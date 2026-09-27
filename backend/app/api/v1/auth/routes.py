"""Auth endpoints: register, login, refresh, logout, sessions, password change.

Paths are fixed by the rate limiter's rules (``app.core.rate_limit``): login is
throttled per minute, the OTP endpoints per hour. Renaming one of these paths
silently removes its throttle, so the two files must be changed together.

Every route returns the same envelope as the rest of the API, and every route
gets its own request-scoped session which is committed by ``get_db``.
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request, Response, status
from sqlalchemy.orm import Session

from app.api.deps import AuthSvc, CurrentUser, get_current_user
from app.core.identifiers import mask_email, mask_phone
from app.core.errors import AppError, ErrorCode, NotFoundError, success_payload
from app.security.passwords import verify_password
from app.core.logging_config import get_logger
from app.database.session import get_db
from app.models.identity import User
from app.repositories.user_repository import SessionRepository, UserRepository
from app.schemas.auth import (
    ChangePasswordRequest,
    ChangePasswordResponse,
    LoginRequest,
    LoginResponse,
    LogoutResponse,
    PasswordPolicyResponse,
    PasswordResetResponse,
    RefreshRequest,
    RegisterRequest,
    RegisterResponse,
    RequestOtpRequest,
    RequestOtpResponse,
    ResetPasswordRequest,
    RevokeSessionResponse,
    SessionListResponse,
    SessionView,
    UserSummary,
    VerifyOtpRequest,
    VerifyOtpResponse,
)
from app.services.audit_service import AuditService
from app.services.auth_service import AuthService, ClientInfo
from app.services.otp_service import OtpService
from app.services.user_service import NewUser, UserAlreadyExistsError, UserService

log = get_logger("plantdoctor.api.auth")

router = APIRouter(prefix="/auth", tags=["auth"])

DbSession = Annotated[Session, Depends(get_db)]


def _client(request: Request) -> ClientInfo:
    return ClientInfo.from_request(request)


def _status_value(status: Any) -> str:
    """Read a status column as text.

    The status columns are mapped as ``String``, so SQLAlchemy hands back a
    ``str``; elsewhere an enum instance may be in memory before a refresh. Both
    have to render, and a plain ``.value`` raises on the str.
    """
    return str(getattr(status, "value", status))


def _summary(db: Session, user: User) -> UserSummary:
    """Public projection of a user.

    Takes the session explicitly rather than stashing it in a module global: a
    per-request object in module state would leak between concurrent requests.
    """
    return UserSummary(
        id=user.id,
        full_name=user.full_name,
        email=user.email,
        phone=user.phone_display,
        status=_status_value(user.status),
        roles=sorted(UserRepository(db).role_names(user)),
        is_staff=bool(user.is_staff),
    )


# ----------------------------------------------------------------------
# public
# ----------------------------------------------------------------------


@router.get(
    "/password-policy",
    summary="Password requirements",
    description="Lets the client show the real rules instead of guessing at them.",
)
async def password_policy() -> dict[str, Any]:
    return success_payload(PasswordPolicyResponse.current().model_dump(mode="json"))


@router.post(
    "/register",
    status_code=status.HTTP_201_CREATED,
    summary="Create an account",
    description=(
        "Creates a `PENDING_VERIFICATION` account and returns no tokens. The "
        "caller must complete `POST /auth/request-otp` before the account can "
        "log in. If the address is already registered the response is identical "
        "apart from a generic message, so the endpoint cannot be used to "
        "discover who has an account."
    ),
)
async def register(
    request: Request,
    payload: RegisterRequest,
    response: Response,
    db: DbSession,
) -> dict[str, Any]:
    service = UserService(db)
    client = _client(request)
    try:
        user = service.create_user(
            NewUser(
                full_name=payload.full_name,
                password=payload.password,
                email=payload.email,
                phone=payload.phone,
                role="USER",
                language=payload.language,
                timezone=payload.timezone,
                ip_address=client.ip_address,
                user_agent=client.user_agent,
                terms_accepted=payload.terms_accepted,
            )
        )
    except UserAlreadyExistsError as exc:
        # 409 for a genuine duplicate, but the message never says which part of
        # the request collided.
        response.status_code = status.HTTP_409_CONFLICT
        AuditService.record_standalone(
            action="auth.register_duplicate",
            resource_type="user",
            status_code=409,
            changes={"reason": str(exc.code)},
            ip_address=client.ip_address,
            user_agent=client.user_agent,
        )
        raise AppError(
            "An account with those details already exists.",
            code=exc.code,
            status_code=409,
        ) from exc

    db.commit()
    db.refresh(user)

    body = RegisterResponse(
        user=_summary(db, user),
        status=_status_value(user.status),
        message=(
            "Account created. Check your messages for a verification code to "
            "finish setting up your account."
        ),
    )
    return success_payload(body.model_dump(mode="json"))


@router.post(
    "/login",
    summary="Sign in",
    description=(
        "Returns an access token and a refresh token. Every failure - unknown "
        "address, wrong password, suspended account - deliberately spends the "
        "same Argon2id time and returns a generic message, so neither the "
        "response body nor its timing reveals whether an account exists."
    ),
)
async def login(
    request: Request,
    payload: LoginRequest,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    auth = AuthService(db)
    pair, user = auth.authenticate(
        identifier=payload.identifier, password=payload.password, client=client
    )
    db.commit()

    body = LoginResponse(**pair.as_dict(), user=_summary(db, user))
    return success_payload(body.model_dump(mode="json"))


@router.post(
    "/refresh",
    summary="Rotate the token pair",
    description=(
        "Exchanges a refresh token for a new pair and marks the old token used. "
        "Presenting an already-used token is treated as theft: every session for "
        "that user is revoked and they must sign in again."
    ),
)
async def refresh(
    request: Request,
    payload: RefreshRequest,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    auth = AuthService(db)
    pair, user = auth.refresh(refresh_token=payload.refresh_token, client=client)
    db.commit()

    body = LoginResponse(**pair.as_dict(), user=_summary(db, user))
    return success_payload(body.model_dump(mode="json"))


@router.post(
    "/request-otp",
    summary="Send a one-time code",
    description="Issues a 6-digit OTP for email verification or password recovery.",
)
async def request_otp(
    request: Request,
    payload: RequestOtpRequest,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    result = OtpService(db).request_otp(
        payload.identifier,
        purpose=payload.purpose,
        client_ip=client.ip_address,
        user_agent=client.user_agent,
    )
    db.commit()
    body = RequestOtpResponse(
        sent=True,
        channel=result.channel.value,
        purpose=result.request.purpose.value,
        expires_in=int((result.request.expires_at - result.request.issued_at).total_seconds()),
        message="A verification code has been sent.",
    )
    return success_payload(body.model_dump(mode="json"))


@router.post(
    "/resend-otp",
    summary="Resend the verification code",
    include_in_schema=False,
)
async def resend_otp(
    request: Request,
    payload: RequestOtpRequest,
    db: DbSession,
) -> dict[str, Any]:
    return await request_otp(request, payload, db)


@router.post(
    "/forgot-password",
    summary="Start password reset",
    include_in_schema=False,
)
async def forgot_password(
    request: Request,
    payload: RequestOtpRequest,
    db: DbSession,
) -> dict[str, Any]:
    payload.purpose = "PASSWORD_RESET"
    return await request_otp(request, payload, db)


@router.post(
    "/verify-otp",
    summary="Validate a one-time code",
    description="Verifies a 6-digit code and activates the account when it matches.",
)
async def verify_otp(
    request: Request,
    payload: VerifyOtpRequest,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    otp_request, user = OtpService(db).verify_otp(
        payload.identifier,
        code=payload.code,
        purpose=payload.purpose,
        client_ip=client.ip_address,
        user_agent=client.user_agent,
    )
    db.commit()
    body = VerifyOtpResponse(
        verified=True,
        status=_status_value(user.status),
        user=_summary(db, user),
        message="Verification succeeded.",
    )
    return success_payload(body.model_dump(mode="json"))


@router.post(
    "/reset-password",
    summary="Set a new password after OTP verification",
    description="Completes a password reset after the OTP step is accepted.",
)
async def reset_password(
    request: Request,
    payload: ResetPasswordRequest,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    user = OtpService(db).reset_password(
        identifier=payload.identifier,
        code=payload.code,
        new_password=payload.new_password,
        client_ip=client.ip_address,
        user_agent=client.user_agent,
    )
    db.commit()
    body = PasswordResetResponse(
        changed=True,
        message="Password changed successfully.",
    )
    return success_payload(body.model_dump(mode="json"))


# ----------------------------------------------------------------------
# authenticated
# ----------------------------------------------------------------------


@router.post(
    "/logout",
    summary="Sign out of this device",
    description=(
        "Revokes the current session and every refresh token issued for it. The "
        "endpoint is idempotent: logging out twice is not an error, because the "
        "client may retry after a dropped connection."
    ),
)
async def logout(
    request: Request,
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    revoked = AuthService(db).logout(
        session_id=auth.session_id, user_id=auth.id, client=client
    )
    db.commit()
    return success_payload(
        LogoutResponse(sessions_revoked=revoked).model_dump(mode="json")
    )


@router.post(
    "/logout-all",
    summary="Sign out of every device",
    description=(
        "Revokes every session and refresh token for the account, this device "
        "included, and bumps the state version so no outstanding access token "
        "survives. The client must clear its stored tokens and sign in again."
    ),
)
async def logout_all(
    request: Request,
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    client = _client(request)
    revoked = AuthService(db).logout_all(user_id=auth.id, client=client)
    db.commit()
    return success_payload(
        LogoutResponse(sessions_revoked=revoked).model_dump(mode="json")
    )


@router.get(
    "/sessions",
    summary="List this account's sessions",
    description="Every device signed in to this account, most recently seen first.",
)
async def list_sessions(
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    service = AuthService(db)
    rows = service.list_sessions(auth.user)
    views = [SessionView.from_row(row, current_session_id=auth.session_id) for row in rows]
    body = SessionListResponse(
        sessions=views,
        active_count=sum(1 for v in views if v.is_active),
        max_sessions=getattr(AuthService(db).settings, "MAX_SESSIONS_PER_USER", 10),
    )
    return success_payload(body.model_dump(mode="json"))


@router.delete(
    "/sessions/{session_id}",
    summary="Revoke one session",
    description=(
        "Signs a device out remotely, for example after noticing an unfamiliar "
        "entry in the session list. Returns 404 for a session that belongs to "
        "another account, so ownership is never confirmed."
    ),
)
async def revoke_session(
    session_id: str,
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    import uuid as _uuid

    try:
        target = _uuid.UUID(str(session_id))
    except ValueError as exc:
        raise NotFoundError("That session does not exist.") from exc

    revoked = AuthService(db).revoke_session(
        session_id=target, user_id=auth.id, actor=auth.id, reason="user_requested"
    )
    if not revoked:
        db.rollback()
        raise NotFoundError("That session does not exist or has already ended.")
    db.commit()
    return success_payload(
        RevokeSessionResponse(
            session_id=target,
            revoked=True,
            message="That device has been signed out.",
        ).model_dump(mode="json")
    )


@router.post(
    "/change-password",
    summary="Change the password",
    description=(
        "Requires the current password. On success every session is revoked, "
        "this device included, and the client must sign in again with the new "
        "password. A password change can never be used to extend a session."
    ),
)
async def change_password(
    request: Request,
    payload: ChangePasswordRequest,
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    if not verify_password(payload.current_password, auth.user.password_hash):
        AuditService.record(
            db,
            action="auth.change_password_failed",
            resource_type="user",
            resource_id=auth.id,
            actor_user_id=auth.id,
            status_code=401,
            changes={"reason": "wrong_current_password"},
            ip_address=_client(request).ip_address,
        )
        db.commit()
        raise AppError(
            "Your current password is not correct.",
            code=ErrorCode.INVALID_CREDENTIALS,
            status_code=401,
        )

    client = _client(request)
    revoked = AuthService(db).change_password_and_revoke(
        user=auth.user, new_password=payload.new_password, client=client, actor=auth.id
    )
    db.commit()
    return success_payload(
        ChangePasswordResponse(
            sessions_revoked=revoked,
            signed_out_everywhere=True,
            message="Password changed. Please sign in again.",
        ).model_dump(mode="json")
    )


@router.get(
    "/me",
    summary="The signed-in account",
    description="Used by the app on launch to confirm a stored token still works.",
)
async def me(auth: CurrentUser, db: DbSession) -> dict[str, Any]:
    user = auth.user
    return success_payload(
        {
            "user": _summary(db, user).model_dump(mode="json"),
            "session": {
                "session_id": str(auth.session_id),
                "state_version": auth.state_version,
            },
            "permissions": sorted(auth.permissions),
        }
    )
