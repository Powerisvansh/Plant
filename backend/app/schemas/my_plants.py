from __future__ import annotations

from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class SavedPlantCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    nickname: str = Field(..., min_length=1, max_length=80)
    common_name: str | None = None
    scientific_name_claimed: str | None = None
    variety: str | None = None
    identity_notes: str | None = None
    location_note: str | None = None
    is_potted: bool | None = None
    is_outdoor: bool | None = None
    planted_on: date | None = None
    acquired_on: date | None = None
    expected_harvest_on: date | None = None
    notes: str | None = None
    care_details: dict[str, Any] | None = None


class SavedPlantNoteCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=5000)
    observed_on: datetime | None = None
    tags: list[str] | None = None
    image_file_id: str | None = None


class UserPlantNoteResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_plant_id: str
    user_id: str
    body: str
    observed_on: datetime
    tags: list[str] | None = None
    image_file_id: str | None = None


class SavedPlantResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str | None = None
    nickname: str
    common_name: str | None = None
    scientific_name_claimed: str | None = None
    variety: str | None = None
    identity_notes: str | None = None
    location_note: str | None = None
    is_potted: bool | None = None
    is_outdoor: bool | None = None
    planted_on: date | None = None
    acquired_on: date | None = None
    expected_harvest_on: date | None = None
    notes: str | None = None
    care_details: dict[str, Any] | None = None
    created_at: datetime
    updated_at: datetime
    notes_history: list[UserPlantNoteResponse] = []
    health_history: list[dict[str, Any]] = []
