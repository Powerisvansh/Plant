from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.errors import success_payload
from plantdoctor_api.db import query_all, query_one

router = APIRouter(prefix="/plants", tags=["plants"])


@router.get("", summary="List plant records")
async def list_plants(
    limit: int = Query(default=20, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    count_row = query_one("SELECT count(*) AS count FROM v_plant_overview")
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
    return success_payload({"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/search", summary="Search plant records")
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
    return success_payload({"query": q, "items": items, "limit": limit, "offset": offset})


@router.get("/{plant_id}", summary="Fetch one plant record")
async def get_plant(plant_id: int) -> dict[str, Any]:
    base = query_one("SELECT * FROM v_plant_overview WHERE plant_id = %s", (plant_id,))
    if base is None:
        from fastapi import HTTPException

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
    return success_payload(plant)


@router.get("/{plant_id}/diseases", summary="Plant disease links")
async def plant_diseases(plant_id: int) -> dict[str, Any]:
    sql = """
        SELECT pd.id AS link_id, pd.plant_id, d.id AS disease_id, d.code, d.name,
               d.pathogen_scientific_name, d.pathogen_type, d.verification_status,
               d.last_verified, pd.susceptibility, d.description
          FROM plant_diseases pd
          JOIN diseases d ON d.id = pd.disease_id
         WHERE pd.plant_id = %s
         ORDER BY d.name
    """
    return success_payload(query_all(sql, (plant_id,)))


@router.get("/{plant_id}/pests", summary="Plant pest links")
async def plant_pests(plant_id: int) -> dict[str, Any]:
    sql = """
        SELECT pp.id AS link_id, pp.plant_id, p.id AS pest_id, p.code, p.name,
               p.scientific_name, p.pest_type, p.verification_status,
               p.last_verified, pp.damage_level, p.description
          FROM plant_pests pp
          JOIN pests p ON p.id = pp.pest_id
         WHERE pp.plant_id = %s
         ORDER BY p.name
    """
    return success_payload(query_all(sql, (plant_id,)))


@router.get("/{plant_id}/symptoms", summary="Symptoms associated with a plant")
async def plant_symptoms(plant_id: int) -> dict[str, Any]:
    sql = """
        SELECT symptom_id, code, name, category, part, verification_status
          FROM v_plant_symptom_index
         WHERE plant_id = %s
         ORDER BY category, name
    """
    return success_payload(query_all(sql, (plant_id,)))


@router.get("/{plant_id}/toxicity", summary="Safety summary")
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
        row = {
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
    return success_payload(row)


@router.get("/{plant_id}/treatments", summary="Treatments for a plant")
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
    return success_payload({"plant_id": plant_id, "count": len(items), "items": items})
