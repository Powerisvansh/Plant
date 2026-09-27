#!/usr/bin/env python3
"""Controlled dataset import pipeline.

The pipeline is deliberately staged, and each stage is a separate command so a
dataset can be inspected between steps:

    register   record the dataset, its licence and its provenance
    ingest     walk the files, hash them, insert image metadata rows
    label      map the dataset's own label names onto knowledge-base records
    dedup      run duplicate detection (delegates to deduplicate_images.py)
    split      assign train / validation / test

Two rules are enforced rather than documented and hoped for:

  1. A dataset is only ingested if its licence is recorded and its
     `license_verified` flag is true. An unverified licence blocks the import.
  2. No image is marked usable for training until it has a resolved knowledge
     base label and a source. Unlabelled images are imported as
     is_usable_for_training = FALSE, so a partially mapped dataset is useful
     for inspection without contaminating a model.

Usage:
    python3 scripts/import_dataset.py register --key plantvillage \\
        --name "PlantVillage" --local-path datasets/raw/plantvillage \\
        --source-key plantvillage --license CC_BY_4_0 --confirm-license
    python3 scripts/import_dataset.py ingest  --key plantvillage --dry-run
    python3 scripts/import_dataset.py label   --key plantvillage --map data/plantvillage_labels.csv
    python3 scripts/import_dataset.py split  --key plantvillage --ratios 0.7 0.15 0.15
    python3 scripts/import_dataset.py status --key plantvillage
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import sys
from pathlib import Path
from typing import Any

from _common import (
    Counters,
    REDISTRIBUTABLE_LICENSES,
    get_logger,
    human_bytes,
    normalise_license,
    rel_to_data_root,
    resolve_data_path,
    setup_logging,
    today,
    transaction,
    utc_now_iso,
)

log = get_logger("import_dataset")

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff"}


# ---------------------------------------------------------------------------
# register
# ---------------------------------------------------------------------------


def cmd_register(args: argparse.Namespace) -> int:
    license_value = normalise_license(args.license)
    if license_value not in REDISTRIBUTABLE_LICENSES:
        log.error(
            "licence %r is not on the redistributable allow list %s. Register the source "
            "with its real terms and, if the data genuinely cannot be redistributed, "
            "keep it local instead of importing it.",
            license_value, sorted(REDISTRIBUTABLE_LICENSES),
        )
        return 1
    if not args.confirm_license:
        log.error(
            "refusing to register without --confirm-license. That flag asserts you have "
            "actually read the dataset's terms of use and checked whether commercial use, "
            "redistribution or attribution are permitted."
        )
        return 1

    with transaction() as cur:
        cur.execute("SELECT id, key, name, license FROM sources WHERE key = %s", (args.source_key,))
        source = cur.fetchone()
        if source is None:
            log.error("source %r is not registered; add it to data/sources.json and run "
                      "scripts/seed_sources.py first", args.source_key)
            return 1
        cur.execute("SELECT approval_status FROM sources WHERE key = %s", (args.source_key,))
        approval = cur.fetchone()["approval_status"]
        if approval != "APPROVED":
            log.error("source %r has approval_status=%s; refusing to register a dataset "
                      "against an unapproved source", args.source_key, approval)
            return 1

        local_path = args.local_path
        if local_path and not local_path.startswith("/"):
            local_path = f"datasets/raw/{local_path}"
        absolute = resolve_data_path(local_path) if local_path else None
        if absolute is not None and not absolute.is_dir():
            log.warning("dataset directory does not exist yet: %s", absolute)

        cur.execute(
            """
            INSERT INTO datasets (name, version, description, source_id, local_path, source_url,
                                  license, license_verified, license_verified_at,
                                  license_verified_by, attribution_required, attribution_text,
                                  redistribution_allowed, commercial_use_allowed, status, notes)
            VALUES (%s,%s,%s,%s,%s,%s,%s,TRUE,now(),%s,%s,%s,%s,%s,'APPROVED',%s)
            ON CONFLICT (name, version) DO UPDATE
               SET description = EXCLUDED.description,
                   source_id = EXCLUDED.source_id,
                   local_path = EXCLUDED.local_path,
                   source_url = EXCLUDED.source_url,
                   license = EXCLUDED.license,
                   license_verified = TRUE,
                   license_verified_at = now(),
                   license_verified_by = EXCLUDED.license_verified_by,
                   attribution_required = EXCLUDED.attribution_required,
                   attribution_text = EXCLUDED.attribution_text,
                   redistribution_allowed = EXCLUDED.redistribution_allowed,
                   commercial_use_allowed = EXCLUDED.commercial_use_allowed,
                   status = 'APPROVED',
                   notes = EXCLUDED.notes
            RETURNING id
            """,
            (args.key, args.version, args.description, source["id"], local_path,
             args.remote_url, license_value, args.confirmed_by,
             args.attribution_required, args.attribution_text or source.get("attribution_text"),
             args.redistribution_allowed, args.commercial_use_allowed,
             f"Registered by scripts/import_dataset.py at {utc_now_iso()}. "
             f"Licence confirmed by {args.confirmed_by} on {today()}."),
        )
        dataset_id = cur.fetchone()["id"]

    print(f"registered dataset {args.key!r} (id={dataset_id}) licence={license_value} "
          f"license_verified=true source={args.source_key}")
    return 0


# ---------------------------------------------------------------------------
# ingest
# ---------------------------------------------------------------------------


def load_dataset(key: str) -> dict[str, Any] | None:
    """Datasets are identified by (name, version); --key names the dataset."""
    with transaction() as cur:
        cur.execute(
            "SELECT id, name, version, local_path, license, license_verified, source_id, "
            "       attribution_required, attribution_text "
            "  FROM datasets WHERE name = %s",
            (key,),
        )
        return cur.fetchone()


def cmd_ingest(args: argparse.Namespace) -> int:
    dataset = load_dataset(args.key)
    if dataset is None:
        raise SystemExit(f"dataset {args.key!r} is not registered")
    if not dataset["license_verified"]:
        log.error("dataset %s has license_verified=false; refusing to ingest. Re-register "
                  "with --confirm-license once the terms have actually been checked.",
                  args.key)
        return 1
    if not dataset["local_path"]:
        raise SystemExit(f"dataset {args.key!r} has no local_path; nothing to ingest")

    base = resolve_data_path(dataset["local_path"])
    if not base.is_dir():
        log.error("dataset directory does not exist: %s", base)
        return 1

    files = [p for p in sorted(base.rglob("*")) if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES]
    if args.limit:
        files = files[: args.limit]
    total_bytes = sum(p.stat().st_size for p in files)
    log.info("dataset %s: %d file(s), %s at %s", args.key, len(files),
             human_bytes(total_bytes), base)

    if args.dry_run:
        print(f"[dry-run] dataset={args.key} licence={dataset['license']} "
              f"verified={dataset['license_verified']}")
        print(f"[dry-run] would insert up to {len(files)} image row(s) "
              f"({human_bytes(total_bytes)}), all initially is_usable_for_training=false")
        return 0

    counters = Counters()
    with transaction() as cur:
        for index, path in enumerate(files, start=1):
            relative = rel_to_data_root(path)
            digest = hashlib.sha256()
            with path.open("rb") as handle:
                for block in iter(lambda: handle.read(1 << 20), b""):
                    digest.update(block)
            sha = digest.hexdigest()

            cur.execute("SELECT id FROM images WHERE file_path = %s", (relative,))
            if cur.fetchone():
                counters.bump("already_present")
                continue

            cur.execute(
                """
                INSERT INTO images (dataset_id, file_path, relative_path, original_filename,
                                    file_sha256, file_extension, file_bytes, license,
                                    copyright_status, source_id, is_usable_for_training,
                                    unusable_reason, notes)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,FALSE,%s,%s)
                ON CONFLICT (file_sha256, dataset_id) DO NOTHING
                """,
                (dataset["id"], relative, path.name, sha, path.suffix.lower().lstrip("."),
                 path.stat().st_size, dataset["license"],
                 "PUBLIC_DOMAIN" if dataset["license"] == "PUBLIC_DOMAIN" else "OPEN_LICENSE",
                 dataset["source_id"],
                 "awaiting label resolution and verification",
                 f"Ingested from dataset {args.key} by scripts/import_dataset.py."),
            )
            counters.bump("inserted" if cur.rowcount else "duplicate_content")
            if index % 500 == 0:
                log.info("[%d/%d] ingested", index, len(files))

        cur.execute("UPDATE datasets SET image_count = %s, obtained_at = COALESCE(obtained_at, %s) "
                    "WHERE id = %s",
                    (len(files), today(), dataset["id"]))

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - DATASET INGEST")
    print("=" * 68)
    print(f"dataset        : {args.key} ({dataset['license']}, verified)")
    print(f"directory      : {base}")
    for key, value in counters.as_dict().items():
        print(f"  {key:<20}: {value}")
    print()
    print("All ingested images are is_usable_for_training=false until a label is resolved.")
    print("Next: label, then dedup, then split.")
    print("=" * 68)
    return 0


# ---------------------------------------------------------------------------
# label
# ---------------------------------------------------------------------------


def cmd_label(args: argparse.Namespace) -> int:
    """Map a dataset's own label vocabulary onto knowledge-base records.

    The CSV must have a header and these columns:
        relative_path, label, condition_class, plant, disease, pest, symptom

    `label` is always preserved in images.original_label. A label that cannot
    be resolved to a real plant, disease, pest or symptom is reported and left
    unresolved; it is never guessed at.
    """
    dataset = load_dataset(args.key)
    if dataset is None:
        raise SystemExit(f"dataset {args.key!r} is not registered")

    mapping_path = Path(args.map)
    if not mapping_path.is_file():
        raise SystemExit(f"label map not found: {mapping_path}")
    with mapping_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    log.info("read %d label row(s) from %s", len(rows), mapping_path)

    if args.dry_run:
        for row in rows[:20]:
            print(f"  {row.get('relative_path')}: {row.get('label')} -> "
                  f"class={row.get('condition_class') or 'UNKNOWN'}")
        if len(rows) > 20:
            print(f"  ... and {len(rows) - 20} more")
        print(f"[dry-run] would resolve {len(rows)} label(s)")
        return 0

    counters = Counters()
    unresolved: list[str] = []

    with transaction() as cur:
        for row in rows:
            relative = (row.get("relative_path") or "").strip()
            label = (row.get("label") or "").strip()
            if not relative or not label:
                counters.bump("skipped_incomplete")
                continue

            cur.execute("SELECT id FROM images WHERE file_path = %s OR relative_path = %s",
                        (relative, relative))
            image = cur.fetchone()
            if image is None:
                counters.bump("image_not_found")
                continue

            condition_class = (row.get("condition_class") or "UNKNOWN").upper()
            if condition_class not in {
                "DISEASE", "PEST", "NUTRIENT_DEFICIENCY", "ENVIRONMENTAL_STRESS",
                "PHYSICAL_DAMAGE", "NORMAL_VARIATION", "UNKNOWN",
            }:
                log.warning("unknown condition_class %r for %s; storing as UNKNOWN",
                            condition_class, relative)
                condition_class = "UNKNOWN"

            plant_id = _lookup_plant(cur, row.get("plant"))
            disease_id = _lookup_disease(cur, row.get("disease"))
            pest_id = _lookup_pest(cur, row.get("pest"))
            symptom_id = _lookup_symptom(cur, row.get("symptom"))

            resolved_any = plant_id or disease_id or pest_id or symptom_id
            if condition_class != "UNKNOWN" and not resolved_any:
                counters.bump("unresolved")
                unresolved.append(f"{relative}: {label} ({condition_class})")
                condition_class = "UNKNOWN"

            if resolved_any:
                counters.bump("resolved")

            cur.execute(
                """
                UPDATE images
                   SET original_label = %s,
                       condition_class = %s,
                       condition = CASE WHEN %s = 'NORMAL_VARIATION' THEN 'HEALTHY'::image_condition
                                       WHEN %s = 'DISEASE' THEN 'DISEASED'::image_condition
                                       WHEN %s = 'PEST' THEN 'PEST_DAMAGED'::image_condition
                                       WHEN %s = 'NUTRIENT_DEFICIENCY' THEN 'NUTRIENT_DEFICIENT'::image_condition
                                       WHEN %s = 'ENVIRONMENTAL_STRESS' THEN 'STRESSED'::image_condition
                                       WHEN %s = 'PHYSICAL_DAMAGE' THEN 'DAMAGED'::image_condition
                                       ELSE 'UNKNOWN'::image_condition END,
                       plant_id = COALESCE(%s, plant_id),
                       disease_id = COALESCE(%s, disease_id),
                       pest_id = COALESCE(%s, pest_id),
                       symptom_id = COALESCE(%s, symptom_id),
                       part = COALESCE(%s::plant_part, part),
                       annotation_status = 'AUTO_LABELED',
                       updated_at = now()
                 WHERE id = %s
                """,
                (label, condition_class, condition_class, condition_class, condition_class,
                 condition_class, condition_class, condition_class, condition_class,
                 plant_id, disease_id, pest_id, symptom_id,
                 (row.get("plant_part") or "").upper() or None, image["id"]),
            )

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - DATASET LABELLING")
    print("=" * 68)
    for key, value in counters.as_dict().items():
        print(f"  {key:<22}: {value}")
    if unresolved:
        print()
        print(f"unresolved labels ({len(unresolved)}); stored as UNKNOWN, never guessed:")
        for line in unresolved[:20]:
            print(f"  {line}")
        if len(unresolved) > 20:
            print(f"  ... and {len(unresolved) - 20} more")
    print("=" * 68)
    return 0


def _lookup_plant(cur, name: str | None) -> int | None:
    if not name:
        return None
    cur.execute("SELECT id FROM plants WHERE canonical_name = lower(%s) AND is_deleted = FALSE",
                (name.strip(),))
    row = cur.fetchone()
    return row["id"] if row else None


def _lookup_by_code(cur, table: str, value: str | None) -> int | None:
    if not value:
        return None
    cur.execute(f"SELECT id FROM {table} WHERE code = %s", (value.strip(),))
    row = cur.fetchone()
    return row["id"] if row else None


def _lookup_disease(cur, value: str | None) -> int | None:
    return _lookup_by_code(cur, "diseases", value)


def _lookup_pest(cur, value: str | None) -> int | None:
    return _lookup_by_code(cur, "pests", value)


def _lookup_symptom(cur, value: str | None) -> int | None:
    return _lookup_by_code(cur, "symptoms", value)


# ---------------------------------------------------------------------------
# split
# ---------------------------------------------------------------------------


def cmd_split(args: argparse.Namespace) -> int:
    """Assign train/validation/test deterministically.

    Splitting is by a hash of the file path, not by random number, so the same
    input always produces the same split. Re-running therefore never moves an
    image between splits and quietly invalidates a previous evaluation.
    """
    dataset = load_dataset(args.key)
    if dataset is None:
        raise SystemExit(f"dataset {args.key!r} is not registered")

    total = sum(args.ratios)
    if abs(total - 1.0) > 1e-6:
        log.error("--ratios must sum to 1.0, got %s", args.ratios)
        return 1

    with transaction() as cur:
        cur.execute(
            """
            SELECT id, file_path, split, is_usable_for_training, verified, license,
                   copyright_status, source_id, annotation_status, condition_class
              FROM images WHERE dataset_id = %s ORDER BY id
            """,
            (dataset["id"],),
        )
        rows = list(cur.fetchall())

    if not rows:
        log.error("no images in dataset %s; run ingest first", args.key)
        return 1

    counters = Counters()
    blocked = 0
    assignments: list[tuple[str, int]] = []

    for row in rows:
        # Only images that are legally and evidentially ready may be split into
        # a training role. Anything else is reported rather than quietly used.
        if not row["is_usable_for_training"]:
            blocked += 1
            continue
        digest = hashlib.sha256(row["file_path"].encode("utf-8")).digest()
        bucket = int.from_bytes(digest[:4], "big") / 0xFFFFFFFF
        if bucket < args.ratios[0]:
            split = "TRAIN"
        elif bucket < args.ratios[0] + args.ratios[1]:
            split = "VALIDATION"
        else:
            split = "TEST"
        assignments.append((split, row["id"]))
        counters.bump(split.lower())

    if args.dry_run:
        print(f"[dry-run] dataset={args.key} images={len(rows)} blocked={blocked}")
        for key, value in counters.as_dict().items():
            print(f"  {key:<12}: {value}")
        return 0

    with transaction() as cur:
        for split, image_id in assignments:
            cur.execute("UPDATE images SET split = %s::dataset_split, updated_at = now() "
                        "WHERE id = %s", (split, image_id))
        cur.execute(
            "UPDATE images SET split = 'UNASSIGNED'::dataset_split "
            "WHERE dataset_id = %s AND split = 'UNASSIGNED'::dataset_split",
            (dataset["id"],),
        )

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - DATASET SPLIT")
    print("=" * 68)
    print(f"dataset   : {args.key}")
    print(f"ratios    : train={args.ratios[0]} validation={args.ratios[1]} test={args.ratios[2]}")
    for key, value in sorted(counters.as_dict().items()):
        print(f"  {key:<12}: {value}")
    print(f"  {'blocked':<12}: {blocked} (not usable for training; left UNASSIGNED)")
    print("=" * 68)
    if blocked:
        print("Blocked images were not split. Resolve licensing, labelling and")
        print("verification first, then re-run split.")
    return 0


# ---------------------------------------------------------------------------
# status / dedup
# ---------------------------------------------------------------------------


def cmd_status(args: argparse.Namespace) -> int:
    with transaction() as cur:
        cur.execute(
            """
            SELECT d.name, d.version, d.license, d.license_verified, d.image_count,
                   d.status, s.name AS source_name, s.approval_status
              FROM datasets d LEFT JOIN sources s ON s.id = d.source_id
             ORDER BY d.name, d.version
            """
        )
        datasets = list(cur.fetchall())
        if not datasets:
            print("no datasets registered")
            return 0
        for dataset in datasets:
            print()
            print("=" * 68)
            print(f"dataset {dataset['name']} (version {dataset['version']})")
            print("=" * 68)
            print(f"  licence           : {dataset['license']} "
                  f"(verified={dataset['license_verified']})")
            print(f"  version           : {dataset['version']}")
            print(f"  status            : {dataset['status']}")
            print(f"  source            : {dataset['source_name']} "
                  f"({dataset['approval_status']})")
            cur.execute(
                """
                SELECT split, count(*) AS n,
                       count(*) FILTER (WHERE is_usable_for_training) AS usable,
                       count(*) FILTER (WHERE verified) AS verified,
                       count(*) FILTER (WHERE is_duplicate_of IS NOT NULL) AS duplicates
                  FROM images WHERE dataset_id = (SELECT id FROM datasets WHERE key = %s)
                 GROUP BY split ORDER BY split
                """,
                (dataset["key"],),
            )
            print(f"  {'split':<12} {'images':>8} {'usable':>8} {'verified':>9} {'dupes':>7}")
            for row in cur.fetchall():
                print(f"  {row['split']:<12} {row['n']:>8} {row['usable']:>8} "
                      f"{row['verified']:>9} {row['duplicates']:>7}")
    return 0


def cmd_dedup(args: argparse.Namespace) -> int:
    import deduplicate_images

    argv = ["--dataset", args.key]
    if args.apply:
        argv.append("--apply")
    if args.dry_run:
        argv.append("--dry-run")
    return deduplicate_images.main(argv)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PlantDoctor dataset import pipeline")
    sub = parser.add_subparsers(dest="command", required=True)

    def add(name: str, help_text: str) -> argparse.ArgumentParser:
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--log-level", default="INFO")
        return p

    p = add("register", "record a dataset and its licence")
    p.add_argument("--key", required=True,
                   help="dataset name; stored as datasets.name and paired with --version")
    p.add_argument("--version", required=True,
                   help="dataset version or release identifier; stored with the name")
    p.add_argument("--description", default=None)
    p.add_argument("--local-path", default=None)
    p.add_argument("--remote-url", default=None)
    p.add_argument("--source-key", required=True)
    p.add_argument("--license", required=True)
    p.add_argument("--confirmed-by", default="operator",
                   help="who read the terms and confirmed the licence (recorded for audit)")
    p.add_argument("--attribution-required", action="store_true")
    p.add_argument("--attribution-text", default=None)
    p.add_argument("--redistribution-allowed", action="store_true", default=True)
    p.add_argument("--no-redistribution-allowed", dest="redistribution_allowed",
                   action="store_false")
    p.add_argument("--commercial-use-allowed", action="store_true", default=True)
    p.add_argument("--no-commercial-use-allowed", dest="commercial_use_allowed",
                   action="store_false")
    p.add_argument("--confirm-license", action="store_true",
                   help="assert the licence and terms of use have been read and checked")
    p.set_defaults(func=cmd_register)

    p = add("ingest", "hash and register image files")
    p.add_argument("--key", required=True)
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_ingest)

    p = add("label", "map dataset labels onto knowledge-base records")
    p.add_argument("--key", required=True)
    p.add_argument("--map", required=True, help="CSV with relative_path,label,condition_class,...")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_label)

    p = add("split", "assign train/validation/test deterministically")
    p.add_argument("--key", required=True)
    p.add_argument("--ratios", type=float, nargs=3, default=[0.7, 0.15, 0.15])
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_split)

    p = add("dedup", "detect duplicate images within the dataset")
    p.add_argument("--key", required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_dedup)

    p = add("status", "show dataset status")
    p.set_defaults(func=cmd_status)

    args = parser.parse_args(argv)
    setup_logging(args.log_level)
    return args.func(args)


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
