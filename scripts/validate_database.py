#!/usr/bin/env python3
"""Validate the PlantDoctor knowledge base and write a data quality report.

Every check below reports a real, reproducible condition. Nothing is inferred
and no record is repaired automatically: a finding is evidence for a human
decision, not an instruction to overwrite curated data.

Checks cover the categories required for data quality assurance:
missing names, duplicate species, duplicate images, invalid paths, missing
sources, invalid taxonomy, missing disease relationships, missing toxicity
status, suspicious dosage records, broken/corrupt images, incorrect
extensions, and conflicting information.

Usage:
    python3 scripts/validate_database.py --dry-run
    python3 scripts/validate_database.py
    python3 scripts/validate_database.py --checks missing_names,duplicate_species
    python3 scripts/validate_database.py --fail-on SEVERE
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Callable

from _common import (
    CHECKER_VERSION,
    Counters,
    get_logger,
    rel_to_data_root,
    resolve_data_path,
    setup_logging,
    today,
    transaction,
    utc_now_iso,
)

log = get_logger("validate_database")

Finding = tuple[str, str, str, str | None, int | None, str | None, str, str]
# check_key, severity, category, table, record_id, field, message, suggested_action
#
# Severity reflects risk to a user, not how much work is needed. A missing
# common name is MILD because the knowledge base is expected to be incomplete
# while it grows; a dose with no jurisdiction, or an image licensed as unknown
# but already fed to a model, is SEVERE.


# ---------------------------------------------------------------------------
# Individual checks. Each returns findings; each is a pure read.
# ---------------------------------------------------------------------------


def check_missing_names(cur) -> list[Finding]:
    cur.execute(
        """
        SELECT id, scientific_name FROM plants
         WHERE is_deleted = FALSE
           AND NOT EXISTS (SELECT 1 FROM plant_names n WHERE n.plant_id = plants.id)
         ORDER BY id
        """
    )
    return [
        ("PLANT_MISSING_NAME", "MILD", "COMPLETENESS", "plants", r["id"], None,
         f"plant {r['scientific_name']!r} has no common name in any language",
         "add a common name from an approved source, or leave absent deliberately")
        for r in cur.fetchall()
    ]


def check_missing_taxonomy(cur) -> list[Finding]:
    cur.execute(
        """
        SELECT id, scientific_name, family, order_name FROM plants
         WHERE is_deleted = FALSE AND (family IS NULL OR order_name IS NULL)
         ORDER BY id
        """
    )
    return [
        ("PLANT_MISSING_TAXONOMY", "MILD", "COMPLETENESS", "plants", r["id"], None,
         f"plant {r['scientific_name']!r} lacks family/order (family={r['family']!r}, order={r['order_name']!r})",
         "re-run the GBIF import so the higher classification chain is populated")
        for r in cur.fetchall()
    ]


def check_invalid_taxonomy(cur) -> list[Finding]:
    """A species-level record must not claim to be a genus, and vice versa."""
    cur.execute(
        """
        SELECT id, scientific_name, genus, species FROM plants
         WHERE is_deleted = FALSE
           AND (
                (species IS NOT NULL AND genus IS NOT NULL AND lower(species) NOT LIKE lower(genus) || ' %')
             )
         ORDER BY id
        """
    )
    return [
        ("PLANT_TAXONOMY_INCONSISTENT", "MODERATE", "TAXONOMY", "plants", r["id"], "species",
         f"species {r['species']!r} does not sit under its recorded genus {r['genus']!r}",
         "verify the record against the GBIF Backbone Taxonomy and correct the stored name")
        for r in cur.fetchall()
    ]


def check_duplicate_species(cur) -> list[Finding]:
    """No two live plants may share a canonical name; the unique index should
    make this impossible, so a hit means the index was dropped."""
    cur.execute(
        """
        SELECT canonical_name, count(*) AS n, array_agg(id ORDER BY id) AS ids
          FROM plants
         WHERE is_deleted = FALSE
         GROUP BY canonical_name
        HAVING count(*) > 1
         ORDER BY canonical_name
        """
    )
    return [
        ("PLANT_DUPLICATE_SPECIES", "MODERATE", "DUPLICATE", "plants", None, "canonical_name",
         f"canonical name {r['canonical_name']!r} is held by {r['n']} plants (ids={r['ids']})",
         "merge with fn_merge_duplicate_plants(keep, drop) after reviewing provenance")
        for r in cur.fetchall()
    ]


def check_duplicate_images(cur) -> list[Finding]:
    """Identical bytes stored twice. Reported, never auto-deleted."""
    cur.execute(
        """
        SELECT file_sha256, count(*) AS n, array_agg(id ORDER BY id) AS ids
          FROM images
         GROUP BY file_sha256
        HAVING count(*) > 1
         ORDER BY count(*) DESC
         LIMIT 500
        """
    )
    return [
        ("IMAGE_DUPLICATE_CONTENT", "MILD", "DUPLICATE", "images", None, "file_sha256",
         f"{r['n']} image rows share sha256 {r['file_sha256'][:16]}... (ids={r['ids']})",
         "run scripts/deduplicate_images.py to mark is_duplicate_of, then review")
        for r in cur.fetchall()
    ]


def check_duplicate_image_paths(cur) -> list[Finding]:
    cur.execute(
        """
        SELECT file_path, count(*) AS n FROM images
         GROUP BY file_path HAVING count(*) > 1
         ORDER BY file_path LIMIT 500
        """
    )
    return [
        ("IMAGE_DUPLICATE_PATH", "MILD", "DUPLICATE", "images", None, "file_path",
         f"path {r['file_path']!r} is registered {r['n']} times",
         "keep one row per physical file and link the others with is_derivative_of")
        for r in cur.fetchall()
    ]


def check_missing_source(cur) -> list[Finding]:
    """Every record presented to a user as fact must name where it came from."""
    out: list[Finding] = []
    for table, column, label in (
        ("plants", "taxonomic_source_id", "plant"),
        ("diseases", "source_id", "disease"),
        ("pests", "source_id", "pest"),
        ("nutrient_deficiencies", "source_id", "nutrient deficiency"),
        ("environmental_stresses", "source_id", "environmental stress"),
        ("treatments", "source_id", "treatment"),
        ("toxicity_profiles", "source_id", "toxicity profile"),
    ):
        cur.execute(
            f"SELECT id FROM {table} WHERE {column} IS NULL ORDER BY id LIMIT 500"
        )
        for row in cur.fetchall():
            out.append((
                "RECORD_MISSING_SOURCE", "MODERATE", "PROVENANCE", table, row["id"], column,
                f"{label} {row['id']} has no {column}, so its facts cannot be attributed",
                "attach an approved source or mark the record UNVERIFIED and hide it from the app",
            ))
    return out


def check_orphan_provenance(cur) -> list[Finding]:
    """Provenance pointing at a source that was never registered."""
    cur.execute(
        """
        SELECT p.id, p.table_name, p.record_id
          FROM data_provenance p
         WHERE p.source_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM sources s WHERE s.id = p.source_id)
         ORDER BY p.id LIMIT 200
        """
    )
    return [
        ("PROVENANCE_ORPHAN_SOURCE", "MODERATE", "PROVENANCE", "data_provenance", r["id"], "source_id",
         f"provenance row {r['id']} references source_id {r['id']} which does not exist",
         "re-register the source or clear the dangling reference")
        for r in cur.fetchall()
    ]


def check_disease_relationships(cur) -> list[Finding]:
    out: list[Finding] = []
    cur.execute(
        """
        SELECT id, name FROM diseases
         WHERE NOT EXISTS (SELECT 1 FROM disease_symptoms ds WHERE ds.disease_id = diseases.id)
         ORDER BY id
        """
    )
    for row in cur.fetchall():
        out.append((
            "DISEASE_WITHOUT_SYMPTOMS", "MODERATE", "COMPLETENESS", "diseases", row["id"], None,
            f"disease {row['name']!r} has no linked symptoms, so it cannot be visually screened",
            "link symptoms from an authoritative description before showing it in the app",
        ))
    cur.execute(
        """
        SELECT id, name FROM diseases
         WHERE NOT EXISTS (SELECT 1 FROM plant_diseases pd WHERE pd.disease_id = diseases.id)
         ORDER BY id
        """
    )
    for row in cur.fetchall():
        out.append((
            "DISEASE_WITHOUT_HOSTS", "MILD", "COMPLETENESS", "diseases", row["id"], None,
            f"disease {row['name']!r} is not linked to any host plant",
            "record affected plants so host-specific guidance can be returned",
        ))
    return out


def check_toxicity_coverage(cur) -> list[Finding]:
    """Absence of a toxicity record is a gap, never a 'safe' verdict.

    The knowledge base is explicit about this: an unknown plant is reported as
    UNKNOWN. This check makes sure that behaviour is still wired up, and flags
    any record that claims safety without a source.
    """
    out: list[Finding] = []
    cur.execute(
        """
        SELECT count(*) AS n FROM plants p
         WHERE p.is_deleted = FALSE
           AND NOT EXISTS (SELECT 1 FROM toxicity_profiles t WHERE t.plant_id = p.id)
        """
    )
    unknown_count = cur.fetchone()["n"]
    if unknown_count:
        out.append((
            "TOXICITY_UNKNOWN_COVERAGE", "UNKNOWN", "COMPLETENESS", "plants", None, None,
            f"{unknown_count} plant(s) have no toxicity profile; the API correctly reports "
            "these as UNKNOWN rather than safe",
            "add profiles from an authoritative toxicology or veterinary reference",
        ))

    # A non-toxic verdict without a source is the dangerous case.
    cur.execute(
        """
        SELECT id, plant_id FROM toxicity_profiles
         WHERE toxicity_status = 'NON_TOXIC' AND source_id IS NULL
         ORDER BY id
        """
    )
    for row in cur.fetchall():
        out.append((
            "TOXICITY_SAFE_WITHOUT_SOURCE", "SEVERE", "SAFETY", "toxicity_profiles", row["id"],
            "source_id",
            f"toxicity profile {row['id']} asserts NON_TOXIC with no source",
            "attach an authoritative source or downgrade the status to UNKNOWN",
        ))
    return out


def check_dosage_plausibility(cur) -> list[Finding]:
    """A dosage without a jurisdiction, label or verification is not usable.

    Dosage is never universal. It depends on country, crop, formulation,
    concentration, growth stage and the current label. A record missing any of
    those must not reach a user, so it is treated as severe rather than as an
    incomplete field.
    """
    cur.execute(
        """
        SELECT d.id, d.treatment_id, d.jurisdiction, d.label_url, d.label_sha256,
               d.label_source_document_id, d.verification_status, t.code AS treatment_code
          FROM treatment_dosages d
          LEFT JOIN treatments t ON t.id = d.treatment_id
         WHERE d.dose_value IS NOT NULL
           AND (d.jurisdiction IS NULL
             OR d.label_url IS NULL
             OR (d.label_sha256 IS NULL AND d.label_source_document_id IS NULL)
             OR d.verification_status IS DISTINCT FROM 'VERIFIED')
         ORDER BY d.id LIMIT 200
        """
    )
    out: list[Finding] = []
    for r in cur.fetchall():
        gaps = []
        if r["jurisdiction"] is None:
            gaps.append("jurisdiction missing")
        if r["label_url"] is None:
            gaps.append("label_url missing")
        if r["label_sha256"] is None and r["label_source_document_id"] is None:
            gaps.append("no label document or checksum")
        if r["verification_status"] != "VERIFIED":
            gaps.append(f"verification_status={r['verification_status']}")
        out.append((
            "DOSAGE_MISSING_JURISDICTION_OR_LABEL", "SEVERE", "SAFETY", "treatment_dosages", r["id"],
            "jurisdiction",
            f"dosage {r['id']} (treatment {r['treatment_code'] or r['treatment_id']}) is missing: "
            + ", ".join(gaps),
            "supply the product label and its jurisdiction; otherwise remove the dose value",
        ))
    return out


def check_dosage_range(cur) -> list[Finding]:
    cur.execute(
        """
        SELECT id, dose_min_value, dose_max_value FROM treatment_dosages
         WHERE dose_min_value IS NOT NULL AND dose_max_value IS NOT NULL
           AND dose_min_value > dose_max_value
         ORDER BY id
        """
    )
    return [
        ("DOSAGE_RANGE_INVERTED", "SEVERE", "SAFETY", "treatment_dosages", r["id"], "dose_min_value",
         f"dosage {r['id']} has min {r['dose_min_value']} greater than max {r['dose_max_value']}",
         "correct the range against the product label")
        for r in cur.fetchall()
    ]


def check_image_paths(cur) -> list[Finding]:
    """Registered images must resolve to a real, readable file."""
    out: list[Finding] = []
    cur.execute("SELECT id, file_path FROM images ORDER BY id LIMIT 2000")
    for row in cur.fetchall():
        path = resolve_data_path(row["file_path"])
        if not path.exists():
            out.append((
                "IMAGE_PATH_MISSING", "MODERATE", "INTEGRITY", "images", row["id"], "file_path",
                f"image {row['id']} points at {row['file_path']!r} which does not exist",
                "restore the file or mark the row unusable with unusable_reason",
            ))
        elif path.stat().st_size == 0:
            out.append((
                "IMAGE_FILE_EMPTY", "MODERATE", "INTEGRITY", "images", row["id"], "file_path",
                f"image {row['id']} points at a zero-byte file {row['file_path']!r}",
                "re-fetch the file or mark the row unusable",
            ))
    return out


def check_image_extensions(cur) -> list[Finding]:
    """The stored extension must match the stored mime type."""
    pairs = {
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
        "webp": "image/webp", "gif": "image/gif", "bmp": "image/bmp",
        "tif": "image/tiff", "tiff": "image/tiff",
    }
    cur.execute(
        """
        SELECT id, file_path, file_extension, mime_type FROM images
         WHERE file_extension IS NOT NULL OR mime_type IS NOT NULL
         ORDER BY id LIMIT 2000
        """
    )
    out: list[Finding] = []
    for row in cur.fetchall():
        ext = (row["file_extension"] or "").lower().lstrip(".")
        suffix = Path(row["file_path"]).suffix.lower().lstrip(".")
        expected = pairs.get(ext)
        if expected and row["mime_type"] and row["mime_type"] != expected:
            out.append((
                "IMAGE_MIME_MISMATCH", "MILD", "INTEGRITY", "images", row["id"], "mime_type",
                f"image {row['id']} extension {ext!r} implies {expected} but mime_type is "
                f"{row['mime_type']!r}",
                "re-detect the mime type from the file contents",
            ))
        if ext and suffix and ext != suffix:
            out.append((
                "IMAGE_EXTENSION_MISMATCH", "MILD", "INTEGRITY", "images", row["id"], "file_extension",
                f"image {row['id']} records extension {ext!r} but the path ends in {suffix!r}",
                "correct file_extension to match the actual file",
            ))
    return out


def check_training_usability(cur) -> list[Finding]:
    """An image marked usable for training must be licensed, sourced and verified.

    This is the gate that stops an unlicensed photo from silently entering a
    model, so violations are severe.
    """
    cur.execute(
        """
        SELECT id, file_path, license, copyright_status, source_id, verified, annotation_status
          FROM images
         WHERE is_usable_for_training
           AND ( license IN ('UNKNOWN', 'PROPRIETARY')
              OR copyright_status IN ('UNKNOWN', 'ALL_RIGHTS_RESERVED')
              OR source_id IS NULL
              OR verified = FALSE
              OR annotation_status = 'UNANNOTATED' )
         ORDER BY id LIMIT 500
        """
    )
    out: list[Finding] = []
    for row in cur.fetchall():
        problems = []
        if row["license"] in ("UNKNOWN", "PROPRIETARY"):
            problems.append(f"license={row['license']}")
        if row["copyright_status"] in ("UNKNOWN", "ALL_RIGHTS_RESERVED"):
            problems.append(f"copyright_status={row['copyright_status']}")
        if row["source_id"] is None:
            problems.append("no source_id")
        if not row["verified"]:
            problems.append("verified=false")
        if row["annotation_status"] == "UNANNOTATED":
            problems.append("annotation_status=UNANNOTATED")
        out.append((
            "IMAGE_TRAINING_GATE_VIOLATION", "SEVERE", "LEGAL", "images", row["id"],
            "is_usable_for_training",
            f"image {row['id']} ({row['file_path']!r}) is flagged usable for training but has: "
            + ", ".join(problems),
            "clear is_usable_for_training until the licence, source and verification are in place",
        ))
    return out


def check_conflicts(cur) -> list[Finding]:
    """Unresolved contradictions are surfaced, never silently merged."""
    cur.execute(
        """
        SELECT id, table_name, record_id, field_name, status FROM record_conflicts
         WHERE status = 'OPEN' ORDER BY id LIMIT 200
        """
    )
    return [
        ("RECORD_CONFLICT_OPEN", "MODERATE", "CONFLICT", "record_conflicts", r["id"], "field_name",
         f"open conflict on {r['table_name']}.{r['field_name']} (record {r['record_id']})",
         "resolve against the higher-quality source; do not average the two values")
        for r in cur.fetchall()
    ]


def check_conflicting_verification(cur) -> list[Finding]:
    cur.execute(
        """
        SELECT id FROM plants
         WHERE verification_status = 'CONFLICTING' AND is_deleted = FALSE
         ORDER BY id
        """
    )
    return [
        ("PLANT_STATUS_CONFLICTING", "MODERATE", "CONFLICT", "plants", r["id"], "verification_status",
         f"plant {r['id']} is marked CONFLICTING and must not be presented as settled fact",
         "resolve the underlying conflict, then update the status")
        for r in cur.fetchall()
    ]


def check_plant_disease_integrity(cur) -> list[Finding]:
    """A host link must reference a live plant and a real disease."""
    cur.execute(
        """
        SELECT pd.id, pd.plant_id, pd.disease_id
          FROM plant_diseases pd
          JOIN plants p ON p.id = pd.plant_id AND p.is_deleted = FALSE
         WHERE pd.disease_id IS NULL
         ORDER BY pd.id LIMIT 200
        """
    )
    return [
        ("PLANT_DISEASE_NULL_DISEASE", "SEVERE", "INTEGRITY", "plant_diseases", r["id"], "disease_id",
         f"host link {r['id']} for plant {r['plant_id']} has no disease_id",
         "supply the disease or delete the link")
        for r in cur.fetchall()
    ]


def check_appearance_without_source(cur) -> list[Finding]:
    """Appearance text describes what a healthy plant looks like. If it has no
    source it is effectively invented, which the project forbids."""
    cur.execute(
        """
        SELECT id, plant_id, part FROM plant_appearance
         WHERE description IS NOT NULL AND source_id IS NULL
         ORDER BY id LIMIT 200
        """
    )
    return [
        ("APPEARANCE_WITHOUT_SOURCE", "SEVERE", "PROVENANCE", "plant_appearance", r["id"], "description",
         f"appearance record {r['id']} (plant {r['plant_id']}, part {r['part']}) has descriptive "
         "text with no source",
         "attach the source the text came from, or delete the text")
        for r in cur.fetchall()
    ]


def check_unmeasured_metrics(cur) -> list[Finding]:
    """A stored metric must say how it was obtained.

    Guards against a placeholder number quietly becoming a 'measured' figure on
    the science-fair dashboard. A metric value is only believable if it records
    when it was measured, on how many samples, and by which script.
    """
    cur.execute(
        """
        SELECT id, metric_name, metric_value, measured_at, sample_size, measurement_script
          FROM model_metrics
         WHERE metric_value IS NOT NULL
           AND (measured_at IS NULL OR sample_size IS NULL OR sample_size <= 0
                OR measurement_script IS NULL)
         ORDER BY id LIMIT 200
        """
    )
    out: list[Finding] = []
    for r in cur.fetchall():
        gaps = []
        if r["measured_at"] is None:
            gaps.append("measured_at missing")
        if r["sample_size"] is None or r["sample_size"] <= 0:
            gaps.append(f"sample_size={r['sample_size']}")
        if r["measurement_script"] is None:
            gaps.append("measurement_script missing")
        out.append((
            "MODEL_METRIC_UNMEASURED_VALUE", "SEVERE", "INTEGRITY", "model_metrics", r["id"],
            "metric_value",
            f"metric {r['metric_name']!r} stores value {r['metric_value']} but is untraceable: "
            + ", ".join(gaps),
            "either measure the metric and record how, or null the value so the dashboard "
            "shows 'Not measured yet'",
        ))
    return out


CHECKS: dict[str, Callable[[Any], list[Finding]]] = {
    "missing_names": check_missing_names,
    "missing_taxonomy": check_missing_taxonomy,
    "invalid_taxonomy": check_invalid_taxonomy,
    "duplicate_species": check_duplicate_species,
    "duplicate_images": check_duplicate_images,
    "duplicate_image_paths": check_duplicate_image_paths,
    "missing_source": check_missing_source,
    "orphan_provenance": check_orphan_provenance,
    "disease_relationships": check_disease_relationships,
    "toxicity": check_toxicity_coverage,
    "dosage": check_dosage_plausibility,
    "dosage_range": check_dosage_range,
    "image_paths": check_image_paths,
    "image_extensions": check_image_extensions,
    "training_gate": check_training_usability,
    "conflicts": check_conflicts,
    "conflicting_verification": check_conflicting_verification,
    "plant_disease_integrity": check_plant_disease_integrity,
    "appearance_provenance": check_appearance_without_source,
    "unmeasured_metrics": check_unmeasured_metrics,
}

# Severities that mean "a user could be misled", used for --fail-on.
SEVERE_ORDER = {"UNKNOWN": 0, "NONE": 1, "MILD": 2, "MODERATE": 3, "SEVERE": 4, "LIFE_THREATENING": 5}


def run_checks(selected: list[str]) -> tuple[list[Finding], int]:
    findings: list[Finding] = []
    total = 0
    with transaction() as cur:
        for name in selected:
            check = CHECKS[name]
            # Each check runs inside its own savepoint. Without this, the first
            # bad query aborts the whole transaction and every later check then
            # reports a misleading "transaction is aborted" error, hiding the
            # areas that were never actually examined.
            cur.execute("SAVEPOINT check_start")
            try:
                result = check(cur)
            except Exception as exc:  # a broken check must not hide the others
                cur.execute("ROLLBACK TO SAVEPOINT check_start")
                log.error("check %s raised %s: %s", name, type(exc).__name__, exc)
                findings.append((
                    f"CHECK_ERROR_{name.upper()}", "MODERATE", "HARNESS", None, None, None,
                    f"check {name!r} failed to run: {type(exc).__name__}: {exc}",
                    "fix the check; its subject area is currently unvalidated",
                ))
                continue
            cur.execute("RELEASE SAVEPOINT check_start")
            total += 1
            findings.extend(result)
            log.info("check %-28s %d finding(s)", name, len(result))
    return findings, total


def persist_report(run_key: str, findings: list[Finding], total_checks: int, report_path: str | None) -> dict[str, Any]:
    counts = Counters()
    for f in findings:
        counts.bump(f[1])
    summary = {
        "run_key": run_key,
        "generated_at": utc_now_iso(),
        "checker_version": CHECKER_VERSION,
        "checks_run": total_checks,
        "finding_count": len(findings),
        "by_severity": counts.as_dict(),
        "note": (
            "Findings are evidence for human review. This tool never repairs, "
            "deletes or rewrites knowledge-base records on its own."
        ),
    }
    with transaction() as cur:
        cur.execute(
            """
            INSERT INTO data_quality_reports (run_key, scope, checker_version, total_checked,
                                              passed, warnings, failed, report_path, summary, status)
            VALUES (%s, 'FULL', %s, %s, 0, %s, %s, %s, %s, 'COMPLETED')
            ON CONFLICT (run_key) DO UPDATE
               SET finished_at = now(), checker_version = EXCLUDED.checker_version,
                   total_checked = EXCLUDED.total_checked, warnings = EXCLUDED.warnings,
                   failed = EXCLUDED.failed, report_path = EXCLUDED.report_path,
                   summary = EXCLUDED.summary, status = 'COMPLETED'
            RETURNING id
            """,
            (run_key, CHECKER_VERSION, total_checks,
             counts.get("MODERATE") + counts.get("MILD") + counts.get("UNKNOWN"),
             counts.get("SEVERE") + counts.get("LIFE_THREATENING"),
             report_path, json.dumps(summary)),
        )
        report_id = cur.fetchone()["id"]
        cur.execute("DELETE FROM data_quality_findings WHERE report_id = %s", (report_id,))
        for check_key, severity, category, table, record_id, field, message, action in findings:
            cur.execute(
                """
                INSERT INTO data_quality_findings (report_id, check_key, severity, category,
                                                   table_name, record_id, field_name, message,
                                                   suggested_action)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                (report_id, check_key, severity, category, table, record_id,
                 field, message, action),
            )
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate the PlantDoctor knowledge base")
    parser.add_argument("--checks", default="",
                        help=f"comma-separated subset of: {', '.join(sorted(CHECKS))}")
    parser.add_argument("--run-key", default=None,
                        help="identifier for this report (default: timestamp)")
    parser.add_argument("--report-json", default=None,
                        help="also write the findings to this JSON path")
    parser.add_argument("--dry-run", action="store_true",
                        help="run the checks and print results without writing a report")
    parser.add_argument("--fail-on", default="SEVERE",
                        choices=["NONE", "MILD", "MODERATE", "SEVERE", "LIFE_THREATENING"],
                        help="exit non-zero when a finding reaches this severity")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    setup_logging(args.log_level)
    selected = [c.strip() for c in args.checks.split(",") if c.strip()] or sorted(CHECKS)
    unknown = [c for c in selected if c not in CHECKS]
    if unknown:
        raise SystemExit(f"unknown check(s): {unknown}. available: {sorted(CHECKS)}")

    run_key = args.run_key or f"validate-{today()}-{utc_now_iso().replace(':', '').replace('-', '')}"
    log.info("running %d check(s); run_key=%s dry_run=%s", len(selected), run_key, args.dry_run)

    findings, total_checks = run_checks(selected)

    by_sev = Counters()
    for f in findings:
        by_sev.bump(f[1])
    by_check = Counters()
    for f in findings:
        by_check.bump(f[0])

    report_path = None
    if args.report_json:
        candidate = Path(args.report_json)
        candidate.parent.mkdir(parents=True, exist_ok=True)
        candidate.write_text(json.dumps({
            "run_key": run_key,
            "generated_at": utc_now_iso(),
            "checker_version": CHECKER_VERSION,
            "by_severity": by_sev.as_dict(),
            "findings": [
                {
                    "check_key": f[0], "severity": f[1], "category": f[2],
                    "table_name": f[3], "record_id": f[4], "field_name": f[5],
                    "message": f[6], "suggested_action": f[7],
                }
                for f in findings
            ],
        }, indent=2), encoding="utf-8")
        report_path = str(candidate)
        log.info("wrote %s", report_path)

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - DATA QUALITY REPORT")
    print("=" * 68)
    print(f"run key        : {run_key}")
    print(f"checks run     : {total_checks}")
    print(f"findings       : {len(findings)}")
    for severity, count in by_sev.as_dict().items():
        print(f"  {severity:<15}: {count}")
    if findings:
        print()
        print("top checks:")
        for check_key, count in sorted(by_check.as_dict().items(), key=lambda kv: -kv[1])[:10]:
            print(f"  {check_key:<34} {count}")
        print()
        print("highest-severity findings:")
        ranked = sorted(findings, key=lambda f: -SEVERE_ORDER.get(f[1], 0))
        for f in ranked[:15]:
            print(f"  [{f[1]:<14}] {f[0]}: {f[6]}")
        if len(ranked) > 15:
            print(f"  ... and {len(ranked) - 15} more")
    print("=" * 68)
    print("No record was modified. Findings require human review.")
    print("=" * 68)

    if not args.dry_run:
        summary = persist_report(run_key, findings, total_checks, report_path)
        log.info("report persisted: %s", json.dumps(summary["by_severity"]))
        if report_path:
            with transaction() as cur:
                cur.execute(
                    "UPDATE data_quality_reports SET report_path = %s WHERE run_key = %s",
                    (rel_to_data_root(Path(report_path)), run_key),
                )

    threshold = SEVERE_ORDER.get(args.fail_on, 4)
    worst = max((SEVERE_ORDER.get(f[1], 0) for f in findings), default=0)
    if args.fail_on != "NONE" and worst >= threshold:
        log.warning("findings at or above %s detected", args.fail_on)
        return 2
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
