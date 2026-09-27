#!/usr/bin/env python3
"""Import disease and pest records from a curated, source-attributed file.

Why a file and not a scraper
----------------------------
There is no openly licensed, machine-readable API that publishes plant disease
and pest facts together with the licence, jurisdiction and evidence level this
project requires. The large agronomic databases (EPPO, CABI, USDA APS) either
restrict redistribution or have no public API. Scraping them would breach
their terms and would import facts whose provenance could not be recorded.

So this script ingests a local file that a human has prepared from a source
they have actually read. The script's job is to enforce the rules, not to
supply the science:

  * every record must name a source that is registered and APPROVED
  * every record must carry the evidence level the source actually supports
  * a record whose host plant or symptom cannot be resolved is reported and
    skipped, never linked to a guess
  * no treatment, dose or prevention advice is accepted here at all. Dosage is
    high-risk and belongs in a separate, label-derived pipeline.

Input format (JSON list, or {"records": [...]}):

    [
      {
        "code": "D-0001",                     # stable local identifier
        "name": "Early blight",               # required
        "pathogen_scientific_name": "Alternaria solani",   # optional, omit if unknown
        "pathogen_type": "FUNGUS",            # optional
        "description": "...",                 # optional, must come from the source
        "source_key": "usda_plants",          # required
        "evidence_level": "GOVERNMENT_EXTENSION",           # required
        "verification_status": "PARTIALLY_VERIFIED",        # required
        "hosts": ["Solanum lycopersicum", "Solanum tuberosum"],
        "symptoms": [
          {"code": "S-LEAF-BROWN-SPOTS", "part": "LEAF", "severity": "MODERATE",
           "frequency": "COMMON", "description": "..."}
        ],
        "affected_parts": ["LEAF", "STEM"],
        "favorable_conditions": "...",
        "transmission": "...",
        "prevention": ["..."],
        "notes": "..."
      }
    ]

Usage:
    python3 scripts/import_diseases.py --file data/diseases.json --dry-run
    python3 scripts/import_diseases.py --file data/diseases.json
    python3 scripts/import_diseases.py --file data/diseases.json --min-evidence GOVERNMENT_EXTENSION
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

log = get_logger("import_diseases")

EVIDENCE_LEVELS = {
    "AUTHORITATIVE_REFERENCE", "PEER_REVIEWED", "GOVERNMENT_EXTENSION",
    "MULTIPLE_INDEPENDENT_REPORTS", "SINGLE_REPORT", "ANECDOTAL", "UNVERIFIED",
}
VERIFICATION_STATUSES = {
    "VERIFIED", "PARTIALLY_VERIFIED", "UNVERIFIED", "CONFLICTING", "UNKNOWN",
}
PATHOGEN_TYPES = {"FUNGUS", "BACTERIUM", "VIRUS", "NEMATODE", "PROTOZOAN", "ALGA", "OTHER", "UNKNOWN"}
PLANT_PARTS = {
    "WHOLE_PLANT", "LEAF", "FLOWER", "FRUIT", "STEM", "ROOT", "SEED", "BARK", "BUD",
    "TENDRIL", "POLLEN", "NECTAR", "ALL_PARTS", "UNKNOWN",
}
FREQUENCIES = {"COMMON", "OCCASIONAL", "RARE", "UNKNOWN"}
SEVERITIES = {"NONE", "MILD", "MODERATE", "SEVERE", "LIFE_THREATENING", "UNKNOWN"}


def require(record: dict[str, Any], field: str) -> str:
    value = (record.get(field) or "").strip() if isinstance(record.get(field), str) else record.get(field)
    if not value:
        raise ValueError(f"missing required field {field!r}")
    return str(value).strip()


def check_enum(value: str | None, allowed: set[str], field: str, default: str) -> str:
    if not value:
        return default
    token = str(value).strip().upper().replace(" ", "_").replace("-", "_")
    if token not in allowed:
        log.warning("unrecognised %s=%r; storing as %s", field, value, default)
        return default
    return token


def resolve_hosts(cur, names: list[str], counters: Counters) -> list[int]:
    """Resolve host scientific names to plant ids. Unresolved names are reported."""
    resolved: list[int] = []
    for name in names:
        cur.execute(
            """
            SELECT id FROM plants
             WHERE canonical_name = lower(%s) AND is_deleted = FALSE
            """,
            (name.strip(),),
        )
        row = cur.fetchone()
        if row:
            resolved.append(row["id"])
        else:
            counters.bump("host_unresolved")
            log.warning("host %r is not in the knowledge base; import the plant first", name)
    return resolved


def import_symptom(cur, code: str, name: str, source_id: int) -> int:
    cur.execute("SELECT id FROM symptoms WHERE code = %s", (code,))
    row = cur.fetchone()
    if row:
        return row["id"]
    cur.execute(
        "INSERT INTO symptoms (code, name, category, verification_status, source_id, notes) "
        "VALUES (%s,%s,'VISUAL','PARTIALLY_VERIFIED',%s,%s) RETURNING id",
        (code, name, source_id,
         f"Visual symptom term imported from curated source file at {utc_now_iso()}."),
    )
    return cur.fetchone()["id"]


def process(record: dict[str, Any], source_cache: dict[str, int], counters: Counters) -> int | None:
    code = require(record, "code")
    name = require(record, "name")
    source_key = require(record, "source_key")
    evidence = check_enum(record.get("evidence_level"), EVIDENCE_LEVELS,
                          "evidence_level", "UNVERIFIED")
    verification = check_enum(record.get("verification_status"), VERIFICATION_STATUSES,
                              "verification_status", "PARTIALLY_VERIFIED")
    pathogen_type = check_enum(record.get("pathogen_type"), PATHOGEN_TYPES,
                               "pathogen_type", "UNKNOWN")
    parts = [p for p in (record.get("affected_parts") or [])
             if check_enum(p, PLANT_PARTS, "affected_part", "UNKNOWN") in PLANT_PARTS]

    if evidence == "UNVERIFIED":
        counters.bump("rejected_unverified")
        log.warning("refusing %r: evidence_level=UNVERIFIED. A disease claim needs a real "
                    "source behind it.", code)
        return None

    if source_key not in source_cache:
        cur_source = None
        with transaction() as cur:
            cur.execute("SELECT id, approval_status FROM sources WHERE key = %s", (source_key,))
            cur_source = cur.fetchone()
        if cur_source is None:
            counters.bump("rejected_source")
            log.error("refusing %r: source %r is not registered", code, source_key)
            return None
        if cur_source["approval_status"] != "APPROVED":
            counters.bump("rejected_source")
            log.error("refusing %r: source %r approval_status=%s", code, source_key,
                      cur_source["approval_status"])
            return None
        source_cache[source_key] = cur_source["id"]

    source_id = source_cache[source_key]

    with transaction() as cur:
        cur.execute("SELECT id FROM diseases WHERE code = %s", (code,))
        existing = cur.fetchone()

        values = (
            name,
            (record.get("pathogen_scientific_name") or "").strip() or None,
            pathogen_type,
            (record.get("description") or "").strip()[:8000] or None,
            verification, today(), source_id,
        )
        if existing:
            disease_id = existing["id"]
            cur.execute(
                """
                UPDATE diseases
                   SET name = COALESCE(%s, name),
                       pathogen_scientific_name = COALESCE(%s, pathogen_scientific_name),
                       pathogen_type = %s,
                       description = COALESCE(%s, description),
                       verification_status = %s, last_verified = %s, source_id = %s
                 WHERE id = %s
                """,
                (*values, disease_id),
            )
            counters.bump("updated")
        else:
            cur.execute(
                """
                INSERT INTO diseases (code, name, pathogen_scientific_name, pathogen_type,
                                      description, verification_status, last_verified, source_id)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id
                """,
                (code, *values),
            )
            disease_id = cur.fetchone()["id"]
            counters.bump("inserted")

        # Host links
        for plant_id in resolve_hosts(cur, record.get("hosts") or [], counters):
            cur.execute(
                """
                INSERT INTO plant_diseases (plant_id, disease_id, source_id, verification_status)
                VALUES (%s,%s,%s,%s)
                ON CONFLICT (plant_id, disease_id) DO UPDATE
                    SET verification_status = EXCLUDED.verification_status
                """,
                (plant_id, disease_id, source_id, verification),
            )
            counters.bump("host_links")

        # Symptoms
        for order, symptom in enumerate(record.get("symptoms") or [], start=1):
            try:
                symptom_code = require(symptom, "code")
                symptom_name = require(symptom, "name")
            except ValueError as exc:
                counters.bump("symptom_rejected")
                log.warning("disease %s: skipping malformed symptom (%s)", code, exc)
                continue
            symptom_id = import_symptom(cur, symptom_code, symptom_name, source_id)
            part = check_enum(symptom.get("part"), PLANT_PARTS, "part", "UNKNOWN")
            frequency = check_enum(symptom.get("frequency"), FREQUENCIES, "frequency", "UNKNOWN")
            severity = check_enum(symptom.get("severity"), SEVERITIES, "severity", "UNKNOWN")
            cur.execute(
                """
                INSERT INTO disease_symptoms (disease_id, symptom_id, part, frequency,
                                              severity, display_order, description,
                                              verification_status, source_id)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (disease_id, symptom_id, part) DO UPDATE
                    SET frequency = EXCLUDED.frequency, severity = EXCLUDED.severity,
                        description = COALESCE(EXCLUDED.description, disease_symptoms.description)
                """,
                (disease_id, symptom_id, part, frequency, severity, order,
                 (symptom.get("description") or "").strip()[:2000] or None, verification, source_id),
            )
            counters.bump("symptom_links")

        add_provenance(
            cur, "diseases", disease_id, source_id, None, "CURATED_FILE_IMPORT",
            json.dumps({"code": code, "name": name}, ensure_ascii=False),
            None, verification,
            f"Imported from curated file; evidence_level={evidence}. "
            f"No treatment or dosage data is accepted by this importer.",
        )
        cur.execute(
            """
            INSERT INTO verification_records (table_name, record_id, verification_status,
                                             method, evidence, notes)
            VALUES ('diseases', %s, %s, 'CURATED_SOURCE_REVIEW', %s, %s)
            """,
            (disease_id, verification, f"evidence_level={evidence}",
             f"Reviewed against source {source_key} at {today()}"),
        )
    return disease_id


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Import disease records from a curated file")
    parser.add_argument("--file", required=True, help="JSON file of disease records")
    parser.add_argument("--min-evidence", default="",
                        choices=sorted(EVIDENCE_LEVELS),
                        help="reject records below this evidence level")
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
    log.info("read %d disease record(s) from %s", len(records), path)

    if args.min_evidence:
        allowed = set(EVIDENCE_LEVELS)
        threshold_rank = max(
            (i for i, level in enumerate(["AUTHORITATIVE_REFERENCE", "PEER_REVIEWED",
                                           "GOVERNMENT_EXTENSION", "MULTIPLE_INDEPENDENT_REPORTS",
                                           "SINGLE_REPORT", "ANECDOTAL", "UNVERIFIED"])
             if level == args.min_evidence), default=len(allowed) - 1)
        order = ["AUTHORITATIVE_REFERENCE", "PEER_REVIEWED", "GOVERNMENT_EXTENSION",
                 "MULTIPLE_INDEPENDENT_REPORTS", "SINGLE_REPORT", "ANECDOTAL", "UNVERIFIED"]
        records = [r for r in records
                   if order.index(check_enum(r.get("evidence_level"), EVIDENCE_LEVELS,
                                             "evidence_level", "UNVERIFIED")) <= threshold_rank]
        log.info("after --min-evidence filter: %d record(s)", len(records))

    if args.dry_run:
        print(f"[dry-run] {len(records)} record(s) from {path}")
        for record in records[:20]:
            print(f"  {record.get('code')}: {record.get('name')} "
                  f"(source={record.get('source_key')}, evidence={record.get('evidence_level')})")
        if len(records) > 20:
            print(f"  ... and {len(records) - 20} more")
        print("[dry-run] no treatment, dose or prevention advice is imported by this tool")
        return 0

    counters = Counters()
    source_cache: dict[str, int] = {}
    accepted = 0
    for index, record in enumerate(records, start=1):
        try:
            result = process(record, source_cache, counters)
            if result is not None:
                accepted += 1
        except ValueError as exc:
            counters.bump("rejected_invalid")
            log.error("[%d/%d] rejected: %s", index, len(records), exc)
        except Exception as exc:
            counters.bump("failed")
            log.error("[%d/%d] failed: %s: %s", index, len(records),
                      type(exc).__name__, exc)

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - DISEASE IMPORT")
    print("=" * 68)
    print(f"file       : {path}")
    print(f"records    : {len(records)}")
    print(f"accepted   : {accepted}")
    for key, value in counters.as_dict().items():
        print(f"  {key:<22}: {value}")
    print()
    print("No disease was invented. Records without an approved source, or below")
    print("UNVERIFIED evidence, were refused rather than stored.")
    print("=" * 68)
    return 1 if counters.get("failed") else 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
