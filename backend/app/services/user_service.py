"""User lifecycle: creation, verification, roles, lockout, deletion.

This is the only place that writes a ``User``. Routes and the CLI call in here
so the invariants - at least one identifier, a valid password, exactly the right
initial role, a full audit trail - cannot be bypassed by a new caller.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError, ErrorCode
from app.core.identifiers import mask_email, mask_phone, normalise_email, normalise_phone
from app.core.logging_config import get_logger
from app.core.timeutils import now_utc
from app.models.enums import RecordStatus, SessionRevokeReason, UserStatus
from app.models.identity import User, UserProfile, UserRole
from app.models.session import LoginAttempt
from app.repositories.user_repository import UserRepository
from app.security.passwords import (
    hash_password,
    validate_password_strength,
    verify_password,
)
from app.services.audit_service import AuditService

logger = get_logger(__name__)

#: Progressive lockout. The delay grows with consecutive failures, so a
#: scripted attack gets quadratically slower while an ordinary user who forgets
#: their password waits seconds, not hours.
LOCKOUT_STEPS: tuple[tuple[int, int], ...] = (
    (0, 0),
    (5, 0),
    (6, 30),
    (8, 300),
    (10, 1800),
    (15, 3600),
)


class UserAlreadyExistsError(AppError):
    status_code = 409
    code = ErrorCode.ACCOUNT_EXISTS
    message = "An account with that email or phone number already exists."


class AccountLockedError(AppError):
    status_code = 423
    code = ErrorCode.ACCOUNT_LOCKED
    message = "This account is temporarily locked. Try again later."


class AccountInactiveError(AppError):
    status_code = 403
    code = ErrorCode.ACCOUNT_DISABLED
    message = "This account is not active."


class AccountNotVerifiedError(AppError):
    status_code = 403
    code = ErrorCode.ACCOUNT_NOT_VERIFIED
    message = "Verify your email or phone number before signing in."


class AccountNotFoundError(AppError):
    status_code = 404
    code = ErrorCode.ACCOUNT_NOT_FOUND
    message = "No account matches those details."


@dataclass
class NewUser:
    full_name: str
    password: str
    email: str | None = None
    phone: str | None = None
    role: str = "USER"
    is_verified: bool = False
    language: str = "en"
    timezone: str = "UTC"
    ip_address: str | None = None
    user_agent: str | None = None
    request_id: str | None = None
    terms_accepted: bool = False


class UserService:
    def __init__(self, session: Session) -> None:
        self.session = session
        self.users = UserRepository(session)

    # -- creation -------------------------------------------------------
    def create_user(self, data: NewUser) -> User:
        full_name = (data.full_name or "").strip()
        if not full_name:
            raise AppError("A name is required.", code=ErrorCode.VALIDATION_ERROR, status_code=422)
        if len(full_name) > 160:
            raise AppError("That name is too long.", code=ErrorCode.VALIDATION_ERROR, status_code=422)

        email_normalised = normalise_email(data.email)
        phone_e164, phone_display = normalise_phone(data.phone)
        if not email_normalised and not phone_e164:
            raise AppError(
                "An email address or a phone number is required.",
                code=ErrorCode.VALIDATION_ERROR,
                status_code=422,
            )

        # Policy first, so a weak password is rejected before any DB work.
        validate_password_strength(
            data.password, email=email_normalised, full_name=full_name
        )

        if email_normalised and self.users.email_taken(email_normalised):
            raise UserAlreadyExistsError("That email address is already registered.")
        if phone_e164 and self.users.phone_taken(phone_e164):
            raise UserAlreadyExistsError("That phone number is already registered.")

        role = self.users.get_role(data.role)
        if role is None:
            raise AppError(
                f"Unknown role {data.role!r}. Run: python -m app.cli seed-roles",
                code=ErrorCode.VALIDATION_ERROR,
                status_code=500,
            )

        verified = data.is_verified
        now = now_utc()
        user = User(
            full_name=full_name,
            email=data.email.strip() if data.email else None,
            email_normalised=email_normalised,
            phone_e164=phone_e164,
            phone_display=phone_display,
            password_hash=hash_password(data.password),
            password_changed_at=now,
            status=UserStatus.ACTIVE if verified else UserStatus.PENDING_VERIFICATION,
            email_verified_at=now if (verified and email_normalised) else None,
            phone_verified_at=now if (verified and phone_e164) else None,
            is_active=True,
            is_staff=role.name in {"ADMIN", "SUPER_ADMIN"},
            is_superuser=role.name == "SUPER_ADMIN",
            last_login_ip=data.ip_address,
            terms_accepted_at=now if data.terms_accepted else None,
        )
        self.session.add(user)
        self.session.flush()  # assigns the id, needed for role and profile

        self.users.assign_role(user, role)

        self.session.add(
            UserProfile(
                user_id=user.id,
                locale=data.language,
                timezone=data.timezone,
            )
        )

        AuditService.record(
            self.session,
            action="user.created",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=user.id,
            actor_email=mask_email(email_normalised),
            actor_roles=[role.name],
            changes={
                "full_name": full_name,
                "email": mask_email(email_normalised),
                "phone": mask_phone(phone_e164),
                "role": role.name,
                "verified_at_creation": verified,
            },
            ip_address=data.ip_address,
            user_agent=data.user_agent,
            request_id=data.request_id,
            status_code=201,
        )
        return user

    def create_user_safe(self, data: NewUser) -> User:
        """``create_user`` with the race on the unique index handled.

        Two simultaneous registrations for the same address can both pass the
        ``email_taken`` check; the partial unique index is what actually stops
        the duplicate, and this converts its error into a clean 409.
        """
        try:
            user = self.create_user(data)
            self.session.commit()
        except IntegrityError as exc:
            self.session.rollback()
            constraint = getattr(getattr(exc, "orig", None), "diag", None)
            detail = ""
            if constraint is not None and constraint.constraint_name:
                detail = constraint.constraint_name
            logger.warning("user_create_integrity_error", extra={"constraint": detail})
            raise UserAlreadyExistsError() from exc
        return user

    # -- verification ---------------------------------------------------
    def mark_email_verified(self, user: User) -> None:
        now = now_utc()
        if user.email_verified_at is None:
            user.email_verified_at = now
        self._maybe_activate(user)

    def mark_phone_verified(self, user: User) -> None:
        now = now_utc()
        if user.phone_verified_at is None:
            user.phone_verified_at = now
        self._maybe_activate(user)

    def _maybe_activate(self, user: User) -> None:
        """Activate once *every* supplied identifier is verified.

        A user who gave both an email and a phone has proved control of both; a
        half-proven account must not get in.
        """
        if user.status != UserStatus.PENDING_VERIFICATION:
            return
        pending: list[bool] = []
        if user.email_normalised:
            pending.append(user.email_verified_at is not None)
        if user.phone_e164:
            pending.append(user.phone_verified_at is not None)
        if pending and all(pending):
            user.status = UserStatus.ACTIVE

    def set_status(self, user: User, status: UserStatus, *, reason: str | None = None) -> None:
        previous = user.status
        user.status = status
        if status == UserStatus.DISABLED:
            user.is_active = False
        AuditService.record(
            self.session,
            action="user.status_changed",
            resource_type="user",
            resource_id=user.id,
            changes={"from": str(previous), "to": str(status), "reason": reason},
            actor_user_id=user.id,
            status_code=200,
        )

    # -- password -------------------------------------------------------
    def set_password(
        self,
        user: User,
        new_password: str,
        *,
        revoke_sessions: bool = True,
        actor: uuid.UUID | None = None,
        reason: str | None = None,
    ) -> None:
        validate_password_strength(
            new_password, email=user.email_normalised, full_name=user.full_name
        )
        now = now_utc()
        user.password_hash = hash_password(new_password)
        user.password_changed_at = now
        user.failed_login_count = 0
        user.locked_until = None
        # Deliberately NOT activating the account here. Setting a password is
        # not proof of control of the email or phone; only OTP verification is.
        # Activating on password set would let anyone who can reach a reset
        # endpoint walk a half-registered account straight to ACTIVE.

        AuditService.record(
            self.session,
            action="user.password_changed",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor or user.id,
            changes={"sessions_revoked": revoke_sessions, "reason": reason},
            status_code=200,
        )

    # -- lockout --------------------------------------------------------
    def register_failed_login(
        self, user: User, *, ip_address: str | None, user_agent: str | None
    ) -> None:
        user.failed_login_count = (user.failed_login_count or 0) + 1
        for threshold, delay in reversed(LOCKOUT_STEPS):
            if delay and user.failed_login_count >= threshold:
                user.locked_until = now_utc() + timedelta(seconds=delay)
                logger.warning(
                    "account_locked",
                    extra={
                        "user_id": str(user.id),
                        "failed_count": user.failed_login_count,
                        "locked_seconds": delay,
                    },
                )
                break
        else:
            user.locked_until = None

        self.session.add(
            LoginAttempt(
                user_id=user.id,
                email_normalised=user.email_normalised,
                identifier_used=mask_email(user.email_normalised) or mask_phone(user.phone_e164),
                succeeded=False,
                failure_reason="bad_password",
                ip_address=ip_address,
                user_agent=(user_agent or "")[:400] or None,
            )
        )

    def register_successful_login(
        self, user: User, *, ip_address: str | None, user_agent: str | None
    ) -> None:
        now = now_utc()
        user.failed_login_count = 0
        user.locked_until = None
        user.last_login_at = now
        user.last_login_ip = ip_address
        self.session.add(
            LoginAttempt(
                user_id=user.id,
                email_normalised=user.email_normalised,
                identifier_used=mask_email(user.email_normalised) or mask_phone(user.phone_e164),
                succeeded=True,
                ip_address=ip_address,
                user_agent=(user_agent or "")[:400] or None,
            )
        )

    def record_login_attempt_for_unknown_identifier(
        self,
        identifier: str,
        *,
        success: bool,
        reason: str,
        ip_address: str | None,
        user_agent: str | None,
    ) -> None:
        """Log a login attempt against an address that has no account.

        Without this, a credential-stuffing run against unknown addresses is
        invisible in ``login_attempts``.
        """
        email_norm: str | None = None
        masked: str | None = None
        if identifier and "@" in identifier:
            email_norm = normalise_email(identifier)
            masked = mask_email(email_norm)
        elif identifier:
            masked = (identifier or "")[:320]
        self.session.add(
            LoginAttempt(
                user_id=None,
                email_normalised=email_norm,
                identifier_used=masked,
                succeeded=success,
                failure_reason=reason[:80],
                ip_address=ip_address,
                user_agent=(user_agent or "")[:400] or None,
            )
        )

    # -- roles ----------------------------------------------------------
    def set_roles(
        self,
        user: User,
        role_names: list[str],
        *,
        actor: uuid.UUID | None = None,
        reason: str | None = None,
    ) -> list[str]:
        before = sorted(self.users.role_names(user))
        wanted: list[Role] = []
        for name in role_names:
            role = self.users.get_role(name)
            if role is None:
                raise AppError(
                    f"Unknown role {name!r}. Run: python -m app.cli seed-roles",
                    code=ErrorCode.VALIDATION_ERROR,
                    status_code=422,
                )
            wanted.append(role)
        if not wanted:
            raise AppError(
                "A user must keep at least one role.",
                code=ErrorCode.VALIDATION_ERROR,
                status_code=422,
            )

        for existing in list(user.roles):
            if existing.role is None or existing.role.name not in {r.name for r in wanted}:
                self.session.delete(existing)
        self.session.flush()
        for role in wanted:
            self.users.assign_role(user, role, assigned_by=actor)
        self.session.flush()

        after = sorted(self.users.role_names(user))
        names = {r.name for r in wanted}
        user.is_staff = bool(names & {"ADMIN", "SUPER_ADMIN"})
        user.is_superuser = "SUPER_ADMIN" in names

        AuditService.record(
            self.session,
            action="user.roles_changed",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor,
            changes={"from": before, "to": after, "reason": reason},
            is_dangerous=True,
            status_code=200,
        )
        return after

    def permission_codes(self, user: User) -> set[str]:
        """Every permission the user holds, resolved through their roles."""
        codes: set[str] = set()
        for user_role in user.roles:
            role = user_role.role
            if role is None:
                continue
            for link in role.permissions:
                if link.permission is not None:
                    codes.add(link.permission.code)
        return codes

    # -- deletion -------------------------------------------------------
    def soft_delete(
        self,
        user: User,
        *,
        actor: uuid.UUID | None = None,
        reason: str | None = None,
        anonymise: bool = True,
    ) -> None:
        """Deactivate and anonymise; never drop the row.

        ``audit_logs`` and ``login_attempts`` reference this user, so a hard
        delete would either destroy the evidence trail or be blocked by the
        foreign key. Personal data is overwritten in place instead, which is
        what "delete my account" has to mean to be honest.
        """
        from app.repositories.user_repository import SessionRepository

        now = now_utc()
        user.deleted_at = now
        user.is_active = False
        user.status = UserStatus.DELETED
        user.locked_until = None

        if anonymise:
            # Keep a non-identifying tombstone so the admin log still reads
            # sensibly, but nothing that can reach the person.
            user.full_name = f"Deleted user {user.id.hex[:8]}"
            user.email = None
            user.email_normalised = None
            user.phone_e164 = None
            user.phone_display = None
            # Invalidates every outstanding session and token immediately.
            user.password_hash = "!revoked:" + uuid.uuid4().hex

        for user_role in list(user.roles):
            self.session.delete(user_role)
        if user.profile is not None:
            user.profile.avatar_file_id = None
            user.profile.display_name = None
            user.profile.bio = None
            user.profile.city = None
            user.profile.region = None

        revoked = SessionRepository(self.session).revoke_all(
            user.id, reason=SessionRevokeReason.ACCOUNT_DELETED.value, revoked_at=now
        )
        self.session.flush()

        AuditService.record(
            self.session,
            action="user.deleted",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor,
            changes={"reason": reason, "sessions_revoked": revoked, "anonymised": anonymise},
            reason=reason,
            is_dangerous=True,
            status_code=200,
        )
