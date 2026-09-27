#!/usr/bin/env python3
"""FastAPI application exposing the PlantDoctor knowledge base.

Endpoints follow the contract specified in the problem:
- GET /plants
- GET /plants/{id}
- GET /plants/search
- GET /plants/{id}/diseases
- GET /plants/{id}/pests
- GET /plants/{id}/symptoms
- GET /plants/{id}/toxicity
- GET /plants/{id}/treatments
- GET /diseases
- GET /diseases/{id}
- GET /pests
- GET /toxicity
- POST /scan/analyze (placeholder: no-hallucination stub)
- POST /images (metadata stub)
- GET /sources
- GET /health

All reads go through the verified views and schema. No fabricated metrics,
no invented dosage. Unknown toxicity is returned explicitly when absent.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.responses import JSONResponse

from plantdoctor_api.db import get_pool, query_all, query_one

log = logging.getLogger(__name__)

app = FastAPI(title="PlantDoctor AI API", version="0.1.0")


def _page_params(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> tuple[int, int]:
    return limit, offset


def _pool_dep():
    return get_pool()


@app.get("/health")
async def health() -> dict[str, Any]:
    pool = get_pool()
    try:
        with pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
    except Exception as exc:  # pragma: no cover - diagnostic endpoint
        log.exception("Health check failed")
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ok"}


@app.get("/sources")
async def list_sources() -> list[dict[str, Any]]:
    sql = """
    SELECT key, name, url, source_type, organization, license, license_url,
           attribution_required, attribution_template, terms_url,
           redistribution_allowed, commercial_use_allowed, citation,
           api_endpoint, approval_status, is_citable_in_app, notes,
           date_accessed, last_verified, created_at, updated_at
      FROM sources
     ORDER BY key
    """
    return query_all(sql)


@app.get("/plants")
async def list_plants(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    sql_count = "SELECT count(*) FROM v_plant_overview"
    count_row = query_one(sql_count)
    total = int(count_row["count"]) if count_row else 0

    sql = """
    SELECT plant_id, canonical_name, scientific_name, scientific_name_authorship,
           genus, species, family, order_name, taxonomic_status, is_accepted,
           description, identification_summary, growth_habit, edible_status,
           known_uses, ornamental_use, agricultural_importance,
           distribution_summary, conservation_status, verification_status,
           last_verified, external_taxon_source, external_taxon_key,
           taxonomic_source_name, taxonomic_source_url, common_name,
           usable_image_count, disease_count, pest_count, warning_count
      FROM v_plant_overview
     ORDER BY scientific_name
     LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@app.get("/plants/search")
async def search_plants(
    q: str = Query(min_length=1, max_length=120),
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    sql = """
    SELECT plant_id, scientific_name, common_names, family, rank
      FROM fn_search_plants(%s, %s, %s)
    """
    items = query_all(sql, (q, limit, offset))
    return {"query": q, "items": items, "limit": limit, "offset": offset}


@app.get("/plants/{plant_id}")
async def get_plant(plant_id: int) -> dict[str, Any]:
    base = query_one(
        "SELECT * FROM v_plant_overview WHERE plant_id = %s",
        (plant_id,),
    )
    if base is None:
        raise HTTPException(status_code=404, detail="plant not found")
    plant = dict(base)

    plant["growth_requirements"] = query_one(
        """
        SELECT climate, temperature_min_c, temperature_max_c, temperature_optimal_min_c,
               temperature_optimal_max_c, temperature_basis, sunlight, water_requirement,
               soil_type, soil_ph_min, soil_ph_max, soil_drainage, humidity_min_pct,
               humidity_max_pct, growing_season, frost_tolerance, drought_tolerance,
               waterlog_tolerance, propagation_methods, pruning, fertilization, spacing,
               verification_status, last_verified
          FROM plant_growth_requirements
         WHERE plant_id = %s
        """,
        (plant_id,),
    )
    plant["names"] = query_all(
        "SELECT name, name_type, language_code, region, is_preferred, verification_status, notes "
        "FROM plant_names WHERE plant_id = %s ORDER BY is_preferred DESC, name",
        (plant_id,),
    )
    plant["synonyms"] = query_all(
        "SELECT synonym, nomenclatural_status, publication, verification_status "
        "FROM plant_synonyms WHERE plant_id = %s ORDER BY synonym",
        (plant_id,),
    )
    plant["parts"] = query_all(
        "SELECT part, part_name, present_season, is_evergreen, description, verification_status "
        "FROM plant_parts WHERE plant_id = %s ORDER BY part",
        (plant_id,),
    )
    plant["appearance"] = query_all(
        """
        SELECT pa.part, pa.summary, pa.description, pa.season, pa.stage, pa.verification_status,
               paa.attribute, paa.attribute_value, paa.color_name, paa.color_hex,
               paa.value_min, paa.value_max, paa.unit, paa.measurement_basis
          FROM plant_appearance pa
          LEFT JOIN plant_appearance_attributes paa ON paa.appearance_id = pa.id
         WHERE pa.plant_id = %s
         ORDER BY pa.part, paa.attribute
        """,
        (plant_id,),
    )
    return plant


@app.get("/plants/{plant_id}/diseases")
async def plant_diseases(plant_id: int) -> list[dict[str, Any]]:
    sql = """
    SELECT pd.id AS link_id, pd.plant_id, d.id AS disease_id, d.code, d.name,
           d.pathogen_scientific_name, d.pathogen_type, d.verification_status,
           d.last_verified, pd.susceptibility, d.description
      FROM plant_diseases pd
      JOIN diseases d ON d.id = pd.disease_id
     WHERE pd.plant_id = %s
     ORDER BY d.name
    """
    return query_all(sql, (plant_id,))


@app.get("/plants/{plant_id}/pests")
async def plant_pests(plant_id: int) -> list[dict[str, Any]]:
    sql = """
    SELECT pp.id AS link_id, pp.plant_id, p.id AS pest_id, p.code, p.name,
           p.scientific_name, p.pest_type, p.verification_status,
           p.last_verified, pp.damage_level, p.description
      FROM plant_pests pp
      JOIN pests p ON p.id = pp.pest_id
     WHERE pp.plant_id = %s
     ORDER BY p.name
    """
    return query_all(sql, (plant_id,))


@app.get("/plants/{plant_id}/symptoms")
async def plant_symptoms(plant_id: int) -> list[dict[str, Any]]:
    sql = """
    SELECT symptom_id, code, name, category, part, verification_status
      FROM v_plant_symptom_index
     WHERE plant_id = %s
     ORDER BY category, name
    """
    return query_all(sql, (plant_id,))


@app.get("/plants/{plant_id}/toxicity")
async def plant_toxicity(plant_id: int) -> dict[str, Any]:
    sql = """
    SELECT plant_id, scientific_name, profile_id, toxicity_status, overall_severity,
           compounds_summary, exposure_summary, symptoms_summary, first_aid,
           human_risk_level, human_risk_summary, vulnerable_groups, safe_handling,
           human_first_aid, when_to_seek_help, pet_risk_level, affected_pets,
           pet_risk_summary, pet_clinical_note, pet_first_aid, livestock_risk_level,
           affected_livestock, livestock_risk_summary, livestock_clinical_note,
           livestock_first_aid, verification_status, last_verified, source_name,
           source_url, source_citation, source_document_title, is_unknown, unknown_notice
      FROM v_subject_safety_summary
     WHERE plant_id = %s
    """
    row = query_one(sql, (plant_id,))
    if row is None:
        return {
            "plant_id": plant_id,
            "is_unknown": True,
            "toxicity_status": "UNKNOWN",
            "human_risk_level": "UNKNOWN",
            "pet_risk_level": "UNKNOWN",
            "livestock_risk_level": "UNKNOWN",
            "verification_status": "UNKNOWN",
            "unknown_notice": (
                "Toxicity information was not found in the available knowledge base. "
                "Do not consume or use medicinally without independent verification."
            ),
        }
    return dict(row)


@app.get("/plants/{plant_id}/treatments")
async def plant_treatments(plant_id: int) -> dict[str, Any]:
    sql = """
    SELECT dosage_id, treatment_code, treatment_name, treatment_type,
           product_name, product_type, formulation, registration_number,
           jurisdiction, crop_label_text, growth_stage, dose_value, dose_min_value,
           dose_max_value, dose_unit, dose_basis, water_volume_value, water_volume_unit,
           application_method, application_count_max, application_interval_days,
           pre_harvest_interval_days, reentry_interval_hours, target_part,
           label_page_reference, label_url, label_sha256, last_verified,
           label_source_name, label_source_url, label_document_title
      FROM v_treatment_dosage_verified
     WHERE plant_id = %s
     ORDER BY jurisdiction, treatment_name, dosage_id
    """
    items = query_all(sql, (plant_id,))
    return {"plant_id": plant_id, "count": len(items), "items": items}


@app.get("/diseases")
async def list_diseases(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) FROM diseases")
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
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@app.get("/diseases/{disease_id}")
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
    return disease


@app.get("/pests")
async def list_pests(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count = query_one("SELECT count(*) FROM pests")
    total = int(count["count"]) if count else 0
    sql = """
    SELECT p.id, p.code, p.name, p.scientific_name, p.pest_type,
           p.description, p.verification_status, p.last_verified,
           s.name AS source_name, s.url AS source_url
      FROM pests p
      LEFT JOIN sources s ON s.id = p.source_id
     ORDER BY p.name
     LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@app.get("/toxicity")
async def list_toxicity_plants(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    sql = """
    SELECT plant_id, scientific_name, toxicity_status, overall_severity,
           human_risk_level, pet_risk_level, livestock_risk_level,
           verification_status, last_verified, source_name, source_url, is_unknown
      FROM v_subject_safety_summary
     ORDER BY is_unknown, toxicity_status, scientific_name
     LIMIT %s OFFSET %s
    """
    items = query_all(sql, (limit, offset))
    count = query_one("SELECT count(*) FROM plants WHERE is_deleted = FALSE")
    total = int(count["count"]) if count else len(items)
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@app.post("/scan/analyze")
async def scan_analyze(payload: dict[str, Any] | None = None) -> JSONResponse:
    return JSONResponse(
        content={
            "status": "not_available",
            "message": "Image-based analysis is not yet implemented for this backend instance.",
            "caution": "No identification or diagnosis is returned without verified data.",
            "requires_verification": True,
            "information_unavailable": True,
        },
        status_code=status.HTTP_202_ACCEPTED,
    )


@app.post("/images")
async def register_images(payload: dict[str, Any] | None = None) -> JSONResponse:
    return JSONResponse(
        content={
            "status": "accepted",
            "message": "Image metadata ingestion is implemented as a future pipeline; no files were processed.",
            "processed": 0,
        },
        status_code=status.HTTP_202_ACCEPTED,
    )
