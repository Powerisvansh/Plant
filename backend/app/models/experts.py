"""Agricultural experts, credentials and the doctor directory.

Rules enforced by the schema and the service layer:

* Nothing here is ever fabricated. A profile requires a ``source_id`` pointing
  at the knowledge base's ``sources`` registry, or an explicit
  ``verification_status`` below VERIFIED.
* Only ``VERIFIED`` profiles appear in the public directory. A draft expert is
  invisible to ``GET /api/v1/doctors`` by default.
* Contact details are optional and only stored when the expert has published
  them, because publishing a third party's phone number without consent is a
  legal problem, not just a privacy one.
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
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import RecordStatus


class DoctorSpecialization(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "doctor_specializations"

    code: Mapped[str] = mapped_column(String(48), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    plant_disciplines: Mapped[list | None] = mapped_column(JSONB)

    __table_args__ = (UniqueConstraint("code", name="uq_doctor_specialization_code"),)


class Doctor(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "doctors"

    full_name: Mapped[str] = mapped_column(String(160), nullable=False, index=True)
    qualifications: Mapped[str | None] = mapped_column(
        String(300), doc="As published, e.g. 'M.Sc. Agronomy, PhD Plant Pathology'."
    )
    designation: Mapped[str | None] = mapped_column(String(120))
    organization: Mapped[str | None] = mapped_column(String(200), index=True)
    organization_type: Mapped[str | None] = mapped_column(
        String(60), doc="University / government agency / NGO / private practice."
    )

    expertise_summary: Mapped[str | None] = mapped_column(Text)
    bio: Mapped[str | None] = mapped_column(Text)

    country_code: Mapped[str | None] = mapped_column(String(2), index=True)
    region: Mapped[str | None] = mapped_column(String(120))
    city: Mapped[str | None] = mapped_column(String(120))
    service_areas: Mapped[list | None] = mapped_column(JSONB)

    years_of_experience: Mapped[int | None] = mapped_column(Integer)
    languages_spoken: Mapped[list | None] = mapped_column(JSONB)

    #: Stored only when the expert has published it for enquiries.
    public_email: Mapped[str | None] = mapped_column(String(320))
    public_phone_e164: Mapped[str | None] = mapped_column(String(20))
    website_url: Mapped[str | None] = mapped_column(String(500))
    profile_image_file_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stored_files.id", ondelete="SET NULL"), nullable=True
    )

    consultation_available: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    consultation_mode: Mapped[list | None] = mapped_column(
        JSONB, doc="['in_person','video','phone','email']"
    )
    consultation_notes: Mapped[str | None] = mapped_column(Text)

    verification_status: Mapped[RecordStatus] = mapped_column(
        String(16), nullable=False, default=RecordStatus.DRAFT, index=True
    )
    #: Foreign key into the knowledge base `sources` table (BIGINT).
    source_id: Mapped[int | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL"), nullable=True, index=True
    )
    source_url: Mapped[str | None] = mapped_column(String(500))
    source_citation: Mapped[str | None] = mapped_column(Text)

    license_jurisdiction: Mapped[str | None] = mapped_column(String(120))
    license_status: Mapped[str | None] = mapped_column(String(60))

    created_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    verified_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verification_notes: Mapped[str | None] = mapped_column(Text)

    specializations: Mapped[list["DoctorSpecializationLink"]] = relationship(
        back_populates="doctor", cascade="all, delete-orphan", lazy="selectin"
    )
    credentials: Mapped[list["DoctorCredential"]] = relationship(
        back_populates="doctor", cascade="all, delete-orphan", lazy="selectin"
    )

    __table_args__ = (
        # The public directory query: verified, not deleted, alphabetical.
        Index(
            "ix_doctors_public",
            "verification_status",
            "full_name",
            postgresql_where=text("deleted_at IS NULL AND verification_status = 'VERIFIED'"),
        ),
        Index("ix_doctors_location", "country_code", "region"),
    )

    @property
    def is_public(self) -> bool:
        return (
            self.deleted_at is None and self.verification_status == RecordStatus.VERIFIED
        )


class DoctorSpecializationLink(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "doctor_specialization_links"

    doctor_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"), nullable=False, index=True
    )
    specialization_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("doctor_specializations.id", ondelete="CASCADE"), nullable=False, index=True
    )
    is_primary: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    years_in_field: Mapped[int | None] = mapped_column(Integer)

    doctor: Mapped[Doctor] = relationship(back_populates="specializations")
    specialization: Mapped[DoctorSpecialization] = relationship(lazy="selectin")

    __table_args__ = (
        UniqueConstraint("doctor_id", "specialization_id", name="uq_doctor_specialization"),
    )


class DoctorCredential(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Licence or registration evidence.

    ``document_reference`` is a citation, not a file: a licence PDF is personal
    data and is not uploaded by the platform.
    """

    __tablename__ = "doctor_credentials"

    doctor_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"), nullable=False, index=True
    )
    credential_type: Mapped[str] = mapped_column(String(60), nullable=False, index=True)
    credential_name: Mapped[str] = mapped_column(String(200), nullable=False)
    issuing_body: Mapped[str | None] = mapped_column(String(200))
    license_number: Mapped[str | None] = mapped_column(String(120))
    jurisdiction: Mapped[str | None] = mapped_column(String(120))
    issued_on: Mapped[date | None] = mapped_column(Date)
    expires_on: Mapped[date | None] = mapped_column(Date)

    verification_status: Mapped[RecordStatus] = mapped_column(
        String(16), nullable=False, default=RecordStatus.DRAFT
    )
    source_id: Mapped[int | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL"), nullable=True
    )
    document_reference: Mapped[str | None] = mapped_column(String(500))
    notes: Mapped[str | None] = mapped_column(Text)
    verified_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    doctor: Mapped[Doctor] = relationship(back_populates="credentials")


class Expert(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """Links a PlantDoctor account to a doctor profile and to review work."""

    __tablename__ = "experts"

    #: A PlantDoctor account may back at most one expert profile. The index is
    #: PARTIAL on purpose: with a plain UNIQUE index, SQL's "NULL <> NULL" would
    #: let any number of unlinked expert profiles coexist and the constraint
    #: would appear to work while enforcing nothing.
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    doctor_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("doctors.id", ondelete="CASCADE"), nullable=True, index=True
    )
    expertise_areas: Mapped[list | None] = mapped_column(JSONB)
    can_review_knowledge: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    can_review_diagnoses: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    hourly_rate_note: Mapped[str | None] = mapped_column(String(200))
    is_accepting_cases: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    notes: Mapped[str | None] = mapped_column(Text)

    doctor = relationship("Doctor", lazy="selectin")
    user = relationship("User", lazy="selectin")

    __table_args__ = (
        Index(
            "uq_experts_user_id",
            "user_id",
            unique=True,
            postgresql_where=text("user_id IS NOT NULL"),
        ),
        Index(
            "ix_experts_active",
            "is_accepting_cases",
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )
