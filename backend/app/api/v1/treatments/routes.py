from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.errors import success_payload
from plantdoctor_api.db import query_all, query_one

router = APIRouter(prefix="/treatments", tags=["treatments"])


@router.get("", summary="List treatment records")
async def list_treatments(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) AS count FROM treatments")
    total = int(count["count"]) if count else 0
    sql = """
        SELECT t.id, t.code, t.name, t.treatment_type, t.summary,
               t.is_prescriptive, t.requires_label, t.requires_professional,
               t.is_regulated, t.jurisdiction, t.restriction_notes,
               t.efficacy_evidence, t.evidence_level, t.verification_status,
               t.last_verified, s.name AS source_name, s.url AS source_url
          FROM treatments t
          LEFT JOIN sources s ON s.id = t.source_id
         ORDER BY t.name
         LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return success_payload({"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/{treatment_id}", summary="Fetch one treatment record")
async def get_treatment(treatment_id: int) -> dict[str, Any]:
    row = query_one(
        """
        SELECT t.*, s.name AS source_name, s.url AS source_url
          FROM treatments t
          LEFT JOIN sources s ON s.id = t.source_id
         WHERE t.id = %s
        """,
        (treatment_id,),
    )
    if row is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="treatment not found")
    return success_payload(row)
