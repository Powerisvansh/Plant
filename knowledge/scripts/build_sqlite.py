#!/usr/bin/env python3
"""Build the bundled SQLite knowledge base from staged + curated data.

Inputs
------
* ``knowledge/data/raw/gbif_species.json``  - real GBIF taxonomy (import_gbif.py)
* ``knowledge/data/curated/*.json``         - project-curated, clearly labelled
                                              content (names, deficiencies,
                                              stresses, prevention, toxicity
                                              watchlist, PlantVillage classes)

Output
------
* ``knowledge/dist/plantdoctor.db``  - shipped as an app asset
* ``knowledge/dist/manifest.json``   - versions, counts, licences

Nothing is generated: every row either comes from GBIF, from a curated file
whose verification status is recorded honestly, or is not written at all.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    ASSET_DB_PATH,
    CURATED_DIR,
    DB_PATH,
    DIST_DIR,
    KNOWLEDGE_DIR,
    MANIFEST_PATH,
    RAW_DIR,
    read_json,
    setup_logging,
    slugify,
    today,
    utc_now,
    write_json,
)

log = setup_logging("build_sqlite")

SCHEMA_PATH = KNOWLEDGE_DIR / "schema.sql"
SCHEMA_VERSION = 2
DATABASE_VERSION = 1
DATA_RELEASE = "2026.10.0"

# The build refuses to publish a bundle that does not reach this many real,
# verifiable plant records. It is a floor, not a fill target: the importer
# stages what GBIF actually returns, and a shortfall fails the build rather
# than being padded with placeholder rows.
PLANT_RECORD_TARGET = 10000

# ---------------------------------------------------------------------------
# Source registry (licences are recorded for every imported dataset)
# ---------------------------------------------------------------------------

SOURCES = [
    {
        "source_key": "gbif",
        "name": "GBIF Backbone Taxonomy",
        "kind": "taxonomy",
        "organization": "Global Biodiversity Information Facility",
        "url": "https://www.gbif.org/dataset/d7dddbf4-2cf0-4f39-9b2a-bb099caae36c",
        "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "attribution": "GBIF.org (2026) GBIF Backbone Taxonomy, CC BY 4.0",
        "attribution_required": 1,
        "version": "GBIF Backbone, retrieved 2026-09",
    },
    {
        "source_key": "gbif_occurrences",
        "name": "GBIF occurrence records (India)",
        "kind": "taxonomy",
        "organization": "Global Biodiversity Information Facility",
        "url": "https://www.gbif.org/occurrence/search?country=IN",
        "license": "CC BY 4.0 (per record; see dataset keys)",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "attribution": "Occurrence records mediated by GBIF.org, CC BY 4.0",
        "attribution_required": 1,
        "version": "retrieved 2026-09",
    },
    {
        "source_key": "plantvillage",
        "name": "PlantVillage Dataset",
        "kind": "image",
        "organization": "Penn State / EPFL (Mohanty, Hughes, Salathe 2016)",
        "url": "https://github.com/spMohanty/PlantVillage-Dataset",
        "license": "CC BY-SA 3.0",
        "license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
        "attribution": (
            "PlantVillage dataset, Mohanty et al. 2016, CC BY-SA 3.0 "
            "(Frontiers in Plant Science 7:1419)"
        ),
        "attribution_required": 1,
        "version": "color/raw as published 2016",
    },
    {
        "source_key": "curated_project",
        "name": "PlantDoctor curated content",
        "kind": "agronomy",
        "organization": "PlantDoctor AI project (Vansh Dhiman)",
        "url": "https://github.com/Powerisvansh/Plant",
        "license": "project-curated",
        "license_url": None,
        "attribution": "PlantDoctor AI curated content",
        "attribution_required": 0,
        "version": DATA_RELEASE,
        "notes": (
            "General horticultural/agronomic knowledge curated by the project "
            "from standard teaching material. Stored with verification_status "
            "= UNVERIFIED until a named published source is attached to each "
            "record. The app labels these records accordingly."
        ),
    },
    {
        "source_key": "aps_common_names",
        "name": "APS Common Names of Plant Diseases",
        "kind": "disease",
        "organization": "American Phytopathological Society",
        "url": "https://www.apsnet.org/publications/commonnames/Pages/default.aspx",
        "license": "reference-use (facts: disease/pathogen names)",
        "license_url": None,
        "attribution": "Disease and pathogen names cross-checked against the APS "
                       "Common Names of Plant Diseases database.",
        "attribution_required": 0,
        "version": "accessed 2026-09",
        "notes": (
            "Used only to cross-check disease names and their pathogen names. "
            "No APS text or images are copied into this database."
        ),
    },
    {
        "source_key": "aspca_toxic_plants",
        "name": "ASPCA Toxic and Non-Toxic Plants",
        "kind": "toxicity",
        "organization": "American Society for the Prevention of Cruelty to Animals",
        "url": "https://www.aspca.org/pet-care/animal-poison-control/toxic-and-non-toxic-plants",
        "license": "reference-use (facts)",
        "license_url": None,
        "attribution": "Pet toxicity status cross-checked against the ASPCA "
                       "Toxic and Non-Toxic Plants list.",
        "attribution_required": 0,
        "version": "accessed 2026-09",
        "notes": (
            "Facts (toxic / non-toxic, principal toxic principle, affected "
            "animal) only. Applies primarily to cats, dogs and horses; it is "
            "not a livestock or human medical reference."
        ),
    },
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def connect_fresh(path: Path) -> sqlite3.Connection:
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    return conn


def _curated_rows(path: Path, key: str) -> list | dict:
    """Rows of a curated/staged JSON file, unwrapping its ``_meta`` sibling.

    Every content file in ``knowledge/data`` stores its rows under a named key
    (``names``, ``species``, ``aliases``, ``diseases``...) beside a ``_meta``
    provenance block. Indexing such a file at the top level silently yields
    nothing, which previously let 199 curated common names go unapplied
    without the build reporting an error. Callers name the key they expect and
    a missing or mis-shaped file fails loudly instead.
    """
    data = read_json(path, None)
    if data is None:
        log.warning("curated file missing or unreadable: %s", path.name)
        return [] if key is None else {}
    if isinstance(data, list):
        return data
    if not isinstance(data, dict):
        raise SystemExit(f"{path.name}: expected a list or an object")
    rows = data.get(key if key is not None else "")
    if rows is None:
        raise SystemExit(
            f"{path.name}: no '{key}' section. Refusing to build a knowledge "
            f"base that silently drops every row in that file."
        )
    return rows


def register_sources(conn: sqlite3.Connection) -> dict[str, int]:
    ids: dict[str, int] = {}
    for src in SOURCES:
        conn.execute(
            """
            INSERT INTO sources (source_key, name, kind, organization, url,
                license, license_url, attribution, attribution_required,
                version, retrieved_at, notes)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                src["source_key"], src["name"], src["kind"],
                src.get("organization"), src.get("url"), src["license"],
                src.get("license_url"), src.get("attribution"),
                src.get("attribution_required", 0), src.get("version"),
                utc_now(), src.get("notes"),
            ),
        )
        ids[src["source_key"]] = conn.execute(
            "SELECT id FROM sources WHERE source_key = ?", (src["source_key"],)
        ).fetchone()["id"]
    return ids


def provenance(conn, table, record_id, field, source_id, value,
               method="api", confidence="HIGH", status="VERIFIED", note=None):
    conn.execute(
        """
        INSERT INTO data_provenance (table_name, record_id, field_name,
            source_id, extracted_value, extraction_method, confidence,
            verification_status, notes)
        VALUES (?,?,?,?,?,?,?,?,?)
        """,
        (table, record_id, field, source_id,
         (str(value)[:4000] if value is not None else None),
         method, confidence, status, note),
    )


RANK_CHAIN = ["kingdom", "phylum", "class", "order", "family", "genus"]



def insert_plants(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    staged = read_json(RAW_DIR / "gbif_species.json", []) or []
    # Curated files wrap their rows under a sibling key ("names"), next to the
    # "_meta" provenance block. Reading the whole file and then looking a
    # canonical name up at the top level silently returns None for every
    # species, which is how 199 curated common/Hindi names went unapplied
    # while the build still reported success. Always index through
    # `_curated_rows()` so the wrapper cannot be forgotten again.
    names = _curated_rows(CURATED_DIR / "common_names.json", "names")
    stats = {"plants": 0, "names": 0, "taxonomy": 0, "india": 0}

    for record in staged:
        slug = record["slug"]
        common = (record.get("vernacular_name") or "").strip() or None
        curated = names.get(record["canonical_name"]) or {}
        if isinstance(curated, str):
            curated = {"en": curated}
        if curated.get("en"):
            common = curated["en"]
        group = record.get("group")

        cur = conn.execute(
            """
            INSERT INTO plants (slug, common_name, scientific_name, canonical_name,
                genus, species, family, order_name, class_name, phylum, kingdom,
                authorship, taxonomic_status, is_accepted, external_taxon_source,
                external_taxon_key, toxicity_status, verification_status,
                last_verified, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                slug, common, record["scientific_name"], record["canonical_name"],
                record.get("genus"), record.get("species"), record.get("family"),
                record.get("order"), record.get("class"), record.get("phylum"),
                record.get("kingdom"), record.get("authorship"),
                record.get("taxonomic_status"),
                1 if (record.get("taxonomic_status") or "").upper() == "ACCEPTED"
                else 0,
                "gbif", record["gbif_key"],
                "UNKNOWN", "TAXONOMY_ONLY", record.get("retrieved_at"),
                source_ids["gbif"],
            ),
        )
        plant_id = cur.lastrowid
        stats["plants"] += 1
        provenance(conn, "plants", plant_id, "scientific_name",
                   source_ids["gbif"], record["scientific_name"],
                   note=f"GBIF usageKey {record['gbif_key']}")

        for rank in RANK_CHAIN:
            value = record.get(rank)
            if not value:
                continue
            conn.execute(
                """
                INSERT OR IGNORE INTO plant_taxonomy
                    (plant_id, rank, name, external_taxon_key, source_id)
                VALUES (?,?,?,?,?)
                """,
                (plant_id, rank.upper(), value, None, source_ids["gbif"]),
            )
            stats["taxonomy"] += 1

        conn.execute(
            """
            INSERT INTO plant_names (plant_id, name, name_type, language,
                is_primary, source_id)
            VALUES (?,?,?,?,?,?)
            """,
            (plant_id, record["scientific_name"], "scientific", "la", 1,
             source_ids["gbif"]),
        )
        stats["names"] += 1
        if record.get("vernacular_name"):
            conn.execute(
                """
                INSERT INTO plant_names (plant_id, name, name_type, language,
                    is_primary, source_id)
                VALUES (?,?,?,?,?,?)
                """,
                (plant_id, record["vernacular_name"], "vernacular", None, 0,
                 source_ids["gbif"]),
            )
            stats["names"] += 1
        for key, name_type, language in (("en", "common", "en"), ("hi", "hindi", "hi")):
            value = curated.get(key)
            if not value:
                continue
            conn.execute(
                """
                INSERT OR IGNORE INTO plant_names (plant_id, name, name_type,
                    language, is_primary, source_id)
                VALUES (?,?,?,?,?,?)
                """,
                (plant_id, value, name_type, language, 0,
                 source_ids["curated_project"]),
            )
            stats["names"] += 1

        # Real evidence of occurrence in India (GBIF occurrence records).
        if record.get("india_occurrences"):
            conn.execute(
                """
                INSERT OR IGNORE INTO plant_distribution
                    (plant_id, region, kind, source_id)
                VALUES (?,?,?,?)
                """,
                (plant_id, "India", "recorded", source_ids["gbif_occurrences"]),
            )
            conn.execute(
                """
                INSERT OR IGNORE INTO plant_characteristics
                    (plant_id, trait, value, source_id)
                VALUES (?,?,?,?)
                """,
                (plant_id, "india_occurrence_records",
                 str(record["india_occurrences"]), source_ids["gbif_occurrences"]),
            )
            stats["india"] += 1

        conn.execute(
            """
            INSERT INTO source_records (source_id, external_id, external_url,
                record_kind, retrieved_at)
            VALUES (?,?,?,?,?)
            """,
            (source_ids["gbif"], record["gbif_key"],
             f"https://www.gbif.org/species/{record['gbif_key']}", "taxon",
             record.get("retrieved_at")),
        )

    log.info("plants inserted: %s", stats)
    return stats



def load_aliases() -> dict[str, dict]:
    """Curated alias -> accepted-name map (see name_aliases.json)."""
    data = read_json(CURATED_DIR / "name_aliases.json", {}) or {}
    return {a["alias"]: a for a in data.get("aliases", [])}


def _plant_id_for(conn: sqlite3.Connection, name: str | None,
                  aliases: dict[str, dict] | None = None) -> int | None:
    if not name:
        return None
    aliases = aliases if aliases is not None else load_aliases()
    row = conn.execute(
        "SELECT id FROM plants WHERE canonical_name = ? OR scientific_name = ?",
        (name, name),
    ).fetchone()
    if row:
        return row["id"]
    row = conn.execute(
        "SELECT plant_id FROM plant_names WHERE name = ? LIMIT 1", (name,)
    ).fetchone()
    if row:
        return row["plant_id"]
    row = conn.execute(
        "SELECT plant_id FROM plant_synonyms WHERE scientific_name = ? LIMIT 1",
        (name,),
    ).fetchone()
    if row:
        return row["plant_id"]
    alias = aliases.get(name)
    if alias and alias.get("canonical_name") != name:
        return _plant_id_for(conn, alias["canonical_name"], aliases)
    return None


def insert_aliases(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Record curated aliases as synonyms and searchable names.

    This is a name-to-name mapping against GBIF's own synonymy, recorded with
    its reason, so no taxon is invented and the visual model's crop label can
    be resolved to a real plant row.
    """
    aliases = load_aliases()
    src = source_ids["gbif"]
    stats = {"aliases": 0, "unmatched": 0}
    for alias, info in aliases.items():
        plant_id = _plant_id_for(conn, info["canonical_name"], aliases)
        if plant_id is None:
            stats["unmatched"] += 1
            log.warning("alias target missing: %s -> %s",
                        alias, info["canonical_name"])
            continue
        conn.execute(
            """
            INSERT OR IGNORE INTO plant_synonyms
                (plant_id, scientific_name, taxonomic_status, source_id)
            VALUES (?,?,?,?)
            """,
            (plant_id, alias, "SYNONYM", src),
        )
        conn.execute(
            """
            INSERT INTO plant_names (plant_id, name, name_type, language,
                is_primary, source_id)
            VALUES (?,?,?,?,?,?)
            """,
            (plant_id, alias, "synonym", info.get("language", "la"), 0, src),
        )
        provenance(conn, "plant_synonyms", plant_id, "scientific_name", src,
                   alias, method="curated_file", confidence="HIGH",
                   status="SOURCE_NAMED", note=info.get("reason"))
        stats["aliases"] += 1
    log.info("aliases: %s", stats)
    return stats


def insert_diseases(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Diseases come from the PlantVillage class list (real crop/disease pairs)."""
    classes = read_json(CURATED_DIR / "plantvillage_classes.json", {}) or {}
    stats = {"diseases": 0, "links": 0, "symptoms": 0}
    for entry in classes.get("diseases", []):
        slug = slugify(entry["name"])
        cur = conn.execute(
            """
            INSERT OR IGNORE INTO diseases (slug, name, pathogen_name,
                pathogen_kind, description, visual_symptoms, favorable_conditions,
                transmission, prevention, management, verification_status,
                last_verified, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                slug, entry["name"], entry.get("pathogen"),
                entry.get("pathogen_kind"), entry.get("description"),
                entry.get("visual_symptoms"), entry.get("favorable_conditions"),
                entry.get("transmission"), entry.get("prevention"),
                entry.get("management"), entry.get("verification_status",
                                                   "UNVERIFIED"),
                today(), source_ids[entry.get("source", "curated_project")],
            ),
        )
        if cur.rowcount == 0:
            disease_id = conn.execute(
                "SELECT id FROM diseases WHERE slug = ?", (slug,)
            ).fetchone()["id"]
        else:
            disease_id = cur.lastrowid
            stats["diseases"] += 1
            provenance(conn, "diseases", disease_id, "name",
                       source_ids[entry.get("source", "curated_project")],
                       entry["name"], method="curated_file",
                       confidence="MEDIUM", status=entry.get("verification_status",
                                                              "UNVERIFIED"))

        for symptom in entry.get("symptoms", []):
            conn.execute(
                """
                INSERT OR IGNORE INTO disease_symptoms
                    (disease_id, symptom, plant_part, stage, source_id)
                VALUES (?,?,?,?,?)
                """,
                (disease_id, symptom.get("text"), symptom.get("part"),
                 symptom.get("stage"), source_ids[entry.get("source",
                                                            "curated_project")]),
            )
            stats["symptoms"] += 1

        for crop in entry.get("crops", []):
            plant_id = _plant_id_for(conn, crop.get("scientific_name"))
            if plant_id is None:
                continue
            conn.execute(
                """
                INSERT OR IGNORE INTO plant_diseases
                    (plant_id, disease_id, severity, source_id)
                VALUES (?,?,?,?)
                """,
                (plant_id, disease_id, crop.get("severity"),
                 source_ids[entry.get("source", "curated_project")]),
            )
            stats["links"] += 1

    log.info("diseases: %s", stats)
    return stats


def insert_deficiencies(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    data = read_json(CURATED_DIR / "nutrient_deficiencies.json", {}) or {}
    src = source_ids["curated_project"]
    stats = {"deficiencies": 0, "links": 0}
    # Which plants they are linked to is deliberately empty by default: a
    # deficiency cannot be attributed to a plant without evidence.
    for entry in data.get("deficiencies", []):
        slug = slugify(entry["nutrient"])
        cur = conn.execute(
            """
            INSERT OR IGNORE INTO nutrient_deficiencies (slug, nutrient, symbol,
                description, visual_signs, affected_parts, similar_conditions,
                soil_factors, correction_guidance, verification_status, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                slug, entry["nutrient"], entry.get("symbol"),
                entry.get("description"), entry.get("visual_signs"),
                entry.get("affected_parts"), entry.get("similar_conditions"),
                entry.get("soil_factors"), entry.get("correction_guidance"),
                entry.get("verification_status", "UNVERIFIED"), src,
            ),
        )
        if cur.rowcount:
            stats["deficiencies"] += 1
            provenance(conn, "nutrient_deficiencies", cur.lastrowid, "nutrient",
                       src, entry["nutrient"], method="curated_file",
                       confidence="MEDIUM", status="UNVERIFIED")

    for entry in data.get("stresses", []):
        slug = slugify(entry["name"])
        conn.execute(
            """
            INSERT OR IGNORE INTO environmental_stresses (slug, name,
                description, visual_signs, similar_conditions,
                correction_guidance, verification_status, source_id)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            (
                slug, entry["name"], entry.get("description"),
                entry.get("visual_signs"), entry.get("similar_conditions"),
                entry.get("correction_guidance"),
                entry.get("verification_status", "UNVERIFIED"), src,
            ),
        )
    log.info("deficiencies/stresses: %s", stats)
    return stats



def insert_pests(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    data = read_json(CURATED_DIR / "pests.json", {}) or {}
    src = source_ids["curated_project"]
    stats = {"pests": 0, "symptoms": 0, "links": 0}
    for entry in data.get("pests", []):
        slug = slugify(entry["name"])
        cur = conn.execute(
            """
            INSERT OR IGNORE INTO pests (slug, name, scientific_name, appearance,
                feeding_behavior, damage_symptoms, life_stages, prevention,
                management, verification_status, last_verified, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                slug, entry["name"], entry.get("scientific_name"),
                entry.get("appearance"), entry.get("feeding_behavior"),
                entry.get("damage_symptoms"), entry.get("life_stages"),
                entry.get("prevention"), entry.get("management"),
                entry.get("verification_status", "UNVERIFIED"), today(), src,
            ),
        )
        if cur.rowcount == 0:
            pest_id = conn.execute("SELECT id FROM pests WHERE slug = ?",
                                   (slug,)).fetchone()["id"]
        else:
            pest_id = cur.lastrowid
            stats["pests"] += 1
            provenance(conn, "pests", pest_id, "name", src, entry["name"],
                       method="curated_file", confidence="MEDIUM",
                       status="UNVERIFIED")
        for symptom in entry.get("symptoms", []):
            conn.execute(
                """
                INSERT OR IGNORE INTO pest_symptoms (pest_id, symptom,
                    plant_part, source_id)
                VALUES (?,?,?,?)
                """,
                (pest_id, symptom.get("text"), symptom.get("part"), src),
            )
            stats["symptoms"] += 1
        for crop in entry.get("crops", []):
            plant_id = _plant_id_for(conn, crop)
            if plant_id is None:
                continue
            conn.execute(
                """
                INSERT OR IGNORE INTO plant_pests (plant_id, pest_id,
                    severity, source_id)
                VALUES (?,?,?,?)
                """,
                (plant_id, pest_id, None, src),
            )
            stats["links"] += 1
    log.info("pests: %s", stats)
    return stats


def insert_treatments(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Treatments. A dose is only stored when a label reference backs it.

    Safety-critical table, so the guard is applied twice: this importer drops
    any dosage arriving without ``label_url`` + ``label_page_reference`` +
    ``last_verified``, and the shipped view ``v_treatment_dosage_verified``
    re-checks the same three columns at read time. Cultural/mechanical first
    steps are stored with no product attached at all.
    """
    data = read_json(CURATED_DIR / "treatments.json", {}) or {}
    src = source_ids["curated_project"]
    stats = {"treatments": 0, "targets": 0, "products": 0,
             "doses_rejected": 0, "unmatched": 0}

    for entry in data.get("treatments", []):
        dosage = entry.get("recommended_dosage")
        label_url = entry.get("label_url")
        label_page = entry.get("label_page_reference")
        verified_on = entry.get("last_verified")
        if dosage and not (label_url and label_page and verified_on):
            stats["doses_rejected"] += 1
            log.warning("rejected unsourced dosage on treatment %r",
                        entry.get("name"))
            dosage = None

        slug = slugify(entry["name"])
        conn.execute(
            """
            INSERT OR REPLACE INTO treatments
                (slug, name, treatment_type, description, application_method,
                 frequency, timing, recommended_dosage, dosage_unit,
                 water_volume, pre_harvest_interval, waiting_period,
                 safety_precautions, protective_equipment, label_page_reference,
                 label_url, last_verified, verification_status, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                slug, entry["name"], entry.get("treatment_type", "CULTURAL"),
                entry.get("description"), entry.get("application_method"),
                entry.get("frequency"), entry.get("timing"), dosage,
                entry.get("dosage_unit"), entry.get("water_volume"),
                entry.get("pre_harvest_interval"), entry.get("waiting_period"),
                entry.get("safety_precautions"),
                entry.get("protective_equipment"), label_page, label_url,
                verified_on, entry.get("verification_status", "UNVERIFIED"), src,
            ),
        )
        treatment_id = conn.execute(
            "SELECT id FROM treatments WHERE slug = ?", (slug,)).fetchone()["id"]
        stats["treatments"] += 1

        _insert_treatment_products(conn, treatment_id, entry, src, stats)

        target = entry.get("target") or {}
        ids = (
            _id_for(conn, "diseases", target.get("disease")),
            _id_for(conn, "pests", target.get("pest")),
            _id_for(conn, "nutrient_deficiencies", target.get("deficiency")),
            _id_for(conn, "environmental_stresses", target.get("stress")),
        )
        if not any(ids):
            stats["unmatched"] += 1
        else:
            conn.execute(
                """
                INSERT INTO treatment_targets
                    (treatment_id, disease_id, pest_id, deficiency_id,
                     stress_id, source_id)
                VALUES (?,?,?,?,?,?)
                """,
                (treatment_id, *ids, src),
            )
            stats["targets"] += 1

        for crop in entry.get("crops", []):
            plant_id = _plant_id_for(conn, crop.get("scientific_name"))
            if plant_id is None:
                continue
            conn.execute(
                """
                INSERT OR IGNORE INTO treatment_plant_scope
                    (treatment_id, plant_id, crop_name, source_id)
                VALUES (?,?,?,?)
                """,
                (treatment_id, plant_id, crop.get("crop_name"), src),
            )

    log.info("treatments: %s", stats)
    return stats


def _insert_treatment_products(conn, treatment_id: int, entry: dict,
                               src: int, stats: dict) -> None:
    """Register any named products and link them to the treatment."""
    for product in entry.get("products", []):
        ingredient = product.get("active_ingredient")
        ingredient_id = None
        if ingredient:
            conn.execute(
                """
                INSERT OR IGNORE INTO active_ingredients
                    (name, kind, description, source_id)
                VALUES (?,?,?,?)
                """,
                (ingredient, product.get("ingredient_kind"), None, src),
            )
            ingredient_id = conn.execute(
                "SELECT id FROM active_ingredients WHERE name = ?",
                (ingredient,)).fetchone()["id"]

        conn.execute(
            """
            INSERT OR IGNORE INTO treatment_products
                (name, active_ingredient_id, formulation, concentration,
                 product_kind, jurisdiction, registration_number, source_id)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            (
                product["name"], ingredient_id, product.get("formulation"),
                product.get("concentration"), product.get("product_kind"),
                product.get("jurisdiction") or "India",
                product.get("registration_number"), src,
            ),
        )
        product_id = conn.execute(
            """
            SELECT id FROM treatment_products
            WHERE name = ? AND COALESCE(concentration, '') = ?
              AND COALESCE(jurisdiction, '') = ?
            """,
            (product["name"], product.get("concentration") or "",
             product.get("jurisdiction") or "India"),
        ).fetchone()["id"]
        conn.execute(
            """
            INSERT OR IGNORE INTO treatment_product_links
                (treatment_id, product_id)
            VALUES (?,?)
            """,
            (treatment_id, product_id),
        )
        stats["products"] += 1


def insert_prevention(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Non-chemical and cultural first steps, attached to their target."""
    data = read_json(CURATED_DIR / "prevention.json", {}) or {}
    src = source_ids["curated_project"]
    stats = {"methods": 0, "linked": 0, "unlinked": 0}

    for entry in data.get("methods", []):
        disease_id = pest_id = None
        if entry.get("disease"):
            disease_id = _id_for(conn, "diseases", entry["disease"])
            if disease_id is None:
                stats["unlinked"] += 1
        if entry.get("pest"):
            pest_id = _id_for(conn, "pests", entry["pest"])
            if pest_id is None:
                stats["unlinked"] += 1

        anchor = entry.get("disease") or entry.get("pest") or "general"
        slug = slugify(f"{anchor}-{entry['method']}")
        conn.execute(
            """
            INSERT OR IGNORE INTO prevention_methods
                (slug, method, description, applies_to, disease_id, pest_id,
                 verification_status, source_id)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            (
                slug, entry["method"], entry.get("description"),
                entry.get("applies_to") or (
                    "disease" if disease_id else "pest" if pest_id else "general"),
                disease_id, pest_id,
                entry.get("verification_status", "UNVERIFIED"), src,
            ),
        )
        stats["methods"] += 1
        if disease_id or pest_id:
            stats["linked"] += 1

    log.info("prevention: %s", stats)
    return stats


def _id_for(conn: sqlite3.Connection, table: str, name: str | None) -> int | None:
    """Look a knowledge table up by its slugified natural key."""
    if not name:
        return None
    row = conn.execute(f"SELECT id FROM {table} WHERE slug = ?",
                       (slugify(name),)).fetchone()
    return row["id"] if row else None


def insert_toxicity(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Curated, source-named toxicity records.

    The specification rule is enforced structurally: a plant with no entry here
    keeps ``toxicity_status = 'UNKNOWN'`` (the column default). Nothing is ever
    written as NON_TOXIC by default, so "we have no data" can never render as
    "this plant is safe".
    """
    data = read_json(CURATED_DIR / "toxicity.json", {}) or {}
    src = source_ids["curated_project"]
    stats = {"profiles": 0, "parts": 0, "human": 0, "pet": 0,
             "livestock": 0, "unmatched": 0}
    unmatched: list[str] = []

    for entry in data.get("profiles", []):
        plant_id = _plant_id_for(conn, entry.get("scientific_name"))
        if plant_id is None:
            stats["unmatched"] += 1
            unmatched.append(entry.get("scientific_name") or "?")
            continue

        status = (entry.get("toxicity_status") or "UNKNOWN").upper()
        conn.execute(
            """
            INSERT OR REPLACE INTO toxicity_profiles
                (plant_id, toxicity_status, toxic_compounds, exposure_routes,
                 symptoms, severity, safety_warning, verification_status,
                 last_verified, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            """,
            (
                plant_id, status, entry.get("toxic_compounds"),
                entry.get("exposure_routes"), entry.get("symptoms"),
                entry.get("severity"), entry.get("safety_warning"),
                entry.get("verification_status", "UNVERIFIED"), today(), src,
            ),
        )
        stats["profiles"] += 1
        provenance(conn, "toxicity_profiles", plant_id, "toxicity_status", src,
                   status, method="curated_file", confidence="MEDIUM",
                   status=entry.get("verification_status", "UNVERIFIED"),
                   note=entry.get("source_note"))

        # Keep the plants read-model column in step with the profile.
        conn.execute("UPDATE plants SET toxicity_status = ? WHERE id = ?",
                     (status, plant_id))

        for part in entry.get("parts", []):
            conn.execute(
                """
                INSERT OR IGNORE INTO toxicity_parts
                    (plant_id, part, toxicity_status, notes, source_id)
                VALUES (?,?,?,?,?)
                """,
                (
                    plant_id, part.get("part", "unspecified"),
                    (part.get("toxicity_status") or status).upper(),
                    part.get("notes"), src,
                ),
            )
            stats["parts"] += 1

        for key, table, counter in (
            ("human", "human_safety", "human"),
            ("pet", "pet_safety", "pet"),
            ("livestock", "livestock_safety", "livestock"),
        ):
            block = entry.get(key)
            if not block:
                continue
            risk = (block.get("risk_level") or "UNKNOWN").upper()
            if table == "human_safety":
                conn.execute(
                    """
                    INSERT OR REPLACE INTO human_safety
                        (plant_id, risk_level, details, first_aid,
                         verification_status, source_id)
                    VALUES (?,?,?,?,?,?)
                    """,
                    (plant_id, risk, block.get("details"),
                     block.get("first_aid"),
                     block.get("verification_status", "UNVERIFIED"), src),
                )
            else:
                conn.execute(
                    f"""
                    INSERT OR REPLACE INTO {table}
                        (plant_id, risk_level, species_affected, details,
                         verification_status, source_id)
                    VALUES (?,?,?,?,?,?)
                    """,
                    (plant_id, risk, block.get("species_affected"),
                     block.get("details"),
                     block.get("verification_status", "UNVERIFIED"), src),
                )
            stats[counter] += 1

    if unmatched:
        log.warning("toxicity entries matching no plant: %s",
                    ", ".join(sorted(set(unmatched))[:12]))
    log.info("toxicity: %s", stats)
    return stats


def insert_rooftop(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Rooftop / terrace siting data (see rooftop_greenery.json).

    Unlike the other curated loaders, an unresolvable name is a hard failure
    rather than a warning. The other files are best-effort enrichment of
    plants that already exist, so skipping a row is harmless. This file is a
    curated worklist: a name that matches no taxon means a typo or a species
    that was never imported, and quietly dropping it would leave the app
    claiming to cover a plant it has no record of.
    """
    data = read_json(CURATED_DIR / "rooftop_greenery.json", {}) or {}
    entries = data.get("species", [])
    if not entries:
        log.info("rooftop: no species entries yet (sources pending)")
        return {"profiles": 0, "verified": 0, "unverified": 0}

    src = source_ids["curated_project"]
    stats = {"profiles": 0, "verified": 0, "unverified": 0}
    unmatched: list[str] = []

    for entry in entries:
        plant_id = _plant_id_for(conn, entry.get("scientific_name"))
        if plant_id is None:
            unmatched.append(entry.get("scientific_name") or "?")
            continue

        # A record is only VERIFIED when it names the sources it rests on.
        # An empty list stays UNVERIFIED, matching every other curated file.
        sources = entry.get("sources") or []
        verified = bool(sources)
        status = "VERIFIED" if verified else "UNVERIFIED"
        cited = "; ".join(
            s.get("citation") or s.get("title") or "unnamed source"
            for s in sources if isinstance(s, dict)
        ) or None

        siting = entry.get("siting") or {}
        container = entry.get("container") or {}
        watering = entry.get("watering") or {}
        maintenance = entry.get("maintenance") or {}

        conn.execute(
            """
            INSERT OR REPLACE INTO plant_rooftop
                (plant_id, rooftop_role, exposure, heat_tolerance,
                 drought_tolerance, wind_exposure, min_container_litres,
                 root_depth_cm, drainage, watering_band,
                 establishment_watering, pruning_requirement, self_sown,
                 special_hazards, notes, verification_status, source_id)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                plant_id,
                entry.get("rooftop_role"),
                siting.get("exposure"),
                siting.get("heat_tolerance"),
                siting.get("drought_tolerance"),
                siting.get("wind_exposure"),
                container.get("min_container_litres"),
                container.get("root_depth_cm"),
                container.get("drainage"),
                watering.get("watering_band"),
                watering.get("establishment_watering"),
                maintenance.get("pruning_requirement"),
                maintenance.get("self_sown"),
                maintenance.get("special_hazards"),
                entry.get("notes"),
                status, src,
            ),
        )
        stats["profiles"] += 1
        stats["verified" if verified else "unverified"] += 1
        provenance(conn, "plant_rooftop", plant_id, "rooftop_role", src,
                   entry.get("rooftop_role"), method="curated_file",
                   confidence="HIGH" if verified else "MEDIUM",
                   status=status, note=cited)

    if unmatched:
        raise SystemExit(
            "rooftop_greenery.json names species that are not in the knowledge "
            f"base, so they would be silently dropped: {', '.join(sorted(set(unmatched)))}. "
            "Fix the name, or add the genus to knowledge/data/curated/"
            "target_genera.json and re-run knowledge/scripts/import_gbif.py."
        )
    log.info("rooftop: %s", stats)
    return stats
def insert_categories(conn: sqlite3.Connection, source_ids: dict[str, int]) -> dict:
    """Populate plant_categories / plant_category_map / plant_crops / plant_traits.

    Two sources, both already curated in ``knowledge/data/curated``:

    * ``plant_categories.json`` defines the category vocabulary and maps each
      GBIF harvest ``group`` onto it, so every staged species lands in a real
      bucket instead of one large uncategorised pile.
    * ``crop_coverage.json`` carries explicit per-species membership for the
      food plants, agricultural crops and urban-garden plants people actually
      ask about, plus crop attributes and horticultural traits. Its membership
      always wins over the group fallback, per that file's ``membership_rule``.

    Category assignment groups taxa the GBIF import already confirmed and
    records no new biological claim, so rows are stored UNVERIFIED_CATEGORY
    rather than VERIFIED, matching the curated-file convention used elsewhere.

    Like the rooftop loader, an unresolvable name in ``crop_coverage.json`` is a
    hard failure: that file is a curated worklist, so silently dropping a row
    would leave the app claiming coverage of a plant it has no record for.
    """
    spec = read_json(CURATED_DIR / "plant_categories.json", {}) or {}
    categories = _curated_rows(CURATED_DIR / "plant_categories.json", "categories")
    coverage = _curated_rows(CURATED_DIR / "crop_coverage.json", "species")
    src = source_ids["curated_project"]

    stats = {"categories": 0, "mappings": 0, "primary": 0, "crops": 0,
             "traits": 0, "fallback_mapped": 0, "explicit": 0}

    category_ids: dict[str, int] = {}
    for cat in categories:
        conn.execute(
            """
            INSERT OR IGNORE INTO plant_categories
                (code, label, description, sort_order)
            VALUES (?,?,?,?)
            """,
            (cat["code"], cat["label"], cat.get("description"),
             int(cat.get("sort_order", 100))),
        )
        row = conn.execute(
            "SELECT id FROM plant_categories WHERE code = ?", (cat["code"],)
        ).fetchone()
        category_ids[cat["code"]] = row["id"]
        stats["categories"] += 1

    group_map = (spec.get("gbif_group_map") or {}).get("map") or {}
    fallback = (spec.get("gbif_group_map") or {}).get("fallback")

    def link(plant_id: int, code: str, is_primary: int) -> None:
        category_id = category_ids.get(code)
        if category_id is None:
            log.warning("unknown category code %r - not mapping", code)
            return
        conn.execute(
            """
            INSERT OR IGNORE INTO plant_category_map
                (plant_id, category_id, is_primary, source_id)
            VALUES (?,?,?,?)
            """,
            (plant_id, category_id, is_primary, src),
        )
        stats["mappings"] += 1
        if is_primary:
            stats["primary"] += 1
        provenance(conn, "plant_category_map", plant_id, "category_code", src,
                   code, method="curated_file", confidence="MEDIUM",
                   status="UNVERIFIED_CATEGORY",
                   note="Project-curated grouping of GBIF-accepted taxa; "
                        "records no new biological claim.")
# Explicit per-species membership from crop_coverage.json.
    unmatched: list[str] = []
    for entry in coverage:
        plant_id = _plant_id_for(conn, entry.get("scientific_name"))
        if plant_id is None:
            unmatched.append(entry.get("scientific_name") or "?")
            continue
        primary = entry.get("primary_category")
        for code in entry.get("categories") or []:
            link(plant_id, code, 1 if code == primary else 0)
        stats["explicit"] += 1

        crop = entry.get("crop") or {}
        if crop:
            conn.execute(
                """
                INSERT OR REPLACE INTO plant_crops
                    (plant_id, crop_role, edible_part, life_cycle,
                     sowing_season, harvest_period, growth_duration,
                     cultivation_system, source_id)
                VALUES (?,?,?,?,?,?,?,?,?)
                """,
                (plant_id, crop.get("crop_role"), crop.get("edible_part"),
                 crop.get("life_cycle"), crop.get("sowing_season"),
                 crop.get("harvest_period"), crop.get("growth_duration"),
                 crop.get("cultivation_system"), src),
            )
            stats["crops"] += 1
            provenance(conn, "plant_crops", plant_id, "crop_role", src,
                       crop.get("crop_role"), method="curated_file",
                       confidence="MEDIUM", status="UNVERIFIED",
                       note="Curated from standard Indian agricultural "
                            "extension practice.")

        for trait in entry.get("traits") or []:
            if not isinstance(trait, dict) or not trait.get("trait"):
                continue
            conn.execute(
                """
                INSERT OR REPLACE INTO plant_traits
                    (plant_id, trait, value, source_id)
                VALUES (?,?,?,?)
                """,
                (plant_id, trait["trait"], trait.get("value"), src),
            )
            stats["traits"] += 1
            provenance(conn, "plant_traits", plant_id, trait["trait"], src,
                       trait.get("value"), method="curated_file",
                       confidence="MEDIUM", status="UNVERIFIED",
                       note="Curated horticultural description.")

    if unmatched:
        raise SystemExit(
            "crop_coverage.json names species that are not in the knowledge "
            f"base, so they would be silently dropped: {', '.join(sorted(set(unmatched)))}. "
            "Fix the name, or add the species to knowledge/data/curated/"
            "target_genera.json and re-run knowledge/scripts/import_gbif.py."
        )

    # Group fallback for every species not already placed above, so the browse
    # screen never collapses into a single uncategorised pile.
    if group_map:
        placed = {r["id"] for r in conn.execute(
            "SELECT DISTINCT plant_id AS id FROM plant_category_map"
        ).fetchall()}
        for record in read_json(RAW_DIR / "gbif_species.json", []) or []:
            plant_row = conn.execute(
                "SELECT id FROM plants WHERE slug = ?", (record["slug"],)
            ).fetchone()
            if not plant_row or plant_row["id"] in placed:
                continue
            code = group_map.get(record.get("group") or "") or fallback
            if not code:
                continue
            link(plant_row["id"], code, 1)
            stats["fallback_mapped"] += 1

    log.info("categories: %s", stats)
    return stats


# ---------------------------------------------------------------------------
# Meta rows, indexes, integrity and the manifest
# ---------------------------------------------------------------------------

AUDITED_TABLES = [
    "plants", "plant_names", "plant_synonyms", "plant_taxonomy",
    "plant_characteristics", "plant_distribution", "plant_rooftop",
    "plant_images", "diseases",
    "plant_categories", "plant_category_map", "plant_crops", "plant_traits",
    "plant_diseases", "disease_symptoms", "pests", "plant_pests",
    "pest_symptoms", "nutrient_deficiencies", "environmental_stresses",
    "prevention_methods", "treatments", "treatment_targets",
    "treatment_products", "active_ingredients", "toxicity_profiles",
    "toxicity_parts", "human_safety", "pet_safety", "livestock_safety",
    "sources", "source_records", "data_provenance", "verification_records",
]


def write_meta(conn: sqlite3.Connection, stats: dict) -> None:
    """database_version / schema_version / data_release, so the app can gate an
    upgrade of the bundled asset."""
    rows = {
        "database_version": str(DATABASE_VERSION),
        "schema_version": str(SCHEMA_VERSION),
        "data_release": DATA_RELEASE,
        "build_date": utc_now(),
        "built_by": "knowledge/scripts/build_sqlite.py",
        "project": "PlantDoctor AI",
        "plant_record_target": str(PLANT_RECORD_TARGET),
        "notes": (
            "Every record carries its source and verification status. Fields "
            "with no source are left NULL rather than generated. Toxicity "
            "UNKNOWN means no reliable information was found; it does not mean "
            "safe."
        ),
    }
    for key, value in rows.items():
        conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?,?)", (key, value))

    counts = {
        table: conn.execute(f"SELECT COUNT(*) AS n FROM {table}").fetchone()["n"]
        for table in AUDITED_TABLES
    }
    for table, count in counts.items():
        conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?,?)",
            (f"count.{table}", str(count)))


def write_indexes(conn: sqlite3.Connection) -> None:
    """Indexes for the app's real read patterns (search + joins)."""
    statements = [
        "CREATE INDEX IF NOT EXISTS ix_plant_names_type ON plant_names (name_type)",
        "CREATE INDEX IF NOT EXISTS ix_plant_names_lang ON plant_names (language)",
        "CREATE INDEX IF NOT EXISTS ix_plants_canon ON plants (canonical_name)",
        "CREATE INDEX IF NOT EXISTS ix_plants_common_lc ON plants (LOWER(common_name))",
        "CREATE INDEX IF NOT EXISTS ix_plant_diseases_p ON plant_diseases (plant_id)",
        "CREATE INDEX IF NOT EXISTS ix_plant_diseases_d ON plant_diseases (disease_id)",
        "CREATE INDEX IF NOT EXISTS ix_plant_pests_p ON plant_pests (plant_id)",
        "CREATE INDEX IF NOT EXISTS ix_plant_pests_x ON plant_pests (pest_id)",
        "CREATE INDEX IF NOT EXISTS ix_disease_symptoms_d ON disease_symptoms (disease_id)",
        "CREATE INDEX IF NOT EXISTS ix_pest_symptoms_p ON pest_symptoms (pest_id)",
        "CREATE INDEX IF NOT EXISTS ix_treatment_targets_t ON treatment_targets (treatment_id)",
        "CREATE INDEX IF NOT EXISTS ix_treatment_targets_d ON treatment_targets (disease_id)",
        "CREATE INDEX IF NOT EXISTS ix_treatment_targets_p ON treatment_targets (pest_id)",
        "CREATE INDEX IF NOT EXISTS ix_plant_scope_t ON treatment_plant_scope (treatment_id)",
        "CREATE INDEX IF NOT EXISTS ix_plant_scope_p ON treatment_plant_scope (plant_id)",
        "CREATE INDEX IF NOT EXISTS ix_plant_images_p ON plant_images (plant_id)",
        "CREATE INDEX IF NOT EXISTS ix_provenance_table ON data_provenance (table_name)",
        "CREATE INDEX IF NOT EXISTS ix_source_records_s ON source_records (source_id)",
    ]
    for statement in statements:
        conn.execute(statement)


def validate(conn: sqlite3.Connection) -> dict:
    """Integrity plus the specification's no-fake-data checks."""
    report: dict[str, object] = {}
    report["integrity_check"] = conn.execute(
        "PRAGMA integrity_check").fetchone()[0]
    report["foreign_key_violations"] = len(
        conn.execute("PRAGMA foreign_key_check").fetchall())

    def count(sql: str) -> int:
        return conn.execute(sql).fetchone()[0]

    report["plants"] = count("SELECT COUNT(*) FROM plants")
    report["unique_scientific_names"] = count(
        "SELECT COUNT(DISTINCT canonical_name) FROM plants")
    report["duplicate_records"] = count(
        "SELECT COUNT(*) - COUNT(DISTINCT canonical_name) FROM plants")
    report["missing_scientific_name"] = count(
        "SELECT COUNT(*) FROM plants WHERE scientific_name IS NULL "
        "OR TRIM(scientific_name) = ''")
    report["missing_taxonomy"] = count(
        "SELECT COUNT(*) FROM plants WHERE family IS NULL OR genus IS NULL")
    report["missing_source"] = count(
        "SELECT COUNT(*) FROM plants WHERE source_id IS NULL")
    report["missing_toxicity_status"] = count(
        "SELECT COUNT(*) FROM plants WHERE toxicity_status IS NULL "
        "OR TRIM(toxicity_status) = ''")
    report["missing_common_name"] = count(
        "SELECT COUNT(*) FROM plants WHERE common_name IS NULL")
    report["toxicity_unknown"] = count(
        "SELECT COUNT(*) FROM plants WHERE toxicity_status = 'UNKNOWN'")
    report["toxicity_documented"] = count(
        "SELECT COUNT(*) FROM plants WHERE toxicity_status <> 'UNKNOWN'")
    report["placeholders"] = count(
        """
        SELECT COUNT(*) FROM plants
        WHERE canonical_name IS NULL
           OR TRIM(canonical_name) = ''
           -- genus-rank records are not species records
           OR canonical_name NOT LIKE '% %'
           -- explicit open nomenclature markers
           OR canonical_name LIKE '% sp.'
           OR canonical_name LIKE '% spp.'
           OR canonical_name LIKE '% cf.'
           OR canonical_name LIKE '% aff.'
           OR scientific_name LIKE '%Plant 0%'
           OR scientific_name LIKE '%unknown%'
        """)
    report["genus_rank_only"] = count(
        "SELECT COUNT(*) FROM plants WHERE canonical_name NOT LIKE '% %'")
    report["missing_authorship"] = count(
        "SELECT COUNT(*) FROM plants WHERE authorship IS NULL "
        "OR TRIM(authorship) = ''")
    report["doses_without_label"] = count(
        """
        SELECT COUNT(*) FROM treatments
        WHERE recommended_dosage IS NOT NULL
          AND (label_url IS NULL OR label_page_reference IS NULL
               OR last_verified IS NULL)
        """)
    report["plant_record_target"] = PLANT_RECORD_TARGET
    report["target_status"] = (
        "PASS" if report["plants"] >= PLANT_RECORD_TARGET else "FAIL"
    )
    return report


def rebuild_fts(conn: sqlite3.Connection) -> dict:
    """Populate the two FTS5 tables from the real tables.

    The schema declares standalone FTS5 tables (no external content and no
    triggers), so they are filled here. Nothing is invented: the search text is
    concatenated from values already present in ``plants`` / ``plant_names`` and
    in the condition tables.
    """
    stats = {"plants": 0, "conditions": 0}

    conn.execute("DELETE FROM plants_fts")
    conn.execute(
        """
        INSERT INTO plants_fts (plant_id, names, family)
        SELECT
            p.id,
            TRIM(
                COALESCE(p.common_name, '') || ' ' ||
                COALESCE(p.scientific_name, '') || ' ' ||
                COALESCE(p.canonical_name, '') || ' ' ||
                COALESCE(p.genus, '') || ' ' ||
                COALESCE(p.family, '') || ' ' ||
                COALESCE((
                    SELECT GROUP_CONCAT(pn.name, ' ')
                    FROM plant_names pn WHERE pn.plant_id = p.id
                ), '') || ' ' ||
                COALESCE((
                    SELECT GROUP_CONCAT(ps.scientific_name, ' ')
                    FROM plant_synonyms ps WHERE ps.plant_id = p.id
                ), '')
            ),
            COALESCE(p.family, '')
        FROM plants p
        """,
    )
    stats["plants"] = conn.execute(
        "SELECT COUNT(*) FROM plants_fts").fetchone()[0]

    conn.execute("DELETE FROM conditions_fts")
    # Each table exposes its searchable text through different columns; the
    # mapping below uses only columns that table actually has.
    mappings = (
        ("disease", "diseases", "name",
         "COALESCE(d.pathogen_name,'') || ' ' || COALESCE(d.visual_symptoms,'') "
         "|| ' ' || COALESCE(d.description,'')",
         "SELECT GROUP_CONCAT(ds.symptom, ' ') FROM disease_symptoms ds "
         "WHERE ds.disease_id = d.id"),
        ("pest", "pests", "name",
         "COALESCE(d.scientific_name,'') || ' ' "
         "|| COALESCE(d.damage_symptoms,'') || ' ' || COALESCE(d.appearance,'')",
         "SELECT GROUP_CONCAT(ps.symptom, ' ') FROM pest_symptoms ps "
         "WHERE ps.pest_id = d.id"),
        ("deficiency", "nutrient_deficiencies", "d.nutrient",
         "COALESCE(d.symbol,'') || ' ' || COALESCE(d.visual_signs,'') || ' ' "
         "|| COALESCE(d.description,'')",
         "NULL"),
        ("stress", "environmental_stresses", "name",
         "COALESCE(d.visual_signs,'') || ' ' || COALESCE(d.description,'')",
         "NULL"),
    )
    for kind, table, name_expr, extra_expr, symptom_expr in mappings:
        conn.execute(
            f"""
            INSERT INTO conditions_fts
                (condition_kind, condition_id, name, keywords)
            SELECT '{kind}', d.id, {name_expr},
                   TRIM(COALESCE(({symptom_expr}), '') || ' ' || {extra_expr})
            FROM {table} d
            """,
        )
    stats["conditions"] = conn.execute(
        "SELECT COUNT(*) FROM conditions_fts").fetchone()[0]
    log.info("fts rebuilt: %s", stats)
    return stats



def build_manifest(conn: sqlite3.Connection, stats: dict, db_path: Path) -> dict:
    import hashlib

    def table_rows(name: str) -> int:
        return conn.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]

    digest = hashlib.sha256()
    with db_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)

    sources = [
        {
            "source_key": row["source_key"],
            "name": row["name"],
            "kind": row["kind"],
            "organization": row["organization"],
            "url": row["url"],
            "license": row["license"],
            "license_url": row["license_url"],
            "attribution": row["attribution"],
            "version": row["version"],
        }
        for row in conn.execute("SELECT * FROM sources ORDER BY id")
    ]

    return {
        "project": "PlantDoctor AI",
        "database": db_path.name,
        "database_version": DATABASE_VERSION,
        "schema_version": SCHEMA_VERSION,
        "data_release": DATA_RELEASE,
        "build_date": utc_now(),
        "sha256": digest.hexdigest(),
        "size_bytes": db_path.stat().st_size,
        "counts": {table: table_rows(table) for table in AUDITED_TABLES},
        "model": {
            "species_classifier": "not_trained_yet",
            "health_classifier": "not_trained_yet",
            "metrics_source": "not_measured",
            "note": (
                "Model metrics are recorded here only after evaluate_model.py "
                "has actually produced them. No metric is estimated."
            ),
        },
        "sources": sources,
        "stats": stats,
    }



# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB_PATH,
                        help="output SQLite path")
    parser.add_argument("--allow-partial", action="store_true",
                        help="exit 0 even if the plant-record target is unmet")
    parser.add_argument("--asset", type=Path, default=ASSET_DB_PATH,
                        help="also write the bundle to this app asset path; "
                             "pass an empty string to skip")
    args = parser.parse_args()

    db_path: Path = args.db
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = connect_fresh(db_path)
    conn.execute("PRAGMA foreign_keys = ON")

    stats: dict = {}
    manifest: dict = {}
    report: dict = {}
    try:
        with conn:
            source_ids = register_sources(conn)
            stats["sources"] = len(source_ids)
            stats["plants"] = insert_plants(conn, source_ids)
            stats["aliases"] = insert_aliases(conn, source_ids)
            stats["diseases"] = insert_diseases(conn, source_ids)
            stats["deficiencies"] = insert_deficiencies(conn, source_ids)
            stats["pests"] = insert_pests(conn, source_ids)
            stats["treatments"] = insert_treatments(conn, source_ids)
            stats["prevention"] = insert_prevention(conn, source_ids)
            stats["toxicity"] = insert_toxicity(conn, source_ids)
            stats["categories"] = insert_categories(conn, source_ids)
            stats["rooftop"] = insert_rooftop(conn, source_ids)
            write_meta(conn, stats)
            write_indexes(conn)

        stats["fts"] = rebuild_fts(conn)
        conn.commit()

        report = validate(conn)
        conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES (?,?)",
            ("validation_report", json.dumps(report, indent=2)))
        conn.commit()

        conn.execute("VACUUM")
        conn.commit()

        manifest = build_manifest(conn, stats, db_path)
        write_json(MANIFEST_PATH, manifest)
    finally:
        conn.close()

    # Publish to the Flutter asset path only once the build has passed, so a
    # failed run cannot leave the app packaging a half-written bundle.
    asset_db: Path | None = Path(args.asset) if args.asset else None
    if asset_db is not None:
        if report["target_status"] == "FAIL" and not args.allow_partial:
            log.warning("not publishing to %s: record target unmet", asset_db)
        else:
            asset_db.parent.mkdir(parents=True, exist_ok=True)
            tmp = asset_db.with_suffix(".db.tmp")
            shutil.copyfile(db_path, tmp)
            tmp.replace(asset_db)
            log.info("published asset bundle -> %s", asset_db)

    print("=" * 72)
    print("PlantDoctor AI | offline knowledge base build")
    print("=" * 72)
    print(f"database        : {db_path}")
    print(f"size            : {db_path.stat().st_size / 1024 / 1024:.1f} MB")
    print(f"sha256          : {manifest.get('sha256', '')[:16]}...")
    print("-" * 72)
    for key, value in report.items():
        print(f"{key:28} {value}")
    print("-" * 72)
    print(f"manifest        : {MANIFEST_PATH}")
    if asset_db is not None and asset_db.exists():
        print(f"app asset       : {asset_db}")
    print("=" * 72)

    if report["target_status"] == "FAIL" and not args.allow_partial:
        print("\nThe verified plant-record target has not been reached yet.")
        print("No records were fabricated to reach it.")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

