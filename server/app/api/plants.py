from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.plant import Plant
from app.services.plant_service import PlantService

router = APIRouter(prefix="/api/v1")


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/plants")
async def get_plants(
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=200),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    service = PlantService(db)
    plants, total = service.get_all(skip=skip, limit=limit)
    return {"items": [plant_to_dict(p) for p in plants], "total": total, "skip": skip, "limit": limit}


@router.get("/plants/search")
async def search_plants(
    q: str = Query(..., min_length=1, max_length=200),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    plants = PlantService(db).search(q)
    return {"query": q, "items": [plant_to_dict(p) for p in plants]}


@router.get("/plants/{plant_id}")
async def get_plant(plant_id: int, db: Session = Depends(get_db)) -> dict[str, Any]:
    plant = PlantService(db).get_by_id(plant_id)
    if plant is None:
        raise HTTPException(status_code=404, detail="Plant not found")
    return plant_to_dict(plant)


def plant_to_dict(plant: Plant) -> dict[str, Any]:
    return {
        "id": plant.id,
        "common_name": plant.common_name,
        "scientific_name": plant.scientific_name,
        "hindi_name": plant.hindi_name,
        "family": plant.family,
        "genus": plant.genus,
        "species": plant.species,
        "description": plant.description,
        "plant_type": plant.plant_type,
        "sunlight": plant.sunlight,
        "water_requirement": plant.water_requirement,
        "soil_requirement": plant.soil_requirement,
        "temperature": plant.temperature,
        "humidity": plant.humidity,
        "fertilizer_information": plant.fertilizer_information,
        "growing_information": plant.growing_information,
        "propagation": plant.propagation,
        "common_diseases": _coerce_list(plant.common_diseases),
        "common_pests": _coerce_list(plant.common_pests),
        "care_information": plant.care_information,
        "image": plant.image,
        "source": plant.source,
        "verification_status": plant.verification_status,
        "created_at": plant.created_at.isoformat() if plant.created_at else None,
        "updated_at": plant.updated_at.isoformat() if plant.updated_at else None,
    }


def _coerce_list(value: str | None) -> list[str]:
    if value is None or value == "":
        return []
    if value.startswith("["):
        try:
            import json

            parsed = json.loads(value)
            return parsed if isinstance(parsed, list) else [value]
        except Exception:
            pass
    return [entry.strip() for entry in value.split("|") if entry.strip()]
