"""Authentication: issuing, rotating and revoking sessions.

The flow, and why each step exists:

``login``
    Verify the password with Argon2id, then open a server-side session. A session
    row is created *before* any token is minted so a token can never exist
    without a session behind it.

``refresh``
    Rotate. The presented token is marked used and a new one issued in the same
    family. Presenting a token that is already used means it was stolen and
    replayed by someone else, so the entire family is revoked - the legitimate
    user is logged out and must sign in again, and the attacker is locked out.

``logout``
    Revoke the session and every token in it. Client-side token deletion is the
    client's job; the server revoking is what actually matters.

``state_version``
    A per-user counter embedded in every access token and compared on every
    request. Bumping it invalidates every outstanding token in O(1), which is
    what a password reset or an admin disable needs.
"""

from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass
from datetime import timedelta
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.core.config import Settings, get_settings
from app.core.errors import AppError, ErrorCode
from app.core.identifiers import normalise_email, normalise_phone
from app.core.logging_config import get_logger
from app.core.timeutils import now_utc
from app.models.enums import ClientPlatform, SessionRevokeReason, UserStatus
from app.models.identity import User
from app.models.session import RefreshToken, StateVersion, UserSession
from app.repositories.user_repository import SessionRepository, UserRepository
from app.security.passwords import needs_rehash, sha256_digest, verify_password
from app.security.tokens import (
    ACCESS_TOKEN,
    REFRESH_TOKEN,
    TokenPair,
    create_access_token,
    create_refresh_token,
    decode_token,
)
from app.services.audit_service import AuditService
from app.services.user_service import (
    AccountInactiveError,
    AccountLockedError,
    AccountNotVerifiedError,
    UserService,
)

logger = get_logger(__name__)

#: One message for every wrong-identifier / wrong-password case. Distinguishing
#: them would let an attacker enumerate registered addresses.
_GENERIC_LOGIN_FAILURE = "Incorrect email/phone number or password."


class AuthenticatedUser:
    """What a request needs to make an authorisation decision."""

    __slots__ = ("user", "session_id", "roles", "permissions", "token_jti", "state_version")

    def __init__(
        self,
        user: User,
        *,
        session_id: uuid.UUID,
        roles: frozenset[str],
        permissions: frozenset[str],
        token_jti: str,
        state_version: int,
    ) -> None:
        self.user = user
        self.session_id = session_id
        self.roles = roles
        self.permissions = permissions
        self.token_jti = token_jti
        self.state_version = state_version

    @property
    def id(self) -> uuid.UUID:
        return self.user.id

    @property
    def is_staff(self) -> bool:
        return bool(self.roles & {"ADMIN", "SUPER_ADMIN"})

    @property
    def is_superuser(self) -> bool:
        return "SUPER_ADMIN" in self.roles

    def has_permission(self, code: str) -> bool:
        return code in self.permissions

    def has_role(self, *names: str) -> bool:
        return bool(self.roles & {n.upper() for n in names})


@dataclass
class ClientInfo:
    """Everything we learn about the caller, from headers only."""

    ip_address: str | None = None
    user_agent: str | None = None
    device_id: str | None = None
    device_name: str | None = None
    platform: ClientPlatform | None = None
    app_version: str | None = None

    @classmethod
    def from_request(cls, request, *, platform: str | None = None) -> ClientInfo:
        headers = request.headers
        return cls(
            ip_address=getattr(request.state, "client_ip", None),
            user_agent=headers.get("user-agent"),
            device_id=(headers.get("x-device-id") or "").strip()[:128] or None,
            device_name=(headers.get("x-device-name") or "").strip()[:120] or None,
            platform=_parse_platform(platform or headers.get("x-client-platform")),
            app_version=(headers.get("x-app-version") or "").strip()[:32] or None,
        )


def _parse_platform(raw: str | None) -> ClientPlatform | None:
    if not raw:
        return None
    try:
        return ClientPlatform(raw.strip().lower())
    except ValueError:
        # An unknown client must not fail the request; it just is not recorded.
        return None


class AuthService:
    def __init__(self, session: Session, settings: Settings | None = None) -> None:
        self.session = session
        self.settings = settings or get_settings()
        self.users = UserRepository(session)
        self.sessions = SessionRepository(session)
        self.user_service = UserService(session)

    # ------------------------------------------------------------------
    # state version
    # ------------------------------------------------------------------
    def state_version(self, user_id: uuid.UUID) -> int:
        row = self.session.execute(
            select(StateVersion).where(StateVersion.user_id == user_id)
        ).scalar_one_or_none()
        if row is None:
            row = StateVersion(user_id=user_id, version=1)
            self.session.add(row)
            self.session.flush()
        return int(row.version)

    def bump_state_version(
        self, user_id: uuid.UUID, *, reason: str, actor: uuid.UUID | None = None
    ) -> int:
        """Invalidate every outstanding token for a user in one write."""
        result = self.session.execute(
            update(StateVersion)
            .where(StateVersion.user_id == user_id)
            .values(version=StateVersion.version + 1, reason=reason[:120], updated_at=now_utc())
        )
        if result.rowcount == 0:
            # No counter yet: create one already bumped, so the version moves 1 -> 2
            # in every case. Going through the same audit path as the update
            # branch matters, because the first bump is usually a password reset.
            self.session.add(StateVersion(user_id=user_id, version=2, reason=reason[:120]))
            self.session.flush()
            new_version = 2
        else:
            new_version = int(
                self.session.execute(
                    select(StateVersion.version).where(StateVersion.user_id == user_id)
                ).scalar_one()
            )
        AuditService.record(
            self.session,
            action="user.state_version_bumped",
            resource_type="user",
            resource_id=user_id,
            actor_user_id=actor,
            changes={"reason": reason, "new_version": new_version},
            is_dangerous=True,
            status_code=200,
        )
        return new_version

    # ------------------------------------------------------------------
    # login
    # ------------------------------------------------------------------
    def authenticate(
        self,
        *,
        identifier: str,
        password: str,
        client: ClientInfo,
    ) -> tuple[TokenPair, User]:
        email_norm = normalise_email(identifier) if "@" in (identifier or "") else None
        phone_e164 = None
        if email_norm is None and identifier:
            try:
                phone_e164, _ = normalise_phone(identifier)
            except AppError:
                phone_e164 = None

        user = self.users.get_by_identifier(
            email_normalised=email_norm, phone_e164=phone_e164
        )

        if user is None:
            # No account: still spend the time an Argon2id verification would,
            # so response timing does not reveal which addresses exist.
            _burn_password_time(password, self.settings)
            self.user_service.record_login_attempt_for_unknown_identifier(
                identifier,
                success=False,
                reason="unknown_identifier",
                ip_address=client.ip_address,
                user_agent=client.user_agent,
            )
            AuditService.record_standalone(
                action="auth.login_failed",
                resource_type="user",
                status_code=401,
                changes={"reason": "unknown_identifier"},
                ip_address=client.ip_address,
                user_agent=client.user_agent,
            )
            # Commit before raising. The request-scoped session is rolled back
            # when this error propagates, which would discard the very row that
            # makes a credential-stuffing run against unknown addresses visible.
            self.session.commit()
            raise AppError(_GENERIC_LOGIN_FAILURE, code=ErrorCode.INVALID_CREDENTIALS, status_code=401)

        # Locked accounts are checked before the password so a locked account
        # cannot be used as a password oracle.
        if user.is_locked:
            self.session.add(
                _locked_attempt(user, client, "account_locked")
            )
            AuditService.record_standalone(
                action="auth.login_blocked",
                resource_type="user",
                resource_id=user.id,
                actor_user_id=user.id,
                status_code=423,
                changes={"reason": "account_locked"},
                ip_address=client.ip_address,
                user_agent=client.user_agent,
            )
            raise AccountLockedError()

        if not verify_password(password, user.password_hash):
            self.user_service.register_failed_login(
                user, ip_address=client.ip_address, user_agent=client.user_agent
            )
            AuditService.record_standalone(
                action="auth.login_failed",
                resource_type="user",
                resource_id=user.id,
                actor_user_id=user.id,
                status_code=401,
                changes={"reason": "bad_password"},
                ip_address=client.ip_address,
                user_agent=client.user_agent,
            )
            self.session.commit()
            raise AppError(_GENERIC_LOGIN_FAILURE, code=ErrorCode.INVALID_CREDENTIALS, status_code=401)

        if not user.is_active or user.deleted_at is not None:
            self.session.add(_locked_attempt(user, client, "account_disabled"))
            self.session.commit()
            raise AccountInactiveError()

        # ``status`` is a String column, so the value read back is a plain str.
        # It is never identical to the enum member, so these must use == and not
        # is: ``status is UserStatus.X`` is silently False for every account.
        if user.status == UserStatus.PENDING_VERIFICATION:
            self.session.commit()
            raise AccountNotVerifiedError()

        if user.status == UserStatus.DISABLED:
            self.session.commit()
            raise AccountInactiveError("This account has been disabled.")

        # Transparently upgrade the hash if the cost parameters have been raised
        # since this password was last set.
        upgraded_hash: str | None = None
        if needs_rehash(user.password_hash, settings=self.settings):
            from app.security.passwords import hash_password

            upgraded_hash = hash_password(password, settings=self.settings)

        self.user_service.register_successful_login(
            user, ip_address=client.ip_address, user_agent=client.user_agent
        )
        if upgraded_hash:
            user.password_hash = upgraded_hash
            AuditService.record(
                self.session,
                action="user.password_rehashed",
                resource_type="user",
                resource_id=user.id,
                actor_user_id=user.id,
                changes={"reason": "argon2_parameters_upgraded"},
            )

        pair, session_row = self._issue_session(user, client)
        return pair, user

    # ------------------------------------------------------------------
    # session issuance
    # ------------------------------------------------------------------
    def _issue_session(
        self, user: User, client: ClientInfo, *, family_id: uuid.UUID | None = None
    ) -> tuple[TokenPair, UserSession]:
        expires_at = now_utc() + timedelta(days=self.settings.REFRESH_TOKEN_TTL_DAYS)
        record = UserSession(
            user_id=user.id,
            # Placeholder: replaced below once the refresh token exists, since
            # the session row must point at a real token hash.
            session_token_hash="0" * 64,
            device_id=client.device_id,
            device_name=client.device_name,
            platform=client.platform or ClientPlatform.UNKNOWN,
            app_version=client.app_version,
            ip_address=client.ip_address,
            user_agent=(client.user_agent or "")[:400] or None,
            issued_at=now_utc(),
            last_seen_at=now_utc(),
            expires_at=expires_at,
        )
        self.session.add(record)
        self.session.flush()  # assign the session id

        family = family_id or uuid.uuid4()
        pair, refresh_row = self._mint_pair(
            user=user, session_record=record, family_id=family, client=client
        )
        return pair, record

    def _mint_pair(
        self,
        *,
        user: User,
        session_record: UserSession,
        family_id: uuid.UUID,
        client: ClientInfo,
        parent: RefreshToken | None = None,
    ) -> tuple[TokenPair, RefreshToken]:
        roles = sorted(self.users.role_names(user))
        permissions = sorted(self.user_service.permission_codes(user))
        version = self.state_version(user.id)

        access_token, access_expires = create_access_token(
            user_id=user.id,
            session_id=session_record.id,
            roles=roles,
            permissions=permissions,
            state_version=version,
            settings=self.settings,
        )
        refresh_token, refresh_expires, jti, _ = create_refresh_token(
            user_id=user.id,
            session_id=session_record.id,
            family_id=family_id,
            settings=self.settings,
        )

        row = RefreshToken(
            user_id=user.id,
            session_id=session_record.id,
            token_hash=sha256_digest(refresh_token),
            jti=jti,
            # Every token descended from this login carries the same family id.
            # Reuse detection revokes the family, so this must be the *family's*
            # id on every rotation, never a fresh one.
            family_id=family_id,
            issued_at=now_utc(),
            expires_at=refresh_expires,
            parent_id=parent.id if parent else None,
            is_rotated=False,
            ip_address=client.ip_address,
            user_agent=(client.user_agent or "")[:400] or None,
        )
        self.session.add(row)
        self.session.flush()

        if parent is not None:
            parent.used_at = now_utc()
            parent.is_rotated = True
            parent.replaced_by_id = row.id
            session_record.refresh_rotations = (session_record.refresh_rotations or 0) + 1

        # Point the session at the current token so a token hash lookup finds it.
        session_record.session_token_hash = row.token_hash
        session_record.last_seen_at = now_utc()
        session_record.expires_at = refresh_expires

        pair = TokenPair(
            access_token=access_token,
            refresh_token=refresh_token,
            access_expires_at=access_expires,
            refresh_expires_at=refresh_expires,
            session_id=session_record.id,
            expires_in=int((access_expires - now_utc()).total_seconds()),
        )
        return pair, row

    # ------------------------------------------------------------------
    # refresh
    # ------------------------------------------------------------------
    def refresh(
        self, *, refresh_token: str, client: ClientInfo
    ) -> tuple[TokenPair, User]:
        decoded = decode_token(refresh_token, expected_type=REFRESH_TOKEN, settings=self.settings)
        token_hash = sha256_digest(refresh_token)

        row = self.session.execute(
            select(RefreshToken)
            .options(
                selectinload(RefreshToken.session).selectinload(UserSession.user).selectinload(
                    User.roles
                )
            )
            .where(RefreshToken.token_hash == token_hash)
        ).scalar_one_or_none()

        if row is None:
            # Signature verified but no row: the token was revoked by a rotation
            # that deleted the old record, or the DB was restored from an old
            # backup. Treat as theft.
            self._handle_reuse(decoded.subject, decoded.session_id, client, "unknown_token")
            raise AppError(
                "This session is no longer valid. Please sign in again.",
                code=ErrorCode.REFRESH_INVALID,
                status_code=401,
            )

        if row.is_rotated or row.used_at is not None:
            # Replay of an already-consumed token. This is the signal that
            # matters most in token rotation: either the user or an attacker is
            # holding a copy, and we cannot tell which. Revoke the family.
            self._handle_reuse(
                row.user_id, row.session_id, client, "rotated_token_replayed", family_hint=row.family_id
            )
            raise AppError(
                "This session is no longer valid. Please sign in again.",
                code=ErrorCode.TOKEN_REUSE_DETECTED,
                status_code=401,
            )

        if row.revoked_at is not None:
            raise AppError(
                "This session is no longer valid. Please sign in again.",
                code=ErrorCode.TOKEN_REVOKED,
                status_code=401,
            )

        now = now_utc()
        if row.expires_at <= now:
            raise AppError(
                "The session has expired. Please sign in again.",
                code=ErrorCode.TOKEN_EXPIRED,
                status_code=401,
            )

        session_record = row.session
        if session_record is None:
            raise AppError(
                "This session is no longer valid. Please sign in again.",
                code=ErrorCode.REFRESH_INVALID,
                status_code=401,
            )
        if session_record.revoked_at is not None:
            raise AppError(
                "This session is no longer valid. Please sign in again.",
                code=ErrorCode.TOKEN_REVOKED,
                status_code=401,
            )
        if session_record.expires_at <= now:
            raise AppError(
                "The session has expired. Please sign in again.",
                code=ErrorCode.TOKEN_EXPIRED,
                status_code=401,
            )

        user = session_record.user
        if user is None or not user.is_active or user.deleted_at is not None:
            self._handle_reuse(row.user_id, row.session_id, client, "user_inactive")
            raise AccountInactiveError()

        # A changed password bumps the state version, so an old refresh token
        # must stop working even if its row is still present.
        if not self._password_unchanged_since(row, user):
            self._handle_reuse(row.user_id, row.session_id, client, "password_changed")
            raise AppError(
                "The session is no longer valid. Please sign in again.",
                code=ErrorCode.REFRESH_INVALID,
                status_code=401,
            )

        pair, _ = self._mint_pair(
            user=user,
            session_record=session_record,
            family_id=row.family_id,
            client=client,
            parent=row,
        )
        AuditService.record(
            self.session,
            action="auth.token_refreshed",
            resource_type="session",
            resource_id=session_record.id,
            actor_user_id=user.id,
            changes={"rotation": session_record.refresh_rotations},
            ip_address=client.ip_address,
            user_agent=client.user_agent,
            status_code=200,
        )
        return pair, user

    def _password_unchanged_since(self, row: RefreshToken, user: User) -> bool:
        """False when the password was reset after this token was issued."""
        changed_at = user.password_changed_at
        if changed_at is None:
            return True
        issued = row.issued_at
        if issued is None:
            return True
        return changed_at <= issued

    def _handle_reuse(
        self,
        user_id: uuid.UUID,
        session_id: uuid.UUID,
        client: ClientInfo,
        reason: str,
        *,
        family_hint: uuid.UUID | None = None,
    ) -> None:
        """Revoke everything for the user and record why.

        Deliberately user-wide rather than session-wide: if one token has been
        replayed, we cannot prove the rest are safe.
        """
        now = now_utc()
        revoked_sessions = self.sessions.revoke_all(
            user_id, reason=SessionRevokeReason.REUSE_DETECTED.value, revoked_at=now
        )
        if family_hint is not None:
            self.session.execute(
                update(RefreshToken)
                .where(
                    RefreshToken.user_id == user_id,
                    RefreshToken.family_id == family_hint,
                    RefreshToken.revoked_at.is_(None),
                )
                .values(revoked_at=now, revoked_reason=SessionRevokeReason.REUSE_DETECTED.value)
            )
        self.bump_state_version(user_id, reason=f"token_reuse:{reason}")
        self.session.commit()

        logger.error(
            "refresh_token_reuse_detected",
            extra={"user_id": str(user_id), "session_id": str(session_id), "reason": reason},
        )
        AuditService.record_standalone(
            action="auth.token_reuse_detected",
            resource_type="session",
            resource_id=session_id,
            actor_user_id=user_id,
            status_code=401,
            is_dangerous=True,
            changes={
                "reason": reason,
                "sessions_revoked": revoked_sessions,
                "all_sessions_revoked": True,
            },
            ip_address=client.ip_address,
            user_agent=client.user_agent,
        )

    # ------------------------------------------------------------------
    # access token validation
    # ------------------------------------------------------------------
    def authenticate_request(self, access_token: str) -> AuthenticatedUser:
        """Validate an access token and return the caller.

        Checks, in order: signature and expiry, that the session still exists
        and is not revoked, that the account is still active, and that the
        token's ``sv`` claim matches the user's current state version.
        """
        decoded = decode_token(access_token, expected_type=ACCESS_TOKEN, settings=self.settings)

        session_record = self.sessions.get(decoded.session_id)
        if session_record is None or session_record.revoked_at is not None:
            raise AppError(
                "The session is no longer valid. Please sign in again.",
                code=ErrorCode.TOKEN_REVOKED,
                status_code=401,
            )
        if session_record.expires_at <= now_utc():
            raise AppError(
                "The session has expired. Please sign in again.",
                code=ErrorCode.TOKEN_EXPIRED,
                status_code=401,
            )

        user = session_record.user
        if user is None or user.deleted_at is not None or not user.is_active:
            raise AccountInactiveError()

        current_version = self.state_version(user.id)
        if decoded.state_version != current_version:
            raise AppError(
                "The session is no longer valid. Please sign in again.",
                code=ErrorCode.TOKEN_REVOKED,
                status_code=401,
            )

        # Trust the database, not the token, for authorisation. The claims are a
        # cache; if a role was revoked a minute ago the token has not noticed.
        live_permissions = self.user_service.permission_codes(user)
        live_roles = self.users.role_names(user)

        session_record.last_seen_at = now_utc()

        return AuthenticatedUser(
            user,
            session_id=decoded.session_id,
            roles=frozenset(live_roles),
            permissions=frozenset(live_permissions),
            token_jti=decoded.jti,
            state_version=current_version,
        )

    # ------------------------------------------------------------------
    # logout
    # ------------------------------------------------------------------
    def logout(self, *, session_id: uuid.UUID, user_id: uuid.UUID, client: ClientInfo) -> int:
        now = now_utc()
        record = self.sessions.get(session_id)
        revoked = 0
        if record is not None and record.user_id == user_id and record.revoked_at is None:
            record.revoked_at = now
            record.revoked_reason = SessionRevokeReason.LOGOUT
            revoked = 1
        tokens = self.session.execute(
            update(RefreshToken)
            .where(
                RefreshToken.session_id == session_id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=now, revoked_reason=SessionRevokeReason.LOGOUT)
        )
        revoked += int(tokens.rowcount or 0)
        AuditService.record(
            self.session,
            action="auth.logout",
            resource_type="session",
            resource_id=session_id,
            actor_user_id=user_id,
            changes={"rows_revoked": revoked},
            ip_address=client.ip_address,
            user_agent=client.user_agent,
            status_code=200,
        )
        return revoked

    def logout_all(self, *, user_id: uuid.UUID, client: ClientInfo) -> int:
        """Revoke every session on every device, including the caller's.

        The caller's own session goes too. Keeping it alive while revoking all of
        its refresh tokens and bumping its state version would leave the client
        holding an access token that dies on its next call and a refresh token
        that is already dead - a half-signed-out state that is confusing to
        support and no more secure. One honest rule: logout-all signs you out,
        then you sign in again.
        """
        now = now_utc()
        revoked = self.sessions.revoke_all(
            user_id,
            reason=SessionRevokeReason.LOGOUT_ALL.value,
            revoked_at=now,
        )
        self.session.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == user_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now, revoked_reason=SessionRevokeReason.LOGOUT_ALL.value)
        )
        self.bump_state_version(user_id, reason="logout_all")
        AuditService.record(
            self.session,
            action="auth.logout_all",
            resource_type="user",
            resource_id=user_id,
            actor_user_id=user_id,
            changes={"sessions_revoked": revoked, "all_devices_signed_out": True},
            is_dangerous=True,
            ip_address=client.ip_address,
            user_agent=client.user_agent,
            status_code=200,
        )
        return revoked

    def revoke_session(
        self, *, session_id: uuid.UUID, user_id: uuid.UUID, actor: uuid.UUID, reason: str = "user_request"
    ) -> bool:
        now = now_utc()
        record = self.sessions.get(session_id)
        if record is None or record.user_id != user_id:
            return False
        if record.revoked_at is not None:
            return False
        record.revoked_at = now
        record.revoked_reason = SessionRevokeReason.ADMIN_REVOKED
        self.session.execute(
            update(RefreshToken)
            .where(RefreshToken.session_id == session_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now, revoked_reason=SessionRevokeReason.ADMIN_REVOKED)
        )
        AuditService.record(
            self.session,
            action="session.revoked",
            resource_type="session",
            resource_id=session_id,
            actor_user_id=actor,
            reason=reason,
            is_dangerous=True,
            status_code=200,
        )
        return True

    def list_sessions(self, user: User, *, include_revoked: bool = False) -> list[UserSession]:
        return list(self.sessions.list_for_user(user, include_revoked=include_revoked))

    def change_password_and_revoke(
        self,
        *,
        user: User,
        new_password: str,
        client: ClientInfo,
        actor: uuid.UUID | None = None,
    ) -> int:
        """Set a new password and sign out every session, the caller's included.

        The caller has to sign in again with the new password. Keeping the
        current session alive would mean either not bumping the state version
        (so a stolen token survives a password reset, which defeats the point) or
        bumping it and invalidating the caller's own token anyway.

        An earlier version of this method tried to keep the current session and
        un-revoked its refresh token by clearing ``used_at`` and ``is_rotated``.
        That is worse than useless: it un-consumed an already-rotated token, so
        a token the client was told to discard became usable again. There is now
        one rule - a password change ends every session.
        """
        self.user_service.set_password(user, new_password, revoke_sessions=True, actor=actor)
        now = now_utc()
        revoked = self.sessions.revoke_all(
            user.id,
            reason=SessionRevokeReason.PASSWORD_CHANGED.value,
            revoked_at=now,
        )
        self.session.execute(
            update(RefreshToken)
            .where(
                RefreshToken.user_id == user.id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=now, revoked_reason=SessionRevokeReason.PASSWORD_CHANGED.value)
        )
        self.bump_state_version(user.id, reason="password_changed", actor=actor)
        AuditService.record(
            self.session,
            action="auth.password_changed",
            resource_type="user",
            resource_id=user.id,
            actor_user_id=actor or user.id,
            changes={"sessions_revoked": revoked, "signed_out_everywhere": True},
            is_dangerous=True,
            ip_address=client.ip_address,
            user_agent=client.user_agent,
            status_code=200,
        )
        return revoked


# ----------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------


def _burn_password_time(password: str, settings: Settings) -> None:
    """Spend Argon2id time on a hash nobody will check.

    Without this, "no such user" returns in microseconds while a real user takes
    ~100 ms, and the response time alone enumerates registered addresses.
    """
    from argon2 import PasswordHasher

    try:
        PasswordHasher(
            time_cost=settings.ARGON2_TIME_COST,
            memory_cost=settings.ARGON2_MEMORY_COST_KIB,
            parallelism=settings.ARGON2_PARALLELISM,
        ).hash(password)
    except Exception:  # pragma: no cover - best effort
        pass


def _locked_attempt(user: User, client: ClientInfo, reason: str):
    from app.models.session import LoginAttempt

    from app.core.identifiers import mask_email, mask_phone

    return LoginAttempt(
        user_id=user.id,
        email_normalised=user.email_normalised,
        identifier_used=mask_email(user.email_normalised) or mask_phone(user.phone_e164),
        succeeded=False,
        failure_reason=reason,
        ip_address=client.ip_address,
        user_agent=(client.user_agent or "")[:400] or None,
    )
