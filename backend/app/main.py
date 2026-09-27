"""PlantDoctor server entry point.

Layout:

* ``/api/v1/*``  the versioned application API (auth, users, knowledge, …)
* ``/health*``   liveness/readiness probes
* legacy knowledge-base routes are mounted unchanged at the root so existing
  clients keep working exactly as before.

Start with::

    uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse

from app.core.config import get_settings
from app.core.env import ensure_env_loaded
from app.core.errors import install_error_handlers
from app.core.logging_config import get_logger, setup_logging
from app.core.middleware import install_middleware

ensure_env_loaded()

log = get_logger("plantdoctor.server")

DESCRIPTION = """
Central backend for the PlantDoctor mobile application.

**Everything except the probes and the read-only knowledge base requires a
bearer access token obtained from `/api/v1/auth/login`.**

### Authentication flow

1. `POST /api/v1/auth/register` - create an account (status `PENDING_VERIFICATION`)
2. `POST /api/v1/auth/request-otp` - email a 6-digit OTP
3. `POST /api/v1/auth/verify-otp` - activate the account
4. `POST /api/v1/auth/login` - receive `access_token` + `refresh_token`
5. `POST /api/v1/auth/refresh` - rotate the pair when the access token expires
6. `POST /api/v1/auth/logout` or `/logout-all` - revoke

Send the access token as `Authorization: Bearer <access_token>`.

### Knowledge integrity

Records served by `/api/v1/plants`, `/diseases`, `/treatments` and `/medicines`
carry `verification_status` and `sources`. Only `VERIFIED` records are returned
by default. Where information is unavailable the API returns an explicit
`unverified` marker instead of a generated answer. Treatment dosage is only
exposed when it is backed by a registered product label.

### Diagnosis

Results from `POST /api/v1/diagnosis` are **AI predictions**, never confirmed
diagnoses. The response keeps `prediction` and `verified_knowledge` in separate
objects so a client cannot conflate them.
"""

TAGS_METADATA: list[dict[str, Any]] = [
    {"name": "health", "description": "Liveness and dependency checks."},
    {"name": "auth", "description": "Registration, login, OTP, password reset, sessions."},
    {"name": "users", "description": "The signed-in user's own profile."},
    {"name": "plants", "description": "Plant and species knowledge base."},
    {"name": "diseases", "description": "Disease knowledge base."},
    {"name": "symptoms", "description": "Symptom and cause knowledge base."},
    {"name": "treatments", "description": "Treatment knowledge base."},
    {"name": "medicines", "description": "Registered products and active ingredients."},
    {"name": "doctors", "description": "Agricultural experts and advisors."},
    {"name": "diagnosis", "description": "Image upload and AI screening results."},
    {"name": "my-plants", "description": "The signed-in user's saved plants."},
    {"name": "admin", "description": "Administrative management. Requires a staff role."},
    {"name": "sources", "description": "Provenance registry for every knowledge record."},
]


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    setup_logging(settings.LOG_LEVEL, fmt=settings.LOG_FORMAT, log_file=settings.LOG_FILE)
    settings.assert_secrets_present()

    from app.database.session import wait_for_database

    wait_for_database()

    log.info(
        "server_starting name=%s version=%s environment=%s",
        settings.PROJECT_NAME,
        settings.VERSION,
        settings.ENVIRONMENT,
    )
    try:
        yield
    finally:
        from app.database.session import dispose_engine

        dispose_engine()
        log.info("server_stopped")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title=settings.PROJECT_NAME,
        version=settings.VERSION,
        description=DESCRIPTION,
        openapi_tags=TAGS_METADATA,
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
        contact={"name": "PlantDoctor"},
        license_info={"name": "Proprietary"},
    )

    install_error_handlers(app, expose_internals=settings.DEBUG and not settings.is_production)
    install_middleware(app, settings)

    from app.api.v1.router import api_router

    app.include_router(api_router, prefix=settings.API_V1_PREFIX)
    app.include_router(health_router())

    if settings.ENABLE_LEGACY_KNOWLEDGE_ROUTES:
        _mount_legacy(app)

    @app.get("/", include_in_schema=False)
    async def root() -> RedirectResponse:
        return RedirectResponse(url="/docs")

    return app


def health_router():
    from app.api.v1.health import router

    return router


def _mount_legacy(app: FastAPI) -> None:
    """Serve the pre-existing knowledge-base API at the root, unchanged.

    The legacy app owns its own psycopg pool and its own settings loader; it is
    imported lazily and its failure must never stop the new server booting.
    """
    try:
        from plantdoctor_api.main import app as legacy_app
    except Exception as exc:  # pragma: no cover - optional compatibility path
        log.error("legacy_app_not_mounted error=%s", type(exc).__name__)
        return
    app.mount("/legacy", legacy_app)
    log.info("legacy_knowledge_app_mounted at=/legacy")


app = create_app()


@app.middleware("http")
async def _reject_oversized_bodies(request: Request, call_next):  # noqa: ANN001, ANN201
    """Cheap pre-flight guard for JSON bodies; files are validated in storage."""
    max_json = 2 * 1024 * 1024
    content_length = request.headers.get("content-length")
    content_type = request.headers.get("content-type", "")
    if content_length and content_length.isdigit() and "multipart" not in content_type:
        if int(content_length) > max_json:
            from app.core.errors import ErrorCode, error_payload

            return app_error_response(request, ErrorCode.FILE_TOO_LARGE, max_json)
    return await call_next(request)


def app_error_response(request: Request, code: str, limit: int):  # noqa: ANN201
    from fastapi.responses import JSONResponse

    from app.core.errors import error_payload

    return JSONResponse(
        status_code=413,
        content=error_payload(
            code,
            f"Request body exceeds the {limit} byte limit.",
            request_id=getattr(request.state, "request_id", None),
        ),
    )


# Environment overrides must be visible to uvicorn workers that fork later.
if os.environ.get("PLANTDOCTOR_FORCE_IPV6"):  # pragma: no cover - rarely used
    os.environ.setdefault("UV_SERVER_HOST", "::")
