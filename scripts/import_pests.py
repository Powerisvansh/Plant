#!/usr/bin/env python3
"""Import pest records from a curated, source-attributed file.

Same reasoning as import_diseases.py: there is no openly licensed,
machine-readable pest database that carries the licence, jurisdiction and
evidence level this project needs, so this ingests a file a human has prepared
from a source they have read. Scraping EPPO, CABI or a commercial site would
breach their terms and leave the facts unattributable.

The script enforces:
  * a registered, APPROVED source per record
  * an explicit evidence level; UNVERIFIED is refused
  * unresolved host plants and symptoms are reported, never guessed
  * no pesticide name, dose or treatment advice is accepted here. Product and
    dosage data is high-risk and belongs in the label-derived treatment
    pipeline, where jurisdiction and label can be recorded.

Input format (JSON list, or {"records": [...]}):

    [
      {
        "code": "P-0001",                    # required
        "name": "Aphid",                     # required
        "scientific_name": "Aphis gossypii", # optional
        "pest_type": "INSECT",               # optional
        "description": "...",                # optional, from the source
        "source_key": "usda_plants",         # required
        "evidence_level": "GOVERNMENT_EXTENSION",          # required
        "verification_status": "PARTIALLY_VERIFIED",       # required
        "hosts": ["Cucumis sativus"],
        "damage_level": "MODERATE",
        "feeding_damage": "...",
        "life_cycle": "...",
        "prevention": ["..."],
        "symptoms": [
          {"code": "S-CURLING", "part": "LEAF", "severity": "MILD", "description": "..."}
        ]
      }
    ]

Usage:
    python3 scripts/import_pests.py --file data/pests.json --dry-run
    python3 scripts/import_pests.py --file data/pests.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from _common import (
    Counters,
    add_provenance,
    get_logger,
    read_json_records,
    setup_logging,
    today,
    transaction,
    utc_now_iso,
)

log = get_logger("import_pests")

EVIDENCE_LEVELS = {
    "AUTHORITATIVE_REFERENCE", "PEER_REVIEWED", "GOVERNMENT_EXTENSION",
    "MULTIPLE_INDEPENDENT_REPORTS", "SINGLE_REPORT", "ANECDOTAL", "UNVERIFIED",
}
VERIFICATION_STATUSES = {
    "VERIFIED", "PARTIALLY_VERIFIED", "UNVERIFIED", "CONFLICTING", "UNKNOWN",
}
PEST_TYPES = {
    "INSECT", "MITE", "NEMATODE", "SNAIL", "SLUG", "BIRD", "MAMMAL",
    "FUNGUS", "BACTERIUM", "VIRUS", "WEED", "OTHER", "UNKNOWN",
}
PLANT_PARTS = {
    "WHOLE_PLANT", "LEAF", "FLOWER", "FRUIT", "STEM", "ROOT", "SEED", "BARK", "BUD",
    "TENDRIL", "POLLEN", "NECTAR", "ALL_PARTS", "UNKNOWN",
}
SEVERITIES = {"NONE", "MILD", "MODERATE", "SEVERE", "LIFE_THREATENING", "UNKNOWN"}


def require(record: dict[str, Any], field: str) -> str:
    value = record.get(field)
    if not value or not str(value).strip():
        raise ValueError(f"missing required field {field!r}")
    return str(value).strip()


def check_enum(value: Any, allowed: set[str], field: str, default: str) -> str:
    if not value:
        return default
    token = str(value).strip().upper().replace(" ", "_").replace("-", "_")
    if token not in allowed:
        log.warning("unrecognised %s=%r; storing as %s", field, value, default)
        return default
    return token


def resolve_hosts(cur, names: list[str], counters: Counters) -> list[int]:
    resolved: list[int] = []
    for name in names:
        cur.execute(
            "SELECT id FROM plants WHERE canonical_name = lower(%s) AND is_deleted = FALSE",
            (name.strip(),),
        )
        row = cur.fetchone()
        if row:
            resolved.append(row["id"])
        else:
            counters.bump("host_unresolved")
            log.warning("host %r is not in the knowledge base; import the plant first", name)
    return resolved


def process(record: dict[str, Any], source_cache: dict[str, int], counters: Counters) -> int | None:
    code = require(record, "code")
    name = require(record, "name")
    source_key = require(record, "source_key")
    evidence = check_enum(record.get("evidence_level"), EVIDENCE_LEVELS, "evidence_level", "UNVERIFIED")
    verification = check_enum(record.get("verification_status"), VERIFICATION_STATUSES,
                              "verification_status", "PARTIALLY_VERIFIED")
    pest_type = check_enum(record.get("pest_type"), PEST_TYPES, "pest_type", "UNKNOWN")
    damage_level = check_enum(record.get("damage_level"), SEVERITIES, "damage_level", "UNKNOWN")

    if evidence == "UNVERIFIED":
        counters.bump("rejected_unverified")
        log.warning("refusing %r: evidence_level=UNVERIFIED", code)
        return None

    if source_key not in source_cache:
        with transaction() as cur:
            cur.execute("SELECT id, approval_status FROM sources WHERE key = %s", (source_key,))
            found = cur.fetchone()
        if found is None:
            counters.bump("rejected_source")
            log.error("refusing %r: source %r is not registered", code, source_key)
            return None
        if found["approval_status"] != "APPROVED":
            counters.bump("rejected_source")
            log.error("refusing %r: source %r approval_status=%s", code, source_key,
                      found["approval_status"])
            return None
        source_cache[source_key] = found["id"]

    source_id = source_cache[source_key]

    with transaction() as cur:
        cur.execute("SELECT id FROM pests WHERE code = %s", (code,))
        existing = cur.fetchone()

        values = (
            name,
            (record.get("scientific_name") or "").strip() or None,
            pest_type,
            (record.get("description") or "").strip()[:8000] or None,
            (record.get("feeding_damage") or "").strip()[:4000] or None,
            (record.get("life_cycle") or "").strip()[:4000] or None,
            verification, today(), source_id,
        )
        if existing:
            pest_id = existing["id"]
            cur.execute(
                """
                UPDATE pests
                   SET name = COALESCE(%s, name),
                       scientific_name = COALESCE(%s, scientific_name),
                       pest_type = %s,
                       description = COALESCE(%s, description),
                       feeding_damage = COALESCE(%s, feeding_damage),
                       life_cycle = COALESCE(%s, life_cycle),
                       verification_status = %s, last_verified = %s, source_id = %s
                 WHERE id = %s
                """,
                (*values, pest_id),
            )
            counters.bump("updated")
        else:
            cur.execute(
                """
                INSERT INTO pests (code, name, scientific_name, pest_type, description,
                                   feeding_damage, life_cycle, verification_status,
                                   last_verified, source_id)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id
                """,
                (code, *values),
            )
            pest_id = cur.fetchone()["id"]
            counters.bump("inserted")

        for plant_id in resolve_hosts(cur, record.get("hosts") or [], counters):
            cur.execute(
                """
                INSERT INTO plant_pests (plant_id, pest_id, damage_level, source_id,
                                         verification_status)
                VALUES (%s,%s,%s,%s,%s)
                ON CONFLICT (plant_id, pest_id) DO UPDATE
                    SET damage_level = EXCLUDED.damage_level,
                        verification_status = EXCLUDED.verification_status
                """,
                (plant_id, pest_id, damage_level, source_id, verification),
            )
            counters.bump("host_links")

        for order, symptom in enumerate(record.get("symptoms") or [], start=1):
            try:
                symptom_code = require(symptom, "code")
                symptom_name = require(symptom, "name")
            except ValueError as exc:
                counters.bump("symptom_rejected")
                log.warning("pest %s: skipping malformed symptom (%s)", code, exc)
                continue
            cur.execute("SELECT id FROM symptoms WHERE code = %s", (symptom_code,))
            symptom_row = cur.fetchone()
            if symptom_row:
                symptom_id = symptom_row["id"]
            else:
                cur.execute(
                    "INSERT INTO symptoms (code, name, category, verification_status, source_id, notes) "
                    "VALUES (%s,%s,'VISUAL',%s,%s,%s) RETURNING id",
                    (symptom_code, symptom_name, verification, source_id,
                     f"Visual symptom term imported from curated source file at {utc_now_iso()}."),
                )
                symptom_id = cur.fetchone()["id"]
            part = check_enum(symptom.get("part"), PLANT_PARTS, "part", "UNKNOWN")
            severity = check_enum(symptom.get("severity"), SEVERITIES, "severity", "UNKNOWN")
            cur.execute(
                """
                INSERT INTO pest_symptoms (pest_id, symptom_id, part, severity, display_order,
                                           description, verification_status, source_id)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (pest_id, symptom_id, part) DO UPDATE
                    SET severity = EXCLUDED.severity,
                        description = COALESCE(EXCLUDED.description, pest_symptoms.description)
                """,
                (pest_id, symptom_id, part, severity, order,
                 (symptom.get("description") or "").strip()[:2000] or None, verification, source_id),
            )
            counters.bump("symptom_links")

        add_provenance(
            cur, "pests", pest_id, source_id, None, "CURATED_FILE_IMPORT",
            json.dumps({"code": code, "name": name}, ensure_ascii=False),
            None, verification,
            f"Imported from curated file; evidence_level={evidence}. "
            f"No pesticide product or dosage data is accepted by this importer.",
        )
        cur.execute(
            """
            INSERT INTO verification_records (table_name, record_id, verification_status,
                                             method, evidence, notes)
            VALUES ('pests', %s, %s, 'CURATED_SOURCE_REVIEW', %s, %s)
            """,
            (pest_id, verification, f"evidence_level={evidence}",
             f"Reviewed against source {source_key} at {today()}"),
        )
    return pest_id


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import pest records from a curated file")
    parser.add_argument("--file", required=True, help="JSON file of pest records")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    setup_logging(args.log_level)
    path = Path(args.file)
    if not path.is_file():
        raise SystemExit(f"file not found: {path}")

    try:
        records = read_json_records(path)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc

    if args.limit:
        records = records[: args.limit]
    log.info("read %d pest record(s) from %s", len(records), path)

    if args.dry_run:
        print(f"[dry-run] {len(records)} record(s) from {path}")
        for record in records[:20]:
            print(f"  {record.get('code')}: {record.get('name')} "
                  f"(source={record.get('source_key')}, evidence={record.get('evidence_level')})")
        if len(records) > 20:
            print(f"  ... and {len(records) - 20} more")
        print("[dry-run] no pesticide product or dosage data is imported by this tool")
        return 0

    counters = Counters()
    source_cache: dict[str, int] = {}
    accepted = 0
    for index, record in enumerate(records, start=1):
        try:
            if process(record, source_cache, counters) is not None:
                accepted += 1
        except ValueError as exc:
            counters.bump("rejected_invalid")
            log.error("[%d/%d] rejected: %s", index, len(records), exc)
        except Exception as exc:
            counters.bump("failed")
            log.error("[%d/%d] failed: %s: %s", index, len(records), type(exc).__name__, exc)

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - PEST IMPORT")
    print("=" * 68)
    print(f"file     : {path}")
    print(f"records  : {len(records)}")
    print(f"accepted : {accepted}")
    for key, value in counters.as_dict().items():
        print(f"  {key:<22}: {value}")
    print()
    print("No pest was invented. No pesticide or dose was accepted.")
    print("=" * 68)
    return 1 if counters.get("failed") else 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
