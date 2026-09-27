"""Reusable declarative mixins."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import BigInteger, DateTime, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database.session import Base


def utcnow() -> datetime:
    """Timezone-aware UTC now. The database columns are TIMESTAMPTZ."""
    return datetime.now(timezone.utc)


def new_uuid() -> uuid.UUID:
    return uuid.uuid4()


class UUIDPrimaryKeyMixin:
    """UUID version 4 primary key.

    Chosen over a serial integer so an id cannot be enumerated from a
    sequential pattern, and so identifiers can be generated client-side.
    """

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=new_uuid, sort_order=-100
    )


class BigIntPrimaryKeyMixin:
    """Monotonic primary key for append-only logs.

    Audit and admin-action rows are high volume and are always read in
    insertion order; a UUID plus a separate index would be strictly worse than
    the native sequence here.
    """

    id: Mapped[int] = mapped_column(
        BigInteger,
        primary_key=True,
        autoincrement=True,
        sort_order=-100,
    )


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class SoftDeleteMixin:
    """Soft deletion.

    Rows are never removed by the API. Personal data is erased in place
    (anonymised) so retention and integrity guarantees still hold; see
    ``AccountService.delete_account``.
    """

    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None


__all__ = [
    "Base",
    "BigIntPrimaryKeyMixin",
    "SoftDeleteMixin",
    "TimestampMixin",
    "UUIDPrimaryKeyMixin",
    "new_uuid",
    "utcnow",
]
