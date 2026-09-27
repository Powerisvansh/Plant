#!/usr/bin/env python3
"""Register the approved source registry.

Idempotent: safe to re-run. Sources are keyed, so re-running updates metadata
and never duplicates rows. Records provenance for every change.

Usage:
    python3 scripts/seed_sources.py --dry-run
    python3 scripts/seed_sources.py
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from plantdoctor_api.db import transaction  # noqa: E402

SOURCES_FILE = REPO_ROOT / "data" / "sources.json"
log = logging.getLogger("seed_sources")

FIELDS = (
    "name", "url", "source_type", "organization", "license", "license_url",
    "attribution_required", "attribution_template", "terms_url",
    "redistribution_allowed", "commercial_use_allowed", "citation",
    "approval_status", "is_citable_in_app", "notes",
)
OPTIONAL_FIELDS = ("api_endpoint",)


def load_sources() -> list[dict]:
    data = json.loads(SOURCES_FILE.read_text(encoding="utf-8"))
    sources = data["sources"]
    keys = [s["key"] for s in sources]
    if len(keys) != len(set(keys)):
        raise SystemExit("Duplicate source key in data/sources.json")
    for source in sources:
        missing = [f for f in FIELDS if f not in source]
        if missing:
            raise SystemExit(f"Source {source['key']} is missing fields: {missing}")
    return sources


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Register PlantDoctor knowledge sources")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(message)s",
    )

    sources = load_sources()
    today = date.today().isoformat()

    if args.dry_run:
        print(f"[dry-run] would upsert {len(sources)} sources:")
        for source in sources:
            print(
                f"  {source['key']:<28} {source['approval_status']:<14} "
                f"license={source['license']:<12} citable={source['is_citable_in_app']}"
            )
        return 0

    inserted = updated = 0
    with transaction() as cur:
        for source in sources:
            cur.execute("SELECT id FROM sources WHERE key = %s", (source["key"],))
            existing = cur.fetchone()
            fields = list(FIELDS) + [f for f in OPTIONAL_FIELDS if f in source]
            values = {field: source.get(field) for field in fields}
            if existing is None:
                columns = ["key", *fields, "date_accessed", "last_verified"]
                placeholders = ", ".join(["%s"] * len(columns))
                cur.execute(
                    f"INSERT INTO sources ({', '.join(columns)}) VALUES ({placeholders})",
                    (source["key"], *[values[f] for f in fields], today, today),
                )
                source_id = cur.fetchone()["id"] if cur.description else None
                cur.execute("SELECT id FROM sources WHERE key = %s", (source["key"],))
                source_id = cur.fetchone()["id"]
                cur.execute(
                    "INSERT INTO data_provenance (table_name, record_id, source_id, "
                    "extraction_method, verification_status, notes) "
                    "VALUES ('sources', %s, %s, 'MANUAL_REGISTRATION', 'VERIFIED', %s)",
                    (source_id, source_id, f"Source registry entry '{source['key']}' registered by operator."),
                )
                inserted += 1
                log.info("registered  %s", source["key"])
            else:
                source_id = existing["id"]
                assignments = ", ".join(f"{field} = %s" for field in fields)
                cur.execute(
                    f"UPDATE sources SET {assignments}, last_verified = %s WHERE id = %s",
                    (*[values[f] for f in fields], today, source_id),
                )
                updated += 1
                log.info("updated    %s", source["key"])

    log.info("sources: %d inserted, %d updated", inserted, updated)

    with transaction() as cur:
        cur.execute(
            "SELECT key, approval_status, license, is_citable_in_app FROM sources ORDER BY key"
        )
        print(f"{'KEY':<28} {'APPROVAL':<14} {'LICENSE':<12} CITABLE")
        for row in cur.fetchall():
            print(
                f"{row['key']:<28} {row['approval_status']:<14} "
                f"{row['license']:<12} {row['is_citable_in_app']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
