from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.errors import success_payload
from plantdoctor_api.db import query_all, query_one

router = APIRouter(prefix="/symptoms", tags=["symptoms"])


@router.get("", summary="List symptom records")
async def list_symptoms(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) AS count FROM symptoms")
    total = int(count["count"]) if count else 0
    sql = """
        SELECT s.id, s.code, s.name, s.category, s.description,
               s.visual_appearance, s.onset_notes, s.distinguishing_notes,
               s.default_severity, s.is_observable, s.requires_lab,
               s.verification_status, s.created_at, s.updated_at
          FROM symptoms s
         ORDER BY s.name
         LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return success_payload({"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/{symptom_id}", summary="Fetch one symptom record")
async def get_symptom(symptom_id: int) -> dict[str, Any]:
    row = query_one(
        "SELECT * FROM symptoms WHERE id = %s",
        (symptom_id,),
    )
    if row is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="symptom not found")
    return success_payload(row)
