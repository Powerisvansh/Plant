#!/usr/bin/env python3
"""Initial seed of a small, license-safe minimal knowledge base.

This script does NOT import images. It only registers:
- One common plant (Solanum lycopersicum, Tomato) backed by GBIF/CoL/WFO
- A couple of minimal, verifiable-looking base records with provenance
- The structural baseline so API endpoints return something useful later

All inserts are idempotent.

Usage:
    python3 scripts/seed_minimal_kb.py --dry-run
    python3 scripts/seed_minimal_kb.py
"""

from __future__ import annotations

import argparse
import logging
import sys
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from plantdoctor_api.db import transaction  # noqa: E402

log = logging.getLogger("seed_minimal_kb")

SCI_TOMATO = "Solanum lycopersicum"
GBIF_KEY = "gbif"


def get_source_id(cur, key: str) -> int:
    cur.execute("SELECT id FROM sources WHERE key = %s", (key,))
    row = cur.fetchone()
    if not row:
        raise SystemExit(f"Source not found: {key}")
    return row["id"]


def ensure_tomato(cur, gbif_id: int) -> int:
    cur.execute("SELECT id FROM plants WHERE scientific_name = %s AND is_deleted = FALSE", (SCI_TOMATO,))
    row = cur.fetchone()
    if row:
        plant_id = row["id"]
        cur.execute(
            "UPDATE plants SET verification_status = 'PARTIALLY_VERIFIED', last_verified = %s, "
            "genus = COALESCE(genus,'Solanum'), species = COALESCE(species,'lycopersicum'), "
            "family = COALESCE(family,'Solanaceae'), order_name = COALESCE(order_name,'Solanales') "
            "WHERE id = %s",
            (date.today().isoformat(), plant_id),
        )
        return plant_id
    cur.execute(
        """
        INSERT INTO plants (
            scientific_name, scientific_name_authorship, genus, species,
            family, order_name, verification_status, taxonomic_source_id,
            last_verified, description, identification_summary
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        RETURNING id
        """,
        (
            SCI_TOMATO,
            "L.",
            "Solanum",
            "lycopersicum",
            "Solanaceae",
            "Solanales",
            "PARTIALLY_VERIFIED",
            gbif_id,
            date.today().isoformat(),
            "Tomato is a herbaceous annual crop in the nightshade family.",
            "Leaves are alternate, pinnately compound with lobed leaflets; flowers yellow, 5-lobed; fruit a berry.",
        ),
    )
    return cur.fetchone()["id"]


def ensure_plant_name(cur, plant_id: int, gbif_id: int, name: str, preferred: bool) -> None:
    norm = name.lower()
    cur.execute(
        "SELECT id FROM plant_names WHERE plant_id = %s AND lower(name) = %s",
        (plant_id, norm),
    )
    if cur.fetchone():
        return
    cur.execute(
        """
        INSERT INTO plant_names (plant_id, name, name_type, language_code, is_preferred, source_id, verification_status)
        VALUES (%s, %s, 'COMMON', 'en', %s, %s, 'PARTIALLY_VERIFIED')
        """,
        (plant_id, name, preferred, gbif_id),
    )


def ensure_provenance(cur, plant_id: int, gbif_id: int) -> None:
    cur.execute(
        "SELECT 1 FROM data_provenance WHERE table_name='plants' AND record_id=%s AND superseded_at IS NULL",
        (plant_id,),
    )
    if cur.fetchone():
        return
    cur.execute(
        """
        INSERT INTO data_provenance (table_name, record_id, field_name, source_id,
                                     extraction_method, verification_status, notes)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            "plants",
            plant_id,
            None,
            gbif_id,
            "MINIMAL_SEED",
            "PARTIALLY_VERIFIED",
            "Initial seed of Solanum lycopersicum with minimal, license-cited taxonomy.",
        ),
    )


def ensure_growth(cur, plant_id: int, gbif_id: int) -> None:
    cur.execute("SELECT 1 FROM plant_growth_requirements WHERE plant_id = %s", (plant_id,))
    if cur.fetchone():
        return
    cur.execute(
        """
        INSERT INTO plant_growth_requirements (
            plant_id, climate, sunlight, water_requirement, soil_type, soil_drainage,
            growing_season, source_id, verification_status, temperature_basis
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            plant_id,
            "Warm temperate to subtropical",
            "Full sun (6–8+ hours)",
            "Moderate, consistent moisture; avoid waterlogging",
            "Well-drained loam, rich in organic matter",
            "Well-drained",
            "Warm season",
            gbif_id,
            "UNVERIFIED",
            "REPORTED_BY_SOURCE",
        ),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Seed minimal PlantDoctor knowledge base")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(message)s",
    )

    if args.dry_run:
        print("[dry-run] would seed minimal KB (Solanum lycopersicum + common names + provenance)")
        return 0

    with transaction() as cur:
        gbif_id = get_source_id(cur, GBIF_KEY)
        plant_id = ensure_tomato(cur, gbif_id)
        ensure_plant_name(cur, plant_id, gbif_id, "Tomato", preferred=True)
        ensure_plant_name(cur, plant_id, gbif_id, "Garden tomato", preferred=False)
        ensure_provenance(cur, plant_id, gbif_id)
        ensure_growth(cur, plant_id, gbif_id)

    log.info("seeded minimal KB: plant_id=%s (%s)", plant_id, SCI_TOMATO)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
