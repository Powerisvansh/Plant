from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.errors import success_payload
from plantdoctor_api.db import query_all, query_one

router = APIRouter(prefix="/sources", tags=["sources"])


@router.get("", summary="List provenance sources")
async def list_sources(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) AS count FROM sources")
    total = int(count["count"]) if count else 0
    sql = """
        SELECT id, key, name, url, source_type, organization, authors, license,
               license_url, attribution_required, attribution_template, terms_url,
               redistribution_allowed, commercial_use_allowed, citation,
               date_accessed, last_verified, api_endpoint, approval_status,
               is_citable_in_app, notes, created_at, updated_at
          FROM sources
         ORDER BY key
         LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return success_payload({"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/{source_id}", summary="Fetch one source")
async def get_source(source_id: int) -> dict[str, Any]:
    row = query_one(
        """
        SELECT id, key, name, url, source_type, organization, authors, license,
               license_url, attribution_required, attribution_template, terms_url,
               redistribution_allowed, commercial_use_allowed, citation,
               date_accessed, last_verified, api_endpoint, approval_status,
               is_citable_in_app, notes, created_at, updated_at
          FROM sources
         WHERE id = %s
        """,
        (source_id,),
    )
    if row is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=404, detail="source not found")
    return success_payload(row)
