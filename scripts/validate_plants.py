#!/usr/bin/env python3
"""Validate the bundled PlantDoctor plant knowledge base.

This is the gate for the spec requirement "at least 2,000 distinct, real plant
records". It reads the *built* SQLite database (not the source JSON) and reports
exactly how many verifiable plant records exist, how many are duplicated or
missing required fields, and whether the 2,000 target is met.

It never repairs or invents anything. If the count is short, it says so.

Usage:
    python3 scripts/validate_plants.py
    python3 scripts/validate_plants.py --db knowledge/dist/plantdoctor.db
    python3 scripts/validate_plants.py --json     # machine-readable
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB = REPO_ROOT / "knowledge" / "dist" / "plantdoctor.db"
TARGET = 2000

TOXICITY_VALUES = {
    "NON_TOXIC_REPORTED",
    "TOXIC",
    "POTENTIALLY_TOXIC",
    "UNKNOWN",
}


def scalar(conn: sqlite3.Connection, sql: str, params=()) -> int:
    return int(conn.execute(sql, params).fetchone()[0])


def has_table(conn: sqlite3.Connection, name: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone() is not None


def validate(db_path: Path) -> dict:
    if not db_path.exists():
        return {
            "database": str(db_path),
            "status": "FAIL",
            "errors": [f"database not found: {db_path}"],
        }

    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}

    total = scalar(conn, "SELECT COUNT(*) FROM plants")
    unique_scientific = scalar(
        conn,
        "SELECT COUNT(DISTINCT lower(trim(scientific_name))) "
        "FROM plants WHERE scientific_name IS NOT NULL "
        "AND trim(scientific_name) <> ''",
    )
    duplicate_rows = total - scalar(
        conn,
        "SELECT COUNT(DISTINCT lower(trim(scientific_name))) "
        "FROM plants WHERE scientific_name IS NOT NULL "
        "AND trim(scientific_name) <> ''",
    )
    missing_scientific = scalar(
        conn,
        "SELECT COUNT(*) FROM plants WHERE scientific_name IS NULL "
        "OR trim(scientific_name) = ''",
    )

    missing_source = 0
    if "data_provenance" in tables:
        missing_source = scalar(
            conn,
            "SELECT COUNT(*) FROM plants p WHERE NOT EXISTS ("
            "  SELECT 1 FROM data_provenance d "
            "  WHERE d.table_name='plants' AND d.record_id=p.id)",
        )
    else:
        missing_source = total

    missing_taxonomy = scalar(
        conn,
        "SELECT COUNT(*) FROM plants WHERE family IS NULL OR trim(family)=''",
    )
    missing_genus = scalar(
        conn,
        "SELECT COUNT(*) FROM plants WHERE genus IS NULL OR trim(genus)=''",
    )

    tox_null = scalar(
        conn,
        "SELECT COUNT(*) FROM plants WHERE toxicity_status IS NULL "
        "OR trim(toxicity_status) = ''",
    )
    tox_values = {
        (r[0] or "").strip().upper(): r[1]
        for r in conn.execute(
            "SELECT toxicity_status, COUNT(*) FROM plants "
            "GROUP BY toxicity_status")
    }
    tox_invalid = sum(count for value, count in tox_values.items()
                      if value and value not in TOXICITY_VALUES)

    verified = scalar(
        conn,
        "SELECT COUNT(*) FROM plants WHERE "
        "upper(trim(COALESCE(verification_status,'')))='VERIFIED'",
    )
    unverified = total - verified

    detail_rows = []
    for table in ("plant_names", "plant_taxonomy", "plant_synonyms",
                  "plant_characteristics", "plant_distribution",
                  "diseases", "plant_diseases", "pests", "plant_pests",
                  "pest_symptoms", "nutrient_deficiencies",
                  "environmental_stresses", "treatments", "toxicity_profiles",
                  "human_safety", "pet_safety", "livestock_safety",
                  "prevention_methods", "sources", "source_records",
                  "data_provenance", "verification_records", "plant_images",
                  "plant_rooftop"):
        detail_rows.append({
            "table": table,
            "present": table in tables,
            "rows": scalar(conn, f'SELECT COUNT(*) FROM "{table}"')
            if table in tables else None,
        })

    families = scalar(
        conn,
        "SELECT COUNT(DISTINCT family) FROM plants "
        "WHERE family IS NOT NULL AND trim(family) <> ''",
    )
    genera = scalar(
        conn,
        "SELECT COUNT(DISTINCT genus) FROM plants "
        "WHERE genus IS NOT NULL AND trim(genus) <> ''",
    )

    meta = {r[0]: r[1] for r in conn.execute("SELECT key, value FROM meta")} \
        if has_table(conn, "meta") else {}

    conn.close()

    blocking = []
    if total < TARGET:
        blocking.append(
            f"only {total} plant records, target is {TARGET} "
            f"({TOTAL_SHORT_FALL(total)} short)")
    if duplicate_rows:
        blocking.append(f"{duplicate_rows} duplicate scientific names")
    if missing_scientific:
        blocking.append(f"{missing_scientific} records without a scientific name")
    if missing_source:
        blocking.append(f"{missing_source} records without provenance")

    return {
        "database": str(db_path),
        "generated_from_manifest": meta,
        "target": TARGET,
        "total_plant_records": total,
        "unique_scientific_names": unique_scientific,
        "duplicate_records": duplicate_rows,
        "missing_scientific_names": missing_scientific,
        "missing_source": missing_source,
        "missing_taxonomy": missing_taxonomy,
        "missing_genus": missing_genus,
        "missing_toxicity_status": tox_null,
        "invalid_toxicity_status": tox_invalid,
        "toxicity_status_breakdown": tox_values,
        "verified_records": verified,
        "unverified_records": unverified,
        "distinct_families": families,
        "distinct_genera": genera,
        "table_detail": detail_rows,
        "blocking_problems": blocking,
        "status": "PASS" if not blocking else "FAIL",
    }


def TOTAL_SHORT_FALL(total: int) -> int:
    return max(0, TARGET - total)


def render(report: dict) -> str:
    if report.get("errors"):
        return "DATABASE VALIDATION\n" + "\n".join(
            f"  ERROR: {e}" for e in report["errors"]) + "\n\nStatus: FAIL"

    lines = [
        "=" * 60,
        "PLANTDOCTOR - PLANT KNOWLEDGE BASE VALIDATION",
        "=" * 60,
        f"Database: {report['database']}",
        "",
        f"Total plant records:        {report['total_plant_records']}",
        f"Unique scientific names:    {report['unique_scientific_names']}",
        f"Duplicate records:          {report['duplicate_records']}",
        f"Missing scientific names:   {report['missing_scientific_names']}",
        f"Missing source/provenance:  {report['missing_source']}",
        f"Missing taxonomy (family):  {report['missing_taxonomy']}",
        f"Missing genus:              {report['missing_genus']}",
        f"Missing toxicity status:    {report['missing_toxicity_status']}",
        f"Invalid toxicity status:    {report['invalid_toxicity_status']}",
        f"Verified records:           {report['verified_records']}",
        f"Unverified records:         {report['unverified_records']}",
        f"Distinct families:          {report['distinct_families']}",
        f"Distinct genera:            {report['distinct_genera']}",
        "",
        f"Target: {report['target']}",
        f"Status: {report['status']}",
        "",
        "Table detail:",
    ]
    for row in report["table_detail"]:
        if row["present"]:
            lines.append(f"  {row['table']:<26} {row['rows']:>8}")
        else:
            lines.append(f"  {row['table']:<26} {'MISSING':>8}")
    if report["blocking_problems"]:
        lines += ["", "Blocking problems:"]
        lines += [f"  - {p}" for p in report["blocking_problems"]]
    lines += ["", "Note: this tool never fabricates records. A FAIL means the",
              "verified target has not been reached yet; it does not license",
              "generating placeholder plants to hit the number.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()

    report = validate(args.db)
    print(json.dumps(report, indent=2) if args.as_json else render(report))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
