"""HTTP middleware: request identity, access log, security headers."""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.config import Settings
from app.core.logging_config import get_logger, new_request_id, request_id_var, user_id_var

log = get_logger("plantdoctor.access")

#: Applied to every response. A conservative baseline that does not assume
#: HTTPS is terminated locally; the reverse proxy may add Strict-Transport.
SECURITY_HEADERS: dict[str, str] = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Resource-Policy": "same-site",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=(), payment=()",
    "X-Permitted-Cross-Domain-Policies": "none",
    # The API returns JSON and images only; never let a browser render it.
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
}

#: Paths whose access-log line is shortened to the fact that they were called.
#: Query strings are never logged anywhere; these routes additionally avoid
#: echoing any identifier so a compromised log file leaks as little as possible.
SENSITIVE_PATH_PREFIXES: tuple[str, ...] = (
    "/api/v1/auth/",
    "/api/v1/admin/",
)


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Assign a request id, time the request, and log one structured line."""

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        incoming = request.headers.get("x-request-id", "")
        request_id = incoming[:64] if incoming.isalnum() and len(incoming) <= 64 else new_request_id()
        request.state.request_id = request_id
        token = request_id_var.set(request_id)
        user_token = user_id_var.set(None)
        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            duration_ms = round((time.perf_counter() - started) * 1000, 2)
            log.exception(
                "request_failed method=%s path=%s duration_ms=%s",
                request.method,
                _safe_path(request),
                duration_ms,
            )
            raise
        finally:
            request_id_var.reset(token)
            user_id_var.reset(user_token)

        duration_ms = round((time.perf_counter() - started) * 1000, 2)
        response.headers["X-Request-ID"] = request_id
        if settings_is_production() and request.url.scheme == "https":
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")

        sensitive = _is_sensitive(request.url.path)
        log.info(
            "request method=%s path=%s status=%s duration_ms=%s client=%s",
            request.method,
            _safe_path(request),
            response.status_code,
            duration_ms,
            _client_ip(request),
            extra={"sensitive_route": sensitive} if sensitive else None,
        )
        return response


def settings_is_production() -> bool:
    from app.core.config import get_settings

    try:
        return get_settings().is_production
    except RuntimeError:  # pragma: no cover - misconfigured state
        return True


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        response = await call_next(request)
        for header, value in SECURITY_HEADERS.items():
            response.headers.setdefault(header, value)
        # Swagger UI and ReDoc need their own assets and inline styles.
        if request.url.path in {"/docs", "/redoc", "/docs/oauth2-redirect"}:
            response.headers["Content-Security-Policy"] = (
                "default-src 'self'; img-src 'self' data: https://fastapi.tiangolo.com; "
                "style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
                "frame-ancestors 'none'"
            )
            response.headers["X-Frame-Options"] = "SAMEORIGIN"
        response.headers["X-PlantDoctor-Version"] = _version()
        return response


def _version() -> str:
    from app.core.config import get_settings

    try:
        return get_settings().VERSION
    except RuntimeError:  # pragma: no cover
        return "unknown"


def _is_sensitive(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in SENSITIVE_PATH_PREFIXES)


def _safe_path(request: Request) -> str:
    """Path only. Query strings can carry identifiers, so they are dropped."""
    return request.url.path


def _client_ip(request: Request) -> str:
    if request.client:
        return request.client.host
    return "unknown"


def install_middleware(app, settings: Settings) -> None:
    from app.core.rate_limit import RateLimitMiddleware
    from starlette.middleware.cors import CORSMiddleware

    if settings.CORS_ORIGINS:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.CORS_ORIGINS,
            allow_credentials=False,  # tokens travel in the Authorization header
            allow_methods=["GET", "POST", "PATCH", "PUT", "DELETE", "OPTIONS"],
            allow_headers=[
                "Authorization",
                "Content-Type",
                "X-Request-ID",
                "X-Device-ID",
                "X-Client-Version",
            ],
            expose_headers=["X-Request-ID", "Retry-After"],
            max_age=600,
        )
    # Middleware runs in reverse registration order, so these are outermost.
    app.add_middleware(SecurityHeadersMiddleware)
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(RateLimitMiddleware, settings=settings)
