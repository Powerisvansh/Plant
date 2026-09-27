"""Error model and the consistent JSON error envelope required by the API spec.

Every failure the mobile app can observe is one of these codes. Internal
exception text, SQL, file paths and stack traces never reach the client in
production; they are logged server-side and correlated by ``request_id``.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("plantdoctor.error")


class ErrorCode:
    """Stable, machine-readable error codes. Never renumber or reuse one."""

    VALIDATION_ERROR = "VALIDATION_ERROR"
    INVALID_CREDENTIALS = "INVALID_CREDENTIALS"
    EMAIL_ALREADY_REGISTERED = "EMAIL_ALREADY_REGISTERED"
    PHONE_ALREADY_REGISTERED = "PHONE_ALREADY_REGISTERED"
    ACCOUNT_EXISTS = "ACCOUNT_EXISTS"
    ACCOUNT_NOT_FOUND = "ACCOUNT_NOT_FOUND"
    ACCOUNT_NOT_VERIFIED = "ACCOUNT_NOT_VERIFIED"
    ACCOUNT_DISABLED = "ACCOUNT_DISABLED"
    ACCOUNT_LOCKED = "ACCOUNT_LOCKED"
    INVALID_OTP = "INVALID_OTP"
    OTP_EXPIRED = "OTP_EXPIRED"
    OTP_ATTEMPT_LIMIT = "OTP_ATTEMPT_LIMIT"
    OTP_RESEND_LIMIT = "OTP_RESEND_LIMIT"
    OTP_RESEND_COOLDOWN = "OTP_RESEND_COOLDOWN"
    OTP_ALREADY_VERIFIED = "OTP_ALREADY_VERIFIED"
    EMAIL_SEND_FAILED = "EMAIL_SEND_FAILED"
    WEAK_PASSWORD = "WEAK_PASSWORD"
    PASSWORD_REUSE = "PASSWORD_REUSE"
    TOKEN_INVALID = "TOKEN_INVALID"
    TOKEN_EXPIRED = "TOKEN_EXPIRED"
    TOKEN_REVOKED = "TOKEN_REVOKED"
    TOKEN_REUSE_DETECTED = "TOKEN_REUSE_DETECTED"
    REFRESH_INVALID = "REFRESH_INVALID"
    UNAUTHENTICATED = "UNAUTHENTICATED"
    FORBIDDEN = "FORBIDDEN"
    INSUFFICIENT_ROLE = "INSUFFICIENT_ROLE"
    NOT_FOUND = "NOT_FOUND"
    CONFLICT = "CONFLICT"
    RATE_LIMITED = "RATE_LIMITED"
    UNSUPPORTED_MEDIA_TYPE = "UNSUPPORTED_MEDIA_TYPE"
    FILE_TOO_LARGE = "FILE_TOO_LARGE"
    IMAGE_INVALID = "IMAGE_INVALID"
    IMAGE_DIMENSIONS_INVALID = "IMAGE_DIMENSIONS_INVALID"
    STORAGE_ERROR = "STORAGE_ERROR"
    VERIFICATION_REQUIRED = "VERIFICATION_REQUIRED"
    RECORD_NOT_VERIFIED = "RECORD_NOT_VERIFIED"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"


class AppError(Exception):
    """Base class for every error the application raises deliberately."""

    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = ErrorCode.VALIDATION_ERROR
    message: str = "The request could not be processed."

    def __init__(
        self,
        message: str | None = None,
        *,
        code: str | None = None,
        status_code: int | None = None,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.message = message or self.message
        self.code = code or self.code
        self.status_code = status_code or self.status_code
        self.details = details or {}
        self.headers = headers or {}
        super().__init__(self.message)


class ValidationError(AppError):
    status_code = 422
    code = ErrorCode.VALIDATION_ERROR
    message = "One or more fields are invalid."


class AuthenticationError(AppError):
    status_code = status.HTTP_401_UNAUTHORIZED
    code = ErrorCode.UNAUTHENTICATED
    message = "Authentication is required."


class PermissionDeniedError(AppError):
    status_code = status.HTTP_403_FORBIDDEN
    code = ErrorCode.INSUFFICIENT_ROLE
    message = "You do not have permission to perform this action."


class NotFoundError(AppError):
    status_code = status.HTTP_404_NOT_FOUND
    code = ErrorCode.NOT_FOUND
    message = "The requested resource was not found."


class ConflictError(AppError):
    status_code = status.HTTP_409_CONFLICT
    code = ErrorCode.CONFLICT
    message = "The request conflicts with the current state of the resource."


class RateLimitedError(AppError):
    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    code = ErrorCode.RATE_LIMITED
    message = "Too many requests. Please try again later."

    def __init__(self, message: str | None = None, *, retry_after: int = 60, **kwargs: Any) -> None:
        headers = dict(kwargs.pop("headers", None) or {})
        headers["Retry-After"] = str(retry_after)
        super().__init__(message, headers=headers, **kwargs)
        self.retry_after = retry_after


class UnverifiedRecordError(AppError):
    status_code = status.HTTP_409_CONFLICT
    code = ErrorCode.RECORD_NOT_VERIFIED
    message = "This record has not been verified and cannot be published."


def error_payload(
    code: str,
    message: str,
    *,
    request_id: str | None = None,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    error: dict[str, Any] = {"code": code, "message": message}
    if details:
        error["details"] = details
    if request_id:
        error["request_id"] = request_id
    return {"success": False, "error": error}


def success_payload(
    data: Any,
    *,
    request_id: str | None = None,
    meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {"success": True, "data": data}
    if meta:
        payload["meta"] = meta
    if request_id:
        payload["meta"] = {**(payload.get("meta") or {}), "request_id": request_id}
    return payload


def request_id_of(request: Request) -> str | None:
    value = getattr(request.state, "request_id", None)
    return str(value) if value else None


def install_error_handlers(app: FastAPI, *, expose_internals: bool = False) -> None:
    """Register handlers producing the single JSON error shape."""

    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError) -> JSONResponse:
        log.warning(
            "app_error code=%s status=%s path=%s message=%s",
            exc.code,
            exc.status_code,
            request.url.path,
            exc.message,
        )
        return JSONResponse(
            status_code=exc.status_code,
            content=error_payload(
                exc.code, exc.message, request_id=request_id_of(request), details=exc.details
            ),
            headers=exc.headers or None,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = {
            401: ErrorCode.UNAUTHENTICATED,
            403: ErrorCode.FORBIDDEN,
            404: ErrorCode.NOT_FOUND,
            405: ErrorCode.VALIDATION_ERROR,
            409: ErrorCode.CONFLICT,
            415: ErrorCode.UNSUPPORTED_MEDIA_TYPE,
            429: ErrorCode.RATE_LIMITED,
        }.get(exc.status_code, ErrorCode.VALIDATION_ERROR)
        detail = exc.detail if isinstance(exc.detail, str) else "Request failed."
        return JSONResponse(
            status_code=exc.status_code,
            content=error_payload(code, detail, request_id=request_id_of(request)),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        fields = [
            {
                "field": ".".join(str(p) for p in err.get("loc", ())[1:]) or "body",
                "message": err.get("msg", "invalid value"),
                "type": err.get("type", "value_error"),
            }
            for err in exc.errors()
        ]
        return JSONResponse(
            status_code=422,
            content=error_payload(
                ErrorCode.VALIDATION_ERROR,
                "One or more fields are invalid.",
                request_id=request_id_of(request),
                details={"fields": fields},
            ),
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        # Log everything, return nothing sensitive.
        log.exception("unhandled_exception path=%s", request.url.path, exc_info=exc)
        message = (
            "An unexpected internal error occurred."
            if not expose_internals
            else f"{type(exc).__name__}: {exc}"
        )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=error_payload(
                ErrorCode.INTERNAL_ERROR, message, request_id=request_id_of(request)
            ),
        )
