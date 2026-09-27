from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.errors import success_payload
from plantdoctor_api.db import query_all, query_one

router = APIRouter(prefix="/medicines", tags=["medicines"])


@router.get("", summary="List registered medicine/product records")
async def list_medicines(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) AS count FROM treatment_products")
    total = int(count["count"]) if count else 0
    sql = """
        SELECT p.id, p.key, p.product_name, p.product_type, p.formulation,
               p.formulation_code, p.concentration_value, p.concentration_unit,
               p.manufacturer, p.registration_number, p.jurisdiction,
               p.registration_status, p.label_url, p.label_sha256, p.label_date,
               p.hazard_statements, p.signal_word, p.verification_status,
               p.last_verified, s.name AS source_name, s.url AS source_url
          FROM treatment_products p
          LEFT JOIN sources s ON s.id = p.source_id
         ORDER BY p.product_name
         LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return success_payload({"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/{medicine_id}", summary="Fetch one medicine/product record")
async def get_medicine(medicine_id: int) -> dict[str, Any]:
    row = query_one(
        """
        SELECT p.*, s.name AS source_name, s.url AS source_url
          FROM treatment_products p
          LEFT JOIN sources s ON s.id = p.source_id
         WHERE p.id = %s
        """,
        (medicine_id,),
    )
    if row is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="medicine not found")
    return success_payload(row)
