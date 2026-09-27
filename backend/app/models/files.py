"""Stored file metadata.

Binary data never goes into PostgreSQL. This table records where a file lives,
what it is, and who may see it; the bytes are on disk behind a
:class:`app.storage.base.StorageBackend`.

The ``safe_filename`` column is the only name used for any path construction.
``original_filename`` is retained for display and is stored as a *sanitised*
value, so a malicious ``../../etc/passwd`` can never be reconstructed.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import FileKind


class StoredFile(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "stored_files"

    owner_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    kind: Mapped[FileKind] = mapped_column(String(32), nullable=False, index=True)

    storage_backend: Mapped[str] = mapped_column(
        String(32), nullable=False, default="filesystem", server_default=text("'filesystem'")
    )
    #: Relative, backend-specific locator (e.g. "diagnosis-images/2026/09/uuid.jpg").
    storage_key: Mapped[str] = mapped_column(String(512), nullable=False, unique=True)

    original_filename: Mapped[str | None] = mapped_column(
        String(255), doc="Sanitised display name. Never used to build a path."
    )
    safe_filename: Mapped[str] = mapped_column(String(160), nullable=False)

    mime_type: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False)
    width: Mapped[int | None] = mapped_column(Integer)
    height: Mapped[int | None] = mapped_column(Integer)

    #: Content digest, used for deduplication and integrity verification.
    sha256: Mapped[str] = mapped_column(String(64), nullable=False, index=True)

    is_public: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    #: Set by the image sniffer when the declared type did not match the bytes.
    content_type_verified: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    is_processed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    processed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    notes: Mapped[str | None] = mapped_column(String(500))

    owner = relationship("User", lazy="selectin")

    __table_args__ = (
        Index("ix_stored_files_owner_kind", "owner_user_id", "kind"),
        Index(
            "ix_stored_files_live",
            "kind",
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )
