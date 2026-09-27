from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.errors import success_payload
from plantdoctor_api.db import query_all, query_one

router = APIRouter(prefix="/diseases", tags=["diseases"])


@router.get("", summary="List disease records")
async def list_diseases(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) AS count FROM diseases")
    total = int(count["count"]) if count else 0
    sql = """
        SELECT d.id, d.code, d.name, d.pathogen_type, d.pathogen_scientific_name,
               d.description, d.verification_status, d.last_verified,
               s.name AS source_name, s.url AS source_url
          FROM diseases d
          LEFT JOIN sources s ON s.id = d.source_id
         ORDER BY d.name
         LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return success_payload({"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/{disease_id}", summary="Fetch one disease record")
async def get_disease(disease_id: int) -> dict[str, Any]:
    row = query_one(
        """
        SELECT d.*, s.name AS source_name, s.url AS source_url
          FROM diseases d
          LEFT JOIN sources s ON s.id = d.source_id
         WHERE d.id = %s
        """,
        (disease_id,),
    )
    if row is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="disease not found")
    disease = dict(row)
    disease["symptoms"] = query_all(
        """
        SELECT ds.id, s.id AS symptom_id, s.code, s.name, s.category,
               ds.part, ds.frequency, ds.severity, ds.display_order, ds.verification_status
          FROM disease_symptoms ds
          JOIN symptoms s ON s.id = ds.symptom_id
         WHERE ds.disease_id = %s
         ORDER BY ds.display_order, s.name
        """,
        (disease_id,),
    )
    disease["affected_plants"] = query_all(
        """
        SELECT pd.plant_id, p.scientific_name, COALESCE(n.name, p.scientific_name) AS common_name,
               pd.susceptibility, pd.verification_status, pd.last_verified
          FROM plant_diseases pd
          JOIN plants p ON p.id = pd.plant_id
          LEFT JOIN LATERAL (
            SELECT name FROM plant_names pn WHERE pn.plant_id = p.id AND pn.is_preferred
            LIMIT 1
          ) n ON TRUE
         WHERE pd.disease_id = %s
         ORDER BY p.scientific_name
        """,
        (disease_id,),
    )
    return success_payload(disease)
