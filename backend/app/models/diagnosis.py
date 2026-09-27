"""Diagnosis records.

The critical design rule (spec rule 9) is structural, not documentary:

* :class:`DiagnosisResult` holds **only** model output. Every row has
  ``is_prediction = True`` and an ``EvidenceSource.AI_INFERRED`` marker, and a
  ``model_name`` / ``model_version``.
* :class:`VerifiedKnowledgeLink` holds text that came from the verified
  knowledge base, keyed to a real ``diseases`` / ``symptoms`` / ``treatments``
  row with its own ``verification_status`` and ``source_id``.

The API serialises these into two different objects, ``prediction`` and
``verified_knowledge``. There is no code path that mixes them, so a client
cannot render a model guess as a confirmed finding.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin, UUIDPrimaryKeyMixin
from app.models.enums import (
    DiagnosisStatus,
    EvidenceSource,
    HealthGrade,
    ResultKind,
)


class Diagnosis(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    __tablename__ = "diagnoses"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    status: Mapped[DiagnosisStatus] = mapped_column(
        String(16), nullable=False, default=DiagnosisStatus.PENDING, index=True
    )
    status_detail: Mapped[str | None] = mapped_column(String(200))

    #: Which analysis produced the predictions. Required, so a result can
    #: never be attributed to an unknown model.
    model_name: Mapped[str | None] = mapped_column(String(80))
    model_version: Mapped[str | None] = mapped_column(String(40))
    #: Where the analysis ran: on-device (the current Flutter engine) or server.
    analysis_location: Mapped[str] = mapped_column(
        String(16), nullable=False, default="client", server_default=text("'client'")
    )
    analysis_duration_ms: Mapped[int | None] = mapped_column(Integer)
    client_app_version: Mapped[str | None] = mapped_column(String(32))
    device_id: Mapped[str | None] = mapped_column(String(128))

    #: What the user said, verbatim. Not a diagnosis.
    user_notes: Mapped[str | None] = mapped_column(Text)
    user_reported_symptoms: Mapped[list | None] = mapped_column(JSONB)
    region_hint: Mapped[str | None] = mapped_column(String(120))

    #: Health index reported by the client engine (0-100, experimental metric).
    health_index: Mapped[int | None] = mapped_column(Integer)
    health_grade: Mapped[HealthGrade | None] = mapped_column(String(24))

    #: Set once a human expert has reviewed the case.
    reviewed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    review_notes: Mapped[str | None] = mapped_column(Text)

    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(String(200))

    saved_plant_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("saved_plants.id", ondelete="SET NULL"), nullable=True, index=True
    )

    #: ``diagnoses`` has two foreign keys to ``users`` (the owner and the
    #: reviewing expert), so both relationships must name their own column or
    #: SQLAlchemy cannot pick a join.
    user = relationship("User", lazy="selectin", foreign_keys=[user_id])
    reviewer = relationship("User", lazy="selectin", foreign_keys=[reviewed_by])
    images: Mapped[list["DiagnosisImage"]] = relationship(
        back_populates="diagnosis", cascade="all, delete-orphan", order_by="DiagnosisImage.position"
    )
    results: Mapped[list["DiagnosisResult"]] = relationship(
        back_populates="diagnosis", cascade="all, delete-orphan", order_by="DiagnosisResult.id"
    )
    actions: Mapped[list["DiagnosisAction"]] = relationship(
        back_populates="diagnosis", cascade="all, delete-orphan", order_by="DiagnosisAction.sort_order"
    )
    knowledge: Mapped[list["VerifiedKnowledgeLink"]] = relationship(
        back_populates="diagnosis", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_diagnoses_user_created", "user_id", "created_at"),
        Index(
            "ix_diagnoses_active",
            "user_id",
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )


class DiagnosisImage(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "diagnosis_images"

    diagnosis_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("diagnoses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    stored_file_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("stored_files.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    #: whole_plant | leaf | stem | fruit | soil | other
    subject_type: Mapped[str | None] = mapped_column(String(24))
    captured_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    #: Per-image client quality verdict, kept verbatim for reproducibility.
    client_quality: Mapped[dict | None] = mapped_column(JSONB)
    client_measurements: Mapped[dict | None] = mapped_column(JSONB)
    is_primary: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )

    diagnosis = relationship("Diagnosis", back_populates="images")
    stored_file = relationship("StoredFile", lazy="selectin")

    __table_args__ = (
        Index("uq_diagnosis_image_position", "diagnosis_id", "position", unique=True),
    )


class DiagnosisResult(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """A single model output. Never a confirmed diagnosis."""

    __tablename__ = "diagnosis_results"

    diagnosis_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("diagnoses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[ResultKind] = mapped_column(String(32), nullable=False, index=True)
    label: Mapped[str] = mapped_column(String(200), nullable=False)
    confidence: Mapped[float | None] = mapped_column(Float)
    #: Rank among candidates of the same kind, 1 = best.
    rank: Mapped[int | None] = mapped_column(Integer)
    explanation: Mapped[str | None] = mapped_column(Text)

    #: Always true. A default of ``false`` would let a bug quietly promote a
    #: prediction into a confirmed finding.
    is_prediction: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    evidence_source: Mapped[EvidenceSource] = mapped_column(
        String(24), nullable=False, default=EvidenceSource.AI_INFERRED
    )
    model_name: Mapped[str | None] = mapped_column(String(80))
    model_version: Mapped[str | None] = mapped_column(String(40))

    raw_output: Mapped[dict | None] = mapped_column(JSONB)

    #: Optional link to a knowledge-base row this prediction resembles. A link
    #: is a pointer, not a confirmation.
    candidate_disease_id: Mapped[int | None] = mapped_column(
        ForeignKey("diseases.id", ondelete="SET NULL"), nullable=True, index=True
    )
    candidate_plant_id: Mapped[int | None] = mapped_column(
        ForeignKey("plants.id", ondelete="SET NULL"), nullable=True, index=True
    )
    candidate_pest_id: Mapped[int | None] = mapped_column(
        ForeignKey("pests.id", ondelete="SET NULL"), nullable=True, index=True
    )

    diagnosis = relationship("Diagnosis", back_populates="results")
    symptoms: Mapped[list["DiagnosisSymptom"]] = relationship(
        back_populates="result", cascade="all, delete-orphan"
    )

    __table_args__ = (
        # Composite index for the "candidates for this diagnosis, best first"
        # query. Named distinctly from the single-column ix_diagnosis_results_kind
        # that ``index=True`` on ``kind`` generates, because two indexes in one
        # table cannot share a name.
        Index("ix_diagnosis_results_diag_kind_rank", "diagnosis_id", "kind", "rank"),
    )


class DiagnosisSymptom(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "diagnosis_symptoms"

    result_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("diagnosis_results.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: Knowledge-base symptom, when the label matched one.
    symptom_id: Mapped[int | None] = mapped_column(
        ForeignKey("symptoms.id", ondelete="SET NULL"), nullable=True, index=True
    )
    label: Mapped[str] = mapped_column(String(200), nullable=False)
    part: Mapped[str | None] = mapped_column(String(24))
    confidence: Mapped[float | None] = mapped_column(Float)
    is_primary: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    evidence_source: Mapped[EvidenceSource] = mapped_column(
        String(24), nullable=False, default=EvidenceSource.AI_INFERRED
    )
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    result = relationship("DiagnosisResult", back_populates="symptoms")


class DiagnosisAction(UUIDPrimaryKeyMixin, Base):
    """A recommended next step.

    ``source`` names where the advice came from. Advice derived from a verified
    treatment record is labelled as such; advice that is generic preventive
    guidance is labelled ``GENERAL`` and carries no claim of clinical authority.
    """

    __tablename__ = "diagnosis_actions"

    diagnosis_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("diagnoses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: remove_affected_leaves | isolate_plant | improve_airflow | reduce_watering |
    #: seek_expert_advice | monitor | no_action_required
    action_type: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    instruction: Mapped[str] = mapped_column(Text, nullable=False)
    rationale: Mapped[str | None] = mapped_column(Text)
    urgency: Mapped[str] = mapped_column(
        String(16), nullable=False, default="routine", server_default=text("'routine'")
    )
    is_medical_advice: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )
    source_reference_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("source_references.id", ondelete="SET NULL"), nullable=True
    )
    source_name: Mapped[str | None] = mapped_column(String(200))
    source_url: Mapped[str | None] = mapped_column(String(500))
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    diagnosis = relationship("Diagnosis", back_populates="actions")

    __table_args__ = (Index("ix_diagnosis_actions_order", "diagnosis_id", "sort_order"),)


class VerifiedKnowledgeLink(UUIDPrimaryKeyMixin, Base):
    """Points at a real knowledge-base row, carrying its verification status.

    This is the only place where a diagnosis touches verified content, and it
    can only *reference* that content: it cannot assert it as a finding.
    """

    __tablename__ = "verified_knowledge_links"

    diagnosis_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("diagnoses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    #: plant | disease | pest | symptom | treatment | medicine
    entity_type: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    entity_id: Mapped[int] = mapped_column(Integer, nullable=False)
    entity_label: Mapped[str] = mapped_column(String(200), nullable=False)
    entity_verification_status: Mapped[str] = mapped_column(
        String(16), nullable=False, doc="Copied at read time from the knowledge base."
    )
    source_id: Mapped[int | None] = mapped_column(
        ForeignKey("sources.id", ondelete="SET NULL"), nullable=True
    )
    source_name: Mapped[str | None] = mapped_column(String(200))
    source_url: Mapped[str | None] = mapped_column(String(500))
    #: The verified text shown alongside the prediction.
    excerpt: Mapped[str | None] = mapped_column(Text)

    diagnosis = relationship("Diagnosis", back_populates="knowledge")

    __table_args__ = (
        Index("uq_verified_link", "diagnosis_id", "entity_type", "entity_id", unique=True),
    )
