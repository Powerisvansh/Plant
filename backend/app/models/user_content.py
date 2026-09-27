"""User-owned content: saved plants, notes and health history.

Ownership is enforced by ``user_id`` on every row plus a composite index, and
by the repository layer, which always filters on the authenticated subject. A
user can never read another user's diagnosis history.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import HealthGrade


class SavedPlant(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "saved_plants"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    nickname: Mapped[str] = mapped_column(String(80), nullable=False)

    #: Link into the knowledge base. Nullable: a user's own plant may not be in it.
    plant_id: Mapped[int | None] = mapped_column(
        ForeignKey("plants.id", ondelete="SET NULL"), nullable=True, index=True
    )
    #: What the user called it, and what they say it is. Never asserted as fact.
    common_name: Mapped[str | None] = mapped_column(String(160))
    scientific_name_claimed: Mapped[str | None] = mapped_column(String(200))
    variety: Mapped[str | None] = mapped_column(String(120))
    #: Free-text identity note, e.g. "the one by the window".
    identity_notes: Mapped[str | None] = mapped_column(String(300))

    image_file_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stored_files.id", ondelete="SET NULL"), nullable=True
    )
    location_note: Mapped[str | None] = mapped_column(String(200))
    is_potted: Mapped[bool | None] = mapped_column(Boolean)
    is_outdoor: Mapped[bool | None] = mapped_column(Boolean)
    planted_on: Mapped[date | None] = mapped_column(Date)
    acquired_on: Mapped[date | None] = mapped_column(Date)
    expected_harvest_on: Mapped[date | None] = mapped_column(Date)

    health_status: Mapped[HealthGrade | None] = mapped_column(String(24))
    latest_health_index: Mapped[int | None] = mapped_column(Integer)
    last_checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    notes: Mapped[str | None] = mapped_column(Text)
    #: Care inputs: soil, pot size, watering schedule reminders.
    care_details: Mapped[dict | None] = mapped_column(JSONB)

    user = relationship("User", lazy="selectin")
    image = relationship("StoredFile", lazy="selectin")
    notes_history: Mapped[list["UserPlantNote"]] = relationship(
        back_populates="plant", cascade="all, delete-orphan", order_by="UserPlantNote.observed_on"
    )
    health_history: Mapped[list["PlantHealthHistory"]] = relationship(
        back_populates="plant",
        cascade="all, delete-orphan",
        order_by="PlantHealthHistory.recorded_at",
    )

    __table_args__ = (
        Index(
            "ix_saved_plants_user_active",
            "user_id",
            "created_at",
            postgresql_where=text("deleted_at IS NULL"),
        ),
        Index("uq_saved_plants_user_nickname", "user_id", "nickname", unique=True),
    )


class UserPlantNote(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "user_plant_notes"

    user_plant_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("saved_plants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    observed_on: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    tags: Mapped[list | None] = mapped_column(JSONB)
    image_file_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stored_files.id", ondelete="SET NULL"), nullable=True
    )

    plant: Mapped[SavedPlant] = relationship(back_populates="notes_history")
    user = relationship("User", lazy="selectin")

    __table_args__ = (Index("ix_user_plant_notes_plant", "user_plant_id", "observed_on"),)


class PlantHealthHistory(UUIDPrimaryKeyMixin, Base):
    """An append-only health reading for one of the user's plants.

    ``source`` records where the number came from, so an experimental on-device
    index is never presented as a clinical measurement.
    """

    __tablename__ = "plant_health_history"

    user_plant_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("saved_plants.id", ondelete="CASCADE"), nullable=False, index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    diagnosis_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("diagnoses.id", ondelete="SET NULL"), nullable=True, index=True
    )

    health_index: Mapped[int | None] = mapped_column(Integer)
    grade: Mapped[HealthGrade | None] = mapped_column(String(24))
    #: client_engine | expert_review | user_self_report
    source: Mapped[str] = mapped_column(
        String(32), nullable=False, default="client_engine", server_default=text("'client_engine'")
    )
    notes: Mapped[str | None] = mapped_column(String(500))
    recorded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    plant = relationship("SavedPlant", back_populates="health_history")
    diagnosis = relationship("Diagnosis", lazy="selectin")

    __table_args__ = (Index("ix_health_history_plant", "user_plant_id", "recorded_at"),)
