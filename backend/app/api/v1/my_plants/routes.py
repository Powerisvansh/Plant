from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.api.deps import CurrentUser
from app.core.errors import NotFoundError, success_payload
from app.database.session import get_db
from app.models.user_content import SavedPlant, UserPlantNote
from app.schemas.my_plants import (
    SavedPlantCreateRequest,
    SavedPlantNoteCreateRequest,
    SavedPlantResponse,
    UserPlantNoteResponse,
)

router = APIRouter(prefix="/my-plants", tags=["my-plants"])
DbSession = Annotated[Session, Depends(get_db)]


def _serialise_note(note: UserPlantNote) -> UserPlantNoteResponse:
    return UserPlantNoteResponse(
        id=str(note.id),
        user_plant_id=str(note.user_plant_id),
        user_id=str(note.user_id),
        body=note.body,
        observed_on=note.observed_on,
        tags=list(note.tags or []) if isinstance(note.tags, list) else None,
        image_file_id=str(note.image_file_id) if note.image_file_id else None,
    )


def _serialise_plant(plant: SavedPlant) -> SavedPlantResponse:
    return SavedPlantResponse(
        id=str(plant.id),
        user_id=str(plant.user_id),
        nickname=plant.nickname,
        common_name=plant.common_name,
        scientific_name_claimed=plant.scientific_name_claimed,
        variety=plant.variety,
        identity_notes=plant.identity_notes,
        location_note=plant.location_note,
        is_potted=plant.is_potted,
        is_outdoor=plant.is_outdoor,
        planted_on=plant.planted_on,
        acquired_on=plant.acquired_on,
        expected_harvest_on=plant.expected_harvest_on,
        notes=plant.notes,
        care_details=plant.care_details,
        created_at=plant.created_at,
        updated_at=plant.updated_at,
        notes_history=[_serialise_note(n) for n in getattr(plant, "notes_history", [])],
        health_history=[
            {"id": str(h.id), "health_index": h.health_index, "grade": h.grade, "source": h.source,
             "notes": h.notes, "recorded_at": h.recorded_at.isoformat()}
            for h in getattr(plant, "health_history", [])
        ],
    )


@router.get("", summary="List the current user's saved plants")
async def list_saved_plants(auth: CurrentUser, db: DbSession) -> dict[str, Any]:
    rows = db.execute(
        select(SavedPlant)
        .options(selectinload(SavedPlant.notes_history), selectinload(SavedPlant.health_history))
        .where(SavedPlant.user_id == auth.id, SavedPlant.deleted_at.is_(None))
        .order_by(SavedPlant.created_at.desc())
    ).scalars().all()
    items = [_serialise_plant(plant).model_dump(mode="json") for plant in rows]
    return success_payload(items)


@router.post("", status_code=status.HTTP_201_CREATED, summary="Save a plant")
async def create_saved_plant(
    payload: SavedPlantCreateRequest,
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    plant = SavedPlant(
        user_id=auth.id,
        nickname=payload.nickname.strip(),
        common_name=payload.common_name.strip() if payload.common_name else None,
        scientific_name_claimed=(payload.scientific_name_claimed.strip() if payload.scientific_name_claimed else None),
        variety=payload.variety.strip() if payload.variety else None,
        identity_notes=payload.identity_notes.strip() if payload.identity_notes else None,
        location_note=payload.location_note.strip() if payload.location_note else None,
        is_potted=payload.is_potted,
        is_outdoor=payload.is_outdoor,
        planted_on=payload.planted_on,
        acquired_on=payload.acquired_on,
        expected_harvest_on=payload.expected_harvest_on,
        notes=payload.notes.strip() if payload.notes else None,
        care_details=payload.care_details,
    )
    db.add(plant)
    db.flush()
    db.refresh(plant)
    db.commit()
    return success_payload(_serialise_plant(plant).model_dump(mode="json"))


@router.get("/{plant_id}", summary="Fetch one saved plant")
async def get_saved_plant(plant_id: str, auth: CurrentUser, db: DbSession) -> dict[str, Any]:
    plant = db.execute(
        select(SavedPlant)
        .options(selectinload(SavedPlant.notes_history), selectinload(SavedPlant.health_history))
        .where(SavedPlant.id == plant_id, SavedPlant.user_id == auth.id, SavedPlant.deleted_at.is_(None))
    ).scalar_one_or_none()
    if plant is None:
        raise NotFoundError("Saved plant not found.")
    return success_payload(_serialise_plant(plant).model_dump(mode="json"))


@router.post("/{plant_id}/notes", status_code=status.HTTP_201_CREATED, summary="Add a note to a saved plant")
async def add_note_to_saved_plant(
    plant_id: str,
    payload: SavedPlantNoteCreateRequest,
    auth: CurrentUser,
    db: DbSession,
) -> dict[str, Any]:
    plant = db.execute(
        select(SavedPlant).where(SavedPlant.id == plant_id, SavedPlant.user_id == auth.id, SavedPlant.deleted_at.is_(None))
    ).scalar_one_or_none()
    if plant is None:
        raise NotFoundError("Saved plant not found.")
    note = UserPlantNote(
        user_plant_id=plant.id,
        user_id=auth.id,
        body=payload.body.strip(),
        observed_on=payload.observed_on or datetime.now(UTC),
        tags=payload.tags or [],
        image_file_id=None if not payload.image_file_id else payload.image_file_id,
    )
    db.add(note)
    db.flush()
    db.refresh(note)
    db.commit()
    if plant.notes_history is not None:
        plant.notes_history.append(note)
    return success_payload(_serialise_note(note).model_dump(mode="json"))
