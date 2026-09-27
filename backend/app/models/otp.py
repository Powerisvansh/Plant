"""OTP requests and verification attempts.

Security properties enforced by this schema plus
:mod:`app.services.otp_service`:

* The code is stored only as ``code_hash`` - an HMAC-SHA-256 of the code with a
  per-deployment pepper. There is no column that can hold a plaintext OTP, so
  a database dump reveals nothing usable.
* ``target_hash`` is a keyed digest of the destination address, used to look up
  a pending request without storing the address twice in plaintext and to
  throttle per address.
* ``expires_at`` is enforced in the service, and every state transition is
  recorded in :class:`OtpAttempt` so abuse is detectable after the fact.
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
    func,
    text,
)
from sqlalchemy.dialects.postgresql import INET
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import OtpPurpose, VerificationChannel


class OtpRequest(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "otp_requests"

    purpose: Mapped[OtpPurpose] = mapped_column(String(32), nullable=False, index=True)
    channel: Mapped[VerificationChannel] = mapped_column(
        String(8), nullable=False, default=VerificationChannel.EMAIL, index=True
    )
    #: The email address or E.164 number, stored for sending. Never returned.
    target: Mapped[str] = mapped_column(String(320), nullable=False)
    #: Keyed digest of ``target`` for indexed lookup and per-address throttling.
    target_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)

    #: HMAC-SHA-256(code, pepper). Constant-time comparison only.
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True
    )

    attempts_used: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    max_attempts: Mapped[int] = mapped_column(
        Integer, nullable=False, default=5, server_default=text("5")
    )
    resend_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    max_resends: Mapped[int] = mapped_column(
        Integer, nullable=False, default=5, server_default=text("5")
    )

    issued_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    last_sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    invalidated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        doc="Set when a newer OTP is generated, so only the newest code works.",
    )
    invalidated_reason: Mapped[str | None] = mapped_column(String(64))

    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(400))
    provider: Mapped[str | None] = mapped_column(String(32), doc="Provider that delivered it.")
    delivery_reference: Mapped[str | None] = mapped_column(String(120))

    attempts: Mapped[list["OtpAttempt"]] = relationship(
        back_populates="request", cascade="all, delete-orphan", order_by="OtpAttempt.id"
    )

    __table_args__ = (
        Index("ix_otp_requests_lookup", "target_hash", "purpose", "expires_at"),
        Index(
            "ix_otp_requests_pending",
            "target_hash",
            "purpose",
            postgresql_where=text("consumed_at IS NULL AND invalidated_at IS NULL"),
        ),
    )

    @property
    def is_usable(self) -> bool:
        from app.core.timeutils import is_expired

        return (
            self.consumed_at is None
            and self.invalidated_at is None
            and not is_expired(self.expires_at)
            and self.attempts_used < self.max_attempts
        )


class OtpAttempt(UUIDPrimaryKeyMixin, Base):
    """One row per submitted code. Never stores the submitted value."""

    __tablename__ = "otp_attempts"

    otp_request_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("otp_requests.id", ondelete="CASCADE"), nullable=False, index=True
    )
    attempt_number: Mapped[int] = mapped_column(Integer, nullable=False)
    succeeded: Mapped[bool] = mapped_column(Boolean, nullable=False, index=True)
    failure_reason: Mapped[str | None] = mapped_column(String(64))
    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(400))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )

    request: Mapped[OtpRequest] = relationship(back_populates="attempts")

    __table_args__ = (
        Index("ix_otp_attempts_request", "otp_request_id", "attempt_number", unique=True),
    )
