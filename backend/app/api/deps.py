"""FastAPI dependencies for authentication and authorisation.

Design rules that these dependencies enforce:

* **A route asks for what it needs.** ``current_user`` gets any authenticated
  caller; ``require_permission("diagnosis.create")`` gets a caller who actually
  holds that permission. Nothing infers authority from the path.
* **Authorisation is read from the database, not the token.** The access token
  carries role and permission claims as a cache, but every request re-reads the
  live rows, so a role revoked a minute ago loses access immediately instead of
  at token expiry.
* **The request id and subject are placed on ``request.state``** so the rate
  limiter, the audit writer and the error envelope can all correlate without
  re-parsing the token.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.core.errors import AppError, AuthenticationError, ErrorCode, PermissionDeniedError
from app.core.logging_config import get_logger
from app.security.rbac import ROLE_BY_NAME
from app.services.auth_service import AuthenticatedUser, AuthService

log = get_logger("plantdoctor.auth")

# auto_error=False so a missing header produces our error envelope rather than
# Starlette's bare {"detail": ...}, which the mobile client does not parse.
bearer_scheme = HTTPBearer(auto_error=False, description="access_token from /auth/login")


def get_auth_service(db: Annotated[Session, Depends(get_db)]) -> AuthService:
    return AuthService(db)


def _extract_token(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None,
) -> str:
    if credentials is None or not credentials.credentials:
        raise AppError(
            "Sign in to continue.",
            code=ErrorCode.UNAUTHENTICATED,
            status_code=401,
            headers={"WWW-Authenticate": "Bearer"},
        )
    if (credentials.scheme or "").lower() != "bearer":
        raise AppError(
            "Authorization header must use the Bearer scheme.",
            code=ErrorCode.UNAUTHENTICATED,
            status_code=401,
            headers={"WWW-Authenticate": "Bearer"},
        )
    return credentials.credentials


def get_current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthenticatedUser:
    """Any valid access token."""
    token = _extract_token(request, credentials)
    auth = service.authenticate_request(token)

    # Consumed by the rate limiter (per-user buckets) and the audit writer.
    request.state.auth_user_id = str(auth.id)
    request.state.auth_session_id = str(auth.session_id)
    request.state.auth_roles = sorted(auth.roles)
    return auth


def get_optional_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    service: Annotated[AuthService, Depends(get_auth_service)],
) -> AuthenticatedUser | None:
    """Same as :func:`get_current_user` but tolerates no token.

    For endpoints that are public yet personalise when a token happens to be
    present. A *malformed or expired* token still raises, because silently
    ignoring it would hide a broken client.
    """
    if credentials is None or not credentials.credentials:
        return None
    return get_current_user(request, credentials, service)


CurrentUser = Annotated[AuthenticatedUser, Depends(get_current_user)]
OptionalUser = Annotated[AuthenticatedUser | None, Depends(get_optional_user)]
AuthSvc = Annotated[AuthService, Depends(get_auth_service)]


def require_permission(*codes: str) -> Callable[[AuthenticatedUser], AuthenticatedUser]:
    """Dependency factory: caller must hold at least one of ``codes``."""
    required = {c.upper() for c in codes}

    def _dependency(auth: CurrentUser) -> AuthenticatedUser:
        if auth.is_superuser:
            return auth
        if not (auth.permissions & required):
            raise PermissionDeniedError(
                f"This action requires one of: {', '.join(sorted(required))}.",
                code=ErrorCode.FORBIDDEN,
                details={"required_any_of": sorted(required)},
            )
        return auth

    return _dependency


def require_all_permissions(*codes: str) -> Callable[[AuthenticatedUser], AuthenticatedUser]:
    """Dependency factory: caller must hold every one of ``codes``."""
    required = {c.upper() for c in codes}

    def _dependency(auth: CurrentUser) -> AuthenticatedUser:
        if auth.is_superuser:
            return auth
        missing = sorted(required - auth.permissions)
        if missing:
            raise PermissionDeniedError(
                "This action requires additional permissions.",
                code=ErrorCode.FORBIDDEN,
                details={"missing": missing},
            )
        return auth

    return _dependency


def require_role(*names: str) -> Callable[[AuthenticatedUser], AuthenticatedUser]:
    """Dependency factory: caller must hold one of ``names``.

    Roles are coarse; permissions are the real gate. This exists for the few
    places where a role is the honest requirement, such as "staff only" admin
    pages, and it deliberately falls back to role-derived permissions so a
    user granted a role without its catalogue links still behaves consistently.
    """
    allowed = {n.upper() for n in names}

    def _dependency(auth: CurrentUser) -> AuthenticatedUser:
        if auth.is_superuser or (auth.roles & allowed):
            return auth
        raise PermissionDeniedError(
            f"This action requires one of these roles: {', '.join(sorted(allowed))}.",
            code=ErrorCode.INSUFFICIENT_ROLE,
            details={"required_any_of": sorted(allowed), "your_roles": sorted(auth.roles)},
        )

    return _dependency


def require_staff(auth: CurrentUser) -> AuthenticatedUser:
    if auth.is_staff or auth.is_superuser:
        return auth
    raise PermissionDeniedError(
        "This action is restricted to staff.",
        code=ErrorCode.INSUFFICIENT_ROLE,
        details={"your_roles": sorted(auth.roles)},
    )


def require_admin(auth: CurrentUser) -> AuthenticatedUser:
    if auth.has_role("SUPER_ADMIN", "ADMIN"):
        return auth
    raise PermissionDeniedError(
        "This action is restricted to administrators.",
        code=ErrorCode.INSUFFICIENT_ROLE,
        details={"your_roles": sorted(auth.roles)},
    )


def require_super_admin(auth: CurrentUser) -> AuthenticatedUser:
    if auth.is_superuser:
        return auth
    raise PermissionDeniedError(
        "This action is restricted to super administrators.",
        code=ErrorCode.INSUFFICIENT_ROLE,
        details={"your_roles": sorted(auth.roles)},
    )


def require_verified(auth: CurrentUser) -> AuthenticatedUser:
    """Account must have proved control of its identifiers."""
    user = auth.user
    if user.status.value == "ACTIVE" and user.is_active:
        return auth
    raise AppError(
        "Verify your account to continue.",
        code=ErrorCode.ACCOUNT_NOT_VERIFIED,
        status_code=403,
    )


def permissions_for_roles(roles: Sequence[str]) -> set[str]:
    """Union of catalogue permissions for the named roles.

    Used by the CLI's reconciliation and by tests that assert the seed is
    internally consistent. Not a request-path authorisation path: that always
    reads the live database.
    """
    out: set[str] = set()
    for role in roles:
        definition = ROLE_BY_NAME.get(role.upper())
        if definition is not None:
            out.update(definition.permissions)
    return out
