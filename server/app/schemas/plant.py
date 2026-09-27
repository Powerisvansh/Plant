from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class PlantBase(BaseModel):
    common_name: str | None = None
    scientific_name: str | None = None
    hindi_name: str | None = None
    family: str | None = None
    genus: str | None = None
    species: str | None = None
    description: str | None = None
    plant_type: str | None = None
    sunlight: str | None = None
    water_requirement: str | None = None
    soil_requirement: str | None = None
    temperature: str | None = None
    humidity: str | None = None
    fertilizer_information: str | None = None
    growing_information: str | None = None
    propagation: str | None = None
    common_diseases: str | None = None
    common_pests: str | None = None
    care_information: str | None = None
    image: str | None = None
    source: str | None = None
    verification_status: str | None = Field(default="sample")


class PlantCreate(PlantBase):
    pass


class PlantRead(PlantBase):
    id: int
    created_at: datetime
    updated_at: datetime
