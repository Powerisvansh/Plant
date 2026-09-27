"""Read-only declarative mappings of knowledge-base tables.

The knowledge base is owned by ``backend/migrations/*.sql`` and the raw
``plantdoctor_api`` access layer. These mappings exist for two reasons only:

1. so application tables can declare a real ``ForeignKey`` to a knowledge row
   (and therefore get a genuine referential-integrity guarantee), and
2. so a repository can join across the boundary with the ORM when that is
   clearer than hand-written SQL.

They are declared on a **separate declarative base** so that ``Base.metadata``
contains only the tables Alembic owns. That separation is what stops
``alembic revision --autogenerate`` from ever trying to drop or alter a
knowledge-base table.

Nothing here is writable through the ORM. The knowledge base is edited only via
its own migration and import tooling, which preserves its provenance guarantees.
"""

from __future__ import annotations

from datetime import date, datetime

from app.database.session import Base
from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Numeric,
    String,
    Text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class KnowledgeBase(DeclarativeBase):
    """Read-only view of the knowledge-base schema.

    The mappings join ``Base``'s registry and metadata for two reasons:

    1. an application table can declare a real ``ForeignKey('sources.id')`` and
       have it resolve, so a knowledge row cannot be deleted while an
       application row still points at it; and
    2. an ORM relationship can name ``Source`` as a string.

    They are still never *emitted* by Alembic: ``include_object`` in
    ``alembic/env.py`` returns False for any table outside the application
    allow-list, so autogenerate cannot propose creating, altering or dropping a
    knowledge-base table. ``app/models/__init__.py`` does not re-export them.
    """

    metadata = Base.metadata
    registry = Base.registry


class Source(KnowledgeBase):
    """The provenance registry. Every important claim in the system cites one."""

    __tablename__ = "sources"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    key: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    url: Mapped[str | None] = mapped_column(String(500))
    source_type: Mapped[str] = mapped_column(String(48), nullable=False)
    organization: Mapped[str | None] = mapped_column(String(200))
    authors: Mapped[str | None] = mapped_column(Text)
    license: Mapped[str | None] = mapped_column(String(48))
    license_url: Mapped[str | None] = mapped_column(String(500))
    attribution_required: Mapped[bool] = mapped_column(Boolean, default=False)
    attribution_template: Mapped[str | None] = mapped_column(Text)
    terms_url: Mapped[str | None] = mapped_column(String(500))
    citation: Mapped[str | None] = mapped_column(Text)
    date_accessed: Mapped[date | None] = mapped_column(Date)
    last_verified: Mapped[date | None] = mapped_column(Date)
    approval_status: Mapped[str | None] = mapped_column(String(32))
    is_citable_in_app: Mapped[bool] = mapped_column(Boolean, default=False)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Plant(KnowledgeBase):
    """Referenced for foreign keys only; reads go through ``v_plant_overview``."""

    __tablename__ = "plants"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    scientific_name: Mapped[str] = mapped_column(String(300), nullable=False)
    genus: Mapped[str | None] = mapped_column(String(120))
    family: Mapped[str | None] = mapped_column(String(120))
    verification_status: Mapped[str | None] = mapped_column(String(16))
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False)


class Disease(KnowledgeBase):
    __tablename__ = "diseases"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    pathogen_type: Mapped[str | None] = mapped_column(String(48))
    pathogen_scientific_name: Mapped[str | None] = mapped_column(String(240))
    description: Mapped[str | None] = mapped_column(Text)
    verification_status: Mapped[str | None] = mapped_column(String(16))
    last_verified: Mapped[date | None] = mapped_column(Date)
    source_id: Mapped[int | None] = mapped_column(ForeignKey("sources.id", ondelete="SET NULL"))


class Pest(KnowledgeBase):
    __tablename__ = "pests"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    scientific_name: Mapped[str | None] = mapped_column(String(240))
    pest_type: Mapped[str | None] = mapped_column(String(48))
    description: Mapped[str | None] = mapped_column(Text)
    verification_status: Mapped[str | None] = mapped_column(String(16))


class Symptom(KnowledgeBase):
    __tablename__ = "symptoms"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    category: Mapped[str | None] = mapped_column(String(32))
    description: Mapped[str | None] = mapped_column(Text)
    visual_appearance: Mapped[str | None] = mapped_column(Text)
    verification_status: Mapped[str | None] = mapped_column(String(16))


class Treatment(KnowledgeBase):
    __tablename__ = "treatments"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    treatment_type: Mapped[str | None] = mapped_column(String(32))
    summary: Mapped[str | None] = mapped_column(Text)
    is_prescriptive: Mapped[bool] = mapped_column(Boolean, default=False)
    requires_label: Mapped[bool] = mapped_column(Boolean, default=True)
    requires_professional: Mapped[bool] = mapped_column(Boolean, default=False)
    jurisdiction: Mapped[str | None] = mapped_column(String(120))
    restriction_notes: Mapped[str | None] = mapped_column(Text)
    evidence_level: Mapped[str | None] = mapped_column(String(32))
    verification_status: Mapped[str | None] = mapped_column(String(16))
    source_id: Mapped[int | None] = mapped_column(ForeignKey("sources.id", ondelete="SET NULL"))


class TreatmentProduct(KnowledgeBase):
    """A registered product. This is the 'medicine' record."""

    __tablename__ = "treatment_products"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    key: Mapped[str] = mapped_column(String(64), nullable=False)
    product_name: Mapped[str] = mapped_column(String(200), nullable=False)
    product_type: Mapped[str | None] = mapped_column(String(32))
    formulation: Mapped[str | None] = mapped_column(String(80))
    concentration_value: Mapped[float | None] = mapped_column(Numeric(14, 6))
    concentration_unit: Mapped[str | None] = mapped_column(String(24))
    manufacturer: Mapped[str | None] = mapped_column(String(200))
    registration_number: Mapped[str | None] = mapped_column(String(80))
    jurisdiction: Mapped[str | None] = mapped_column(String(120))
    registration_status: Mapped[str | None] = mapped_column(String(32))
    label_url: Mapped[str | None] = mapped_column(String(500))
    hazard_statements: Mapped[str | None] = mapped_column(Text)
    signal_word: Mapped[str | None] = mapped_column(String(48))
    verification_status: Mapped[str | None] = mapped_column(String(16))


class ActiveIngredient(KnowledgeBase):
    __tablename__ = "active_ingredients"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    key: Mapped[str] = mapped_column(String(64), nullable=False)
    common_name: Mapped[str] = mapped_column(String(200), nullable=False)
    chemical_name: Mapped[str | None] = mapped_column(String(240))
    cas_number: Mapped[str | None] = mapped_column(String(24))
    pesticide_class: Mapped[str | None] = mapped_column(String(120))
    mode_of_action: Mapped[str | None] = mapped_column(Text)
    human_toxicity_notes: Mapped[str | None] = mapped_column(Text)
    environmental_warnings: Mapped[str | None] = mapped_column(Text)
    verification_status: Mapped[str | None] = mapped_column(String(16))


#: Names that the knowledge base treats as a first-class "not known" answer.
#: The API returns this instead of generating a value.
UNVERIFIED_NOTICE = (
    "Information not verified. This record has no confirmed source in the "
    "PlantDoctor knowledge base, so no answer is given. Do not act on an "
    "unverified assumption; consult a qualified agricultural expert."
)

TOXICITY_UNKNOWN_NOTICE = (
    "Toxicity information was not found in the available knowledge base. "
    "Do not consume or use medicinally without independent verification."
)

DOSAGE_UNVERIFIED_NOTICE = (
    "No label-verified dosage information is available for this treatment. "
    "Follow the product label and local regulations, or consult a qualified "
    "agricultural advisor. Do not estimate a dilution."
)

AI_PREDICTION_NOTICE = (
    "This is an AI-generated prediction from image analysis, not a confirmed "
    "diagnosis. It is a hypothesis to verify, and it is separated from the "
    "verified knowledge shown alongside it."
)

__all__ = [
    "AI_PREDICTION_NOTICE",
    "ActiveIngredient",
    "Disease",
    "DOSAGE_UNVERIFIED_NOTICE",
    "KnowledgeBase",
    "Pest",
    "Plant",
    "Source",
    "Symptom",
    "TOXICITY_UNKNOWN_NOTICE",
    "Treatment",
    "TreatmentProduct",
    "UNVERIFIED_NOTICE",

]
