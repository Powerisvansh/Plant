"""Governance: verification, sources, notifications, audit, settings, backups.

``audit_logs`` and ``admin_actions`` are append-only and use bigint primary
keys so ordering is total and inserts never contend on a UUID index.
``system_settings`` can hold a secret, in which case the value is stored
encrypted-ish (obfuscated at rest) and never returned by the API.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import (
    BigIntPrimaryKeyMixin,
    SoftDeleteMixin,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
)
from app.models.enums import (
    BackupKind,
    BackupStatus,
    RecordStatus,
    SettingValueType,
)
# Registers the knowledge-base mappings so ``relationship("Source")`` and the
# ``ForeignKey("sources.id")`` targets below resolve at mapper configuration.
import app.models.knowledge  # noqa: E402,F401


class DataVerification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """The DRAFT -> REVIEW -> VERIFIED / REJECTED workflow, for any record.

    ``entity_type`` plus either ``entity_uuid`` (an application table) or
    ``entity_id`` (a knowledge-base BIGINT row) identifies the subject. The
    knowledge base keeps its own ``verification_records`` history; this table
    is the single place an administrator works from.
    """

    __tablename__ = "data_verification"

    entity_type: Mapped[str] = mapped_column(
        String(32), nullable=False, index=True,
        doc="plant | disease | symptom | treatment | medicine | doctor | source",
    )
    #: Set for application tables; null for knowledge-base rows.
    entity_uuid: Mapped[uuid.UUID | None] = mapped_column(nullable=True, index=True)
    #: Set for knowledge-base rows (BIGINT primary keys).
    entity_id: Mapped[int | None] = mapped_column(Integer, index=True)
    entity_label: Mapped[str | None] = mapped_column(String(240))

    status: Mapped[RecordStatus] = mapped_column(
        String(16), nullable=False, default=RecordStatus.DRAFT, index=True
    )
    field_name: Mapped[str | None] = mapped_column(
        String(80), doc="Null verifies the whole record; otherwise one field."
    )

    source_id: Mapped[int | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL"), nullable=True, index=True
    )
    source_url: Mapped[str | None] = mapped_column(String(500))
    source_citation: Mapped[str | None] = mapped_column(Text)
    evidence_excerpt: Mapped[str | None] = mapped_column(Text)

    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    verified_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    verification_date: Mapped[date | None] = mapped_column(Date, index=True)
    notes: Mapped[str | None] = mapped_column(Text)

    __table_args__ = (
        Index("ix_data_verification_queue", "entity_type", "status", "created_at"),
        Index(
            "uq_data_verification_live",
            "entity_type",
            "entity_id",
            "field_name",
            unique=True,
            postgresql_where=text("entity_id IS NOT NULL"),
        ),
    )


class SourceReference(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """A citable reference attached to a knowledge record or an action.

    The knowledge base's own ``sources`` / ``source_documents`` tables remain
    the registry; this table records the *specific* citation for a claim, which
    is what specification rule 8 asks for.
    """

    __tablename__ = "source_references"

    source_id: Mapped[int | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL"), nullable=True, index=True
    )
    source_name: Mapped[str] = mapped_column(String(200), nullable=False)
    source_url: Mapped[str | None] = mapped_column(String(500))
    citation: Mapped[str | None] = mapped_column(Text)
    publisher: Mapped[str | None] = mapped_column(String(200))
    published_on: Mapped[date | None] = mapped_column(Date)
    accessed_on: Mapped[date | None] = mapped_column(Date)
    page_reference: Mapped[str | None] = mapped_column(String(120))
    license_name: Mapped[str | None] = mapped_column(String(80))
    notes: Mapped[str | None] = mapped_column(Text)

    knowledge_base = relationship("Source", lazy="selectin")


class Notification(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "notifications"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    notification_type: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str | None] = mapped_column(Text)
    payload: Mapped[dict | None] = mapped_column(JSONB)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (Index("ix_notifications_user_unread", "user_id", "read_at", "created_at"),)


class AuditLog(BigIntPrimaryKeyMixin, Base):
    """Append-only record of every sensitive action.

    Written inside the same transaction as the change it describes, so an
    action cannot succeed without its audit row.
    """

    __tablename__ = "audit_logs"

    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    actor_email: Mapped[str | None] = mapped_column(String(320))
    actor_roles: Mapped[list | None] = mapped_column(JSONB)

    action: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    #: dotted resource path, e.g. "plant_disease", "user", "system_setting"
    resource_type: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    resource_id: Mapped[str | None] = mapped_column(String(80), index=True)
    #: HTTP method and route, e.g. "POST /api/v1/admin/plants"
    http_method: Mapped[str | None] = mapped_column(String(10))
    route: Mapped[str | None] = mapped_column(String(200))
    status_code: Mapped[int | None] = mapped_column(Integer)

    #: Structured, non-secret before/after summary.
    changes: Mapped[dict | None] = mapped_column(JSONB)
    reason: Mapped[str | None] = mapped_column(String(500))
    is_dangerous: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false"), index=True
    )

    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(String(400))
    request_id: Mapped[str | None] = mapped_column(String(64), index=True)

    __table_args__ = (
        Index("ix_audit_logs_actor_time", "actor_user_id", "occurred_at"),
        Index("ix_audit_logs_resource", "resource_type", "resource_id", "occurred_at"),
    )


class AdminAction(BigIntPrimaryKeyMixin, Base):
    """A distinct, queryable view of elevated actions, kept alongside the raw
    audit log so a reviewer can list "who changed what, and why" quickly."""

    __tablename__ = "admin_actions"

    admin_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    admin_email: Mapped[str | None] = mapped_column(String(320))
    action: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    target_id: Mapped[str | None] = mapped_column(String(80))
    #: grant_role | revoke_role | disable_user | enable_user | delete_user |
    #: verify_record | reject_record | import_records | create_backup | update_setting
    reason: Mapped[str | None] = mapped_column(String(500))
    affected_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    details: Mapped[dict | None] = mapped_column(JSONB)
    ip_address: Mapped[str | None] = mapped_column(INET)
    performed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False, index=True
    )

    __table_args__ = (Index("ix_admin_actions_admin_time", "admin_user_id", "performed_at"),)


class SystemSetting(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "system_settings"

    key: Mapped[str] = mapped_column(String(80), unique=True, nullable=False, index=True)
    value: Mapped[dict | str | int | float | bool | None] = mapped_column(JSONB)
    value_type: Mapped[SettingValueType] = mapped_column(
        String(16), nullable=False, default=SettingValueType.JSON
    )
    is_secret: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    description: Mapped[str | None] = mapped_column(Text)
    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    #: Overrides the environment value when set. Used for reversible tuning
    #: without restarting the server.
    restart_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )


class DatabaseBackup(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Inventory of every backup taken, with its checksum.

    The dump file itself lives on disk. This row is what makes a restore
    verifiable: the checksum recorded here must match the file before a restore
    is allowed.
    """

    __tablename__ = "database_backups"

    filename: Mapped[str] = mapped_column(String(200), unique=True, nullable=False, index=True)
    relative_path: Mapped[str] = mapped_column(String(400), nullable=False)
    kind: Mapped[BackupKind] = mapped_column(
        String(20), nullable=False, default=BackupKind.FULL
    )
    status: Mapped[BackupStatus] = mapped_column(
        String(12), nullable=False, default=BackupStatus.RUNNING, index=True
    )
    label: Mapped[str | None] = mapped_column(String(120))
    notes: Mapped[str | None] = mapped_column(Text)

    size_bytes: Mapped[int | None] = mapped_column(BigInteger)
    sha256: Mapped[str | None] = mapped_column(String(64), index=True)
    compression: Mapped[str | None] = mapped_column(String(16))

    schema_revision: Mapped[str | None] = mapped_column(String(64))
    knowledge_migrations: Mapped[int | None] = mapped_column(Integer)
    table_row_counts: Mapped[dict | None] = mapped_column(JSONB)

    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    # Distinct from the single-column ix_database_backups_status that
    # ``index=True`` on ``status`` generates: two indexes in one table cannot
    # share a name, and SQLAlchemy silently keeps only the first.
    __table_args__ = (Index("ix_database_backups_status_started", "status", "started_at"),)


class DataImportBatch(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """One run of ``python -m app.cli import``. Makes every imported row
    attributable and every bad record traceable."""

    __tablename__ = "data_import_batches"

    entity_type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    source_file: Mapped[str] = mapped_column(String(400), nullable=False)
    source_sha256: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    #: knowledge-base import_batches row, when the import used that pipeline.
    knowledge_batch_id: Mapped[int | None] = mapped_column(Integer)

    records_seen: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    records_inserted: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    records_updated: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    records_rejected: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    was_dry_run: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    report: Mapped[dict | None] = mapped_column(JSONB)

    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    notes: Mapped[str | None] = mapped_column(Text)
