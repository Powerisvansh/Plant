"""Liveness and readiness endpoints.

These are unauthenticated on purpose (a load balancer cannot hold a token) and
return no secret material whatsoever.
"""

from __future__ import annotations

import time
from typing import Any

from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.core.config import get_settings
from app.core.errors import ErrorCode
from app.core.logging_config import get_logger
from app.core.rate_limit import backend_status
from app.database.session import get_engine

router = APIRouter(tags=["health"])
log = get_logger("plantdoctor.health")

STARTED_AT = time.time()


@router.get(
    "/health",
    summary="Server status",
    description="Liveness probe. Always 200 while the process is serving.",
)
async def health() -> dict[str, Any]:
    settings = get_settings()
    return {
        "status": "ok",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "environment": settings.ENVIRONMENT,
        "uptime_seconds": round(time.time() - STARTED_AT, 3),
        "api_version": settings.API_V1_PREFIX,
    }


@router.get(
    "/health/database",
    summary="PostgreSQL status",
    description="Checks connectivity, the knowledge-base schema and the app schema.",
)
async def health_database(response: Response) -> dict[str, Any]:
    settings = get_settings()
    checks: dict[str, Any] = {}
    healthy = True
    started = time.perf_counter()

    try:
        engine = get_engine()
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
            checks["connectivity"] = "ok"
            server_version = conn.execute(text("SHOW server_version")).scalar_one()
            checks["server_version"] = str(server_version)

            # The knowledge base is owned by backend/migrations/*.sql and must
            # be present before this server is useful.
            conn.execute(text("SELECT 1 FROM schema_migrations LIMIT 1"))
            applied = conn.execute(text("SELECT count(*) FROM schema_migrations")).scalar_one()
            checks["knowledge_schema"] = "present"
            checks["knowledge_migrations_applied"] = int(applied)
            if int(applied) == 0:
                checks["knowledge_schema"] = "empty"
                healthy = False

            # The application schema is owned by Alembic. Absent before the
            # first `alembic upgrade head` is a pending state, not a failure.
            has_alembic = conn.execute(
                text("SELECT to_regclass('public.alembic_version') IS NOT NULL")
            ).scalar_one()
            if has_alembic:
                checks["app_schema"] = "present"
                checks["app_revision"] = str(
                    conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
                )
            else:
                checks["app_schema"] = "pending"
                checks["app_detail"] = "Run 'alembic upgrade head' to create the app schema."
    except Exception as exc:
        healthy = False
        checks["connectivity"] = "failed"
        # The class name is safe to expose; the message is not.
        checks["error"] = type(exc).__name__
        log.error("database_health_failed error=%s", type(exc).__name__)

    checks["latency_ms"] = round((time.perf_counter() - started) * 1000, 2)
    checks["expected_database"] = settings.build_database_url().rsplit("/", 1)[-1]

    if not healthy:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "unavailable", "error_code": ErrorCode.SERVICE_UNAVAILABLE, "checks": checks}
    return {"status": "ok", "checks": checks}


@router.get(
    "/health/redis",
    summary="Redis status",
    description="Optional dependency. Reports 'disabled' when REDIS_URL is unset.",
)
async def health_redis(response: Response) -> dict[str, Any]:
    settings = get_settings()
    if not settings.effective_redis_url:
        return {
            "status": "disabled",
            "detail": "REDIS_URL is not configured; rate limiting uses the in-process backend.",
        }
    healthy, kind = _probe_redis()
    if not healthy:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {
            "status": "unavailable",
            "error_code": ErrorCode.SERVICE_UNAVAILABLE,
            "backend": kind,
        }
    return {"status": "ok", "backend": kind}


def _probe_redis() -> tuple[bool, str]:
    try:
        import redis
    except ImportError:
        return False, "not-installed"
    try:
        client = redis.Redis.from_url(
            get_settings().effective_redis_url, socket_timeout=2, socket_connect_timeout=2
        )
        client.ping()
        return True, "redis"
    except Exception as exc:
        log.warning("redis_health_failed error=%s", type(exc).__name__)
        return False, "redis"


@router.get("/health/rate-limit", summary="Rate-limit backend status")
async def health_rate_limit() -> dict[str, Any]:
    return {"status": "ok", **backend_status()}
