from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Plant(Base):
    __tablename__ = "plants"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    common_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    scientific_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    hindi_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    family: Mapped[str | None] = mapped_column(String(200), nullable=True)
    genus: Mapped[str | None] = mapped_column(String(200), nullable=True)
    species: Mapped[str | None] = mapped_column(String(200), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    plant_type: Mapped[str | None] = mapped_column(String(100), nullable=True)
    sunlight: Mapped[str | None] = mapped_column(String(200), nullable=True)
    water_requirement: Mapped[str | None] = mapped_column(String(200), nullable=True)
    soil_requirement: Mapped[str | None] = mapped_column(String(200), nullable=True)
    temperature: Mapped[str | None] = mapped_column(String(200), nullable=True)
    humidity: Mapped[str | None] = mapped_column(String(200), nullable=True)
    fertilizer_information: Mapped[str | None] = mapped_column(Text, nullable=True)
    growing_information: Mapped[str | None] = mapped_column(Text, nullable=True)
    propagation: Mapped[str | None] = mapped_column(Text, nullable=True)
    common_diseases: Mapped[str | None] = mapped_column(Text, nullable=True)
    common_pests: Mapped[str | None] = mapped_column(Text, nullable=True)
    care_information: Mapped[str | None] = mapped_column(Text, nullable=True)
    image: Mapped[str | None] = mapped_column(String(500), nullable=True)
    source: Mapped[str | None] = mapped_column(String(300), nullable=True)
    verification_status: Mapped[str | None] = mapped_column(String(100), nullable=True, default="sample")
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow)
