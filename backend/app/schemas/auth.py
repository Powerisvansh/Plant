"""Request and response models for the auth surface.

Validation is split on purpose:

* **Shape and obvious bounds** are declared here as Pydantic constraints, so a
  malformed request is rejected before it reaches a service.
* **Semantic rules** - is this password strong enough, is this address already
  taken, is this account allowed to log in - live in the services, because they
  need the database and the security policy. Duplicating them here would give
  two answers to the same question.

No response model here ever contains ``password_hash``, a raw OTP, or a refresh
token except where the client genuinely needs one to store.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core.identifiers import normalise_email, normalise_phone
from app.core.config import get_settings
from app.models.enums import OtpPurpose

# ----------------------------------------------------------------------
# shared
# ----------------------------------------------------------------------


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class TokenResponse(BaseModel):
    """What the client stores after a successful login or refresh.

    The refresh token rotates on every use, so the client must replace the copy
    it holds with each response rather than keeping the first one it was given.
    """

    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int = Field(description="Access-token lifetime in seconds.")
    access_expires_at: datetime
    refresh_expires_at: datetime
    session_id: uuid.UUID

    @classmethod
    def from_pair(cls, pair: Any) -> "TokenResponse":
        return cls(**pair.as_dict())


class UserSummary(ORMModel):
    """Public view of the caller. Deliberately excludes internal flags and IPs."""

    id: uuid.UUID
    full_name: str
    email: str | None = None
    phone: str | None = None
    status: str
    roles: list[str] = Field(default_factory=list)
    is_staff: bool = False


def _enum_text(value: Any) -> str | None:
    """Render a String-mapped enum column as plain text.

    SQLAlchemy returns a plain ``str`` for these columns, but an enum instance
    may be in memory before a refresh. ``str(SomeEnum.ACTIVE)`` would render
    ``"UserStatus.ACTIVE"`` rather than ``"ACTIVE"``, so unwrap first.
    """
    if value is None:
        return None
    return str(getattr(value, "value", value))


# ----------------------------------------------------------------------
# register
# ----------------------------------------------------------------------


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    password: str = Field(min_length=1, max_length=256)
    email: str | None = Field(default=None, max_length=320)
    phone: str | None = Field(default=None, max_length=32)
    #: An account needs at least one way to be contacted for the OTP step.
    at_least_one_identifier: bool = True
    terms_accepted: bool = False
    language: str = Field(default="en", max_length=8)
    timezone: str = Field(default="UTC", max_length=64)

    @field_validator("full_name")
    @classmethod
    def _clean_name(cls, v: str) -> str:
        cleaned = " ".join(v.split())
        if len(cleaned) < 2:
            raise ValueError("Please enter your full name.")
        return cleaned

    @field_validator("email")
    @classmethod
    def _normalise_email(cls, v: str | None) -> str | None:
        if v is None or not v.strip():
            return None
        return normalise_email(v)

    @field_validator("phone")
    @classmethod
    def _normalise_phone(cls, v: str | None) -> str | None:
        if v is None or not v.strip():
            return None
        e164, _display = normalise_phone(v)
        return e164 or v.strip()

    def model_post_init(self, _context: Any) -> None:
        if self.at_least_one_identifier and not (self.email or self.phone):
            raise ValueError("An email address or phone number is required.")


class RegisterResponse(BaseModel):
    """Registration never returns tokens.

    The account is ``PENDING_VERIFICATION`` and cannot log in until the OTP
    step proves control of the address. Handing out a session here would make
    that step advisory.
    """

    user: UserSummary
    status: str
    next_step: str = "request_otp"
    message: str


# ----------------------------------------------------------------------
# login / refresh
# ----------------------------------------------------------------------


class LoginRequest(BaseModel):
    identifier: str = Field(
        min_length=1,
        max_length=320,
        description="Email address or phone number, in E.164 or local form.",
    )
    password: str = Field(min_length=1, max_length=256)

    @field_validator("identifier")
    @classmethod
    def _clean(cls, v: str) -> str:
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Enter your email address or phone number.")
        return cleaned


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    expires_in: int
    access_expires_at: datetime
    refresh_expires_at: datetime
    session_id: uuid.UUID
    user: UserSummary


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=4096)


# ----------------------------------------------------------------------
# OTP / password recovery
# ----------------------------------------------------------------------


class RequestOtpRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=320)
    purpose: OtpPurpose = OtpPurpose.EMAIL_VERIFICATION

    @field_validator("identifier")
    @classmethod
    def _clean(cls, v: str) -> str:
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Enter your email address or phone number.")
        return cleaned


class VerifyOtpRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=320)
    code: str = Field(min_length=1, max_length=12)
    purpose: OtpPurpose = OtpPurpose.EMAIL_VERIFICATION

    @field_validator("identifier")
    @classmethod
    def _clean(cls, v: str) -> str:
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Enter your email address or phone number.")
        return cleaned


class ResetPasswordRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=320)
    code: str = Field(min_length=1, max_length=12)
    new_password: str = Field(min_length=1, max_length=256)


class RequestOtpResponse(BaseModel):
    sent: bool = True
    channel: str
    purpose: str
    expires_in: int
    message: str


class VerifyOtpResponse(BaseModel):
    verified: bool = True
    status: str
    user: UserSummary
    message: str


class PasswordResetResponse(BaseModel):
    changed: bool = True
    message: str


# ----------------------------------------------------------------------
# logout / sessions
# ----------------------------------------------------------------------


class LogoutResponse(BaseModel):
    signed_out: bool = True
    sessions_revoked: int = 0


class SessionView(ORMModel):
    """One device or app installation, as shown in "your devices"."""

    session_id: uuid.UUID
    device_id: str | None = None
    device_name: str | None = None
    platform: str | None = None
    app_version: str | None = None
    ip_address: str | None = None
    issued_at: datetime
    last_seen_at: datetime | None = None
    expires_at: datetime
    revoked_at: datetime | None = None
    revoke_reason: str | None = None
    refresh_rotations: int = 0
    is_current: bool = False
    is_active: bool = False

    @classmethod
    def from_row(cls, row: Any, *, current_session_id: uuid.UUID | None = None) -> "SessionView":
        from app.core.timeutils import now_utc

        return cls(
            session_id=row.id,
            device_id=row.device_id,
            device_name=row.device_name,
            platform=_enum_text(row.platform),
            app_version=row.app_version,
            ip_address=str(row.ip_address) if row.ip_address is not None else None,
            issued_at=row.issued_at,
            last_seen_at=row.last_seen_at,
            expires_at=row.expires_at,
            revoked_at=row.revoked_at,
            revoke_reason=_enum_text(row.revoked_reason),
            refresh_rotations=int(row.refresh_rotations or 0),
            is_current=row.id == current_session_id,
            is_active=row.revoked_at is None and row.expires_at > now_utc(),
        )


class SessionListResponse(BaseModel):
    sessions: list[SessionView]
    active_count: int
    max_sessions: int


class RevokeSessionResponse(BaseModel):
    session_id: uuid.UUID
    revoked: bool
    message: str


# ----------------------------------------------------------------------
# password change
# ----------------------------------------------------------------------


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=1, max_length=256)
    #: When true the caller is signed out everywhere and must log in again.
    sign_out_other_devices: bool = True

    @field_validator("new_password")
    @classmethod
    def _must_differ(cls, v: str, info) -> str:  # noqa: ANN001
        current = (info.data or {}).get("current_password")
        if current and v == current:
            raise ValueError("The new password must be different from the current one.")
        return v


class ChangePasswordResponse(BaseModel):
    changed: bool = True
    sessions_revoked: int
    signed_out_everywhere: bool
    message: str


class PasswordPolicyResponse(BaseModel):
    """Lets the client show real requirements instead of guessing."""

    min_length: int
    max_length: int
    requires_uppercase: bool
    requires_lowercase: bool
    requires_digit: bool
    requires_symbol: bool
    min_entropy_bits: int | None = None
    rules: list[str]

    @classmethod
    def current(cls) -> "PasswordPolicyResponse":
        s = get_settings()
        return cls(
            min_length=s.PASSWORD_MIN_LENGTH,
            max_length=s.PASSWORD_MAX_LENGTH,
            requires_uppercase=True,
            requires_lowercase=True,
            requires_digit=True,
            requires_symbol=False,
            rules=[
                f"At least {s.PASSWORD_MIN_LENGTH} characters",
                "At least one uppercase letter",
                "At least one lowercase letter",
                "At least one number",
                "Not your email address or your name",
            ],
        )
