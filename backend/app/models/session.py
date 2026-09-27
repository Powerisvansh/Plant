"""Sessions and refresh tokens.

Design:

* One :class:`UserSession` per signed-in device/app installation.
* One :class:`RefreshToken` row per issued refresh token, **hashed** with
  SHA-256. The database therefore never holds a usable refresh token.
* Rotation with reuse detection: presenting a refresh token that was already
  rotated is treated as theft. The whole family (the session) is revoked.
* A short-lived ``state_version`` counter on the user invalidates every session
  without a table scan when the password changes or an admin disables an
  account.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import INET, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import ClientPlatform, SessionRevokeReason


class UserSession(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "user_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: SHA-256 of the session id token embedded in the JWT. Enables "sign out
    #: this device" without inspecting a token's contents.
    session_token_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)

    device_id: Mapped[str | None] = mapped_column(String(128), index=True)
    device_name: Mapped[str | None] = mapped_column(String(120))
    platform: Mapped[ClientPlatform] = mapped_column(
        String(16), nullable=False, default=ClientPlatform.UNKNOWN, index=True
    )
    app_version: Mapped[str | None] = mapped_column(String(32))

    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(400))

    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    revoked_reason: Mapped[SessionRevokeReason | None] = mapped_column(String(24))

    #: Access-token lifetime remaining when the session was last used.
    refresh_rotations: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )

    user = relationship("User", lazy="selectin")
    tokens: Mapped[list["RefreshToken"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_user_sessions_user_active", "user_id", "revoked_at", "expires_at"),
    )

    @property
    def is_active(self) -> bool:
        from app.core.timeutils import as_utc, is_expired, now_utc

        if self.revoked_at is not None:
            return False
        return not is_expired(self.expires_at) and (as_utc(self.expires_at) or now_utc()) > now_utc()


class RefreshToken(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: SHA-256 hex digest. A database dump therefore cannot be replayed.
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    #: The JWT ``jti`` claim, for correlation in logs without storing the token.
    jti: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)

    #: All tokens descended from one login share a family id. Rotation walks the
    #: family forward; presenting a token that was already rotated means one of
    #: the holders is an attacker, and the whole family is revoked. Without this
    #: column, reuse detection can only revoke a single session and cannot tell
    #: two legitimate rotations from a replay.
    family_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), nullable=False, index=True
    )

    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    revoked_reason: Mapped[SessionRevokeReason | None] = mapped_column(String(24))

    #: Rotation chain. Lets an investigator reconstruct a token family.
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL"), nullable=True
    )
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("refresh_tokens.id", ondelete="SET NULL"), nullable=True
    )
    #: True once the token has been exchanged. Presenting it again is a reuse.
    is_rotated: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false"), index=True
    )

    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(400))

    session: Mapped[UserSession] = relationship(back_populates="tokens")

    __table_args__ = (Index("ix_refresh_tokens_user_active", "user_id", "revoked_at", "expires_at"),)


class StateVersion(Base):
    """A monotonic per-user counter checked on every token validation.

    Bumping it invalidates every outstanding token for that user in O(1), which
    is what a password reset or an admin "disable account" needs.
    """

    __tablename__ = "user_state_versions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default=text("1")
    )
    reason: Mapped[str | None] = mapped_column(String(120))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class LoginAttempt(Base):
    """Every authentication outcome, for the brute-force detector and audit."""

    __tablename__ = "login_attempts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    email_normalised: Mapped[str | None] = mapped_column(String(320), index=True)
    #: Masked form of whatever was typed (``j***@e***.com``, ``+91*******89``).
    #: Safe to show in an audit view or a support reply. The plaintext belongs in
    #: email_normalised only, and only because brute-force detection has to be
    #: able to group attempts by target.
    identifier_used: Mapped[str | None] = mapped_column(String(320), index=True)
    succeeded: Mapped[bool] = mapped_column(Boolean, nullable=False, index=True)
    failure_reason: Mapped[str | None] = mapped_column(String(64))
    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(400))
    attempted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )

    __table_args__ = (
        Index("ix_login_attempts_lookup", "email_normalised", "attempted_at"),
        Index("ix_login_attempts_ip_time", "ip_address", "attempted_at"),
    )
