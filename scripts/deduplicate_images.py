#!/usr/bin/env python3
"""Find and mark duplicate images in the knowledge base.

Two kinds of duplicate are detected:

  exact      identical file bytes (same SHA-256). Safe to collapse: the extra
             rows are marked is_duplicate_of and excluded from training.
  resized    same pixel content at a different size or format. Detected with a
             perceptual hash so a re-encoded or rescaled copy is still caught.

Nothing is ever deleted. Marking, not deleting, keeps the provenance trail and
means a wrong decision is always reversible by clearing is_duplicate_of.

Usage:
    python3 scripts/deduplicate_images.py --dry-run
    python3 scripts/deduplicate_images.py
    python3 scripts/deduplicate_images.py --kind resized
    python3 scripts/deduplicate_images.py --dataset plantvillage --apply
"""

from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

from _common import (
    Counters,
    get_logger,
    rel_to_data_root,
    resolve_data_path,
    setup_logging,
    transaction,
)

log = get_logger("deduplicate_images")

# Perceptual-hash Hamming distance at or below which two images are treated as
# the same picture. 0 means byte-identical content; small non-zero values catch
# re-encoding and mild rescaling.
NEAR_DUPLICATE_DISTANCE = 4


def dhash(path: Path, hash_size: int = 8) -> int | None:
    """Difference hash: robust to rescaling and re-compression."""
    try:
        from PIL import Image

        with Image.open(path) as img:
            grayscale = img.convert("L").resize((hash_size + 1, hash_size), Image.LANCZOS)
            pixels = list(grayscale.getdata())
    except Exception as exc:
        log.debug("dhash failed for %s: %s", path, exc)
        return None

    bits = 0
    for row in range(hash_size):
        offset = row * (hash_size + 1)
        for col in range(hash_size):
            left = pixels[offset + col]
            right = pixels[offset + col + 1]
            bits = (bits << 1) | (1 if left > right else 0)
    return bits


def hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Detect and mark duplicate images")
    parser.add_argument("--dataset", default=None, help="limit to one dataset key")
    parser.add_argument("--kind", choices=["exact", "resized", "all"], default="all",
                        help="which duplicate classes to detect")
    parser.add_argument("--apply", action="store_true",
                        help="write is_duplicate_of; without this the script only reports")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0, help="only examine the first N rows")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    setup_logging(args.log_level)

    with transaction() as cur:
        sql = (
            "SELECT i.id, i.file_path, i.file_sha256, i.phash, i.dataset_id, i.split, "
            "       i.is_duplicate_of, i.is_usable_for_training, d.name AS dataset_name "
            "  FROM images i LEFT JOIN datasets d ON d.id = i.dataset_id "
        )
        params: list[Any] = []
        if args.dataset:
            sql += "WHERE d.name = %s "
            params.append(args.dataset)
        sql += "ORDER BY i.id"
        if args.limit:
            sql += f" LIMIT {int(args.limit)}"
        cur.execute(sql, tuple(params))
        rows = list(cur.fetchall())

    log.info("examining %d image row(s)", len(rows))

    counters = Counters()
    exact_groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        if row["file_sha256"]:
            exact_groups[row["file_sha256"]].append(row)

    duplicates: list[tuple[dict[str, Any], dict[str, Any], str]] = []

    if args.kind in ("exact", "all"):
        for sha, group in exact_groups.items():
            if len(group) < 2:
                continue
            # The earliest row is kept as canonical so the choice is stable and
            # reproducible rather than dependent on scan order.
            group.sort(key=lambda r: r["id"])
            keeper = group[0]
            for other in group[1:]:
                duplicates.append((other, keeper, f"identical sha256 {sha[:16]}..."))
                counters.bump("exact")

    if args.kind in ("resized", "all"):
        # Build perceptual hashes for rows that do not already have one, and for
        # any row whose file is still present on disk.
        hashes: list[tuple[dict[str, Any], int]] = []
        for row in rows:
            if any(other is row for other, _, _ in duplicates):
                continue
            stored = row["phash"]
            value: int | None = None
            if stored:
                try:
                    value = int(str(stored), 16)
                except ValueError:
                    value = None
            if value is None:
                path = resolve_data_path(row["file_path"])
                if path.is_file():
                    value = dhash(path)
                    if value is not None and args.apply:
                        with transaction() as cur:
                            cur.execute(
                                "UPDATE images SET phash = %s WHERE id = %s",
                                (format(value, "x"), row["id"]),
                            )
                        counters.bump("phash_computed")
            if value is not None:
                hashes.append((row, value))
                if stored is None and value is not None and not args.apply:
                    pass

        log.info("comparing %d perceptual hash(es) pairwise", len(hashes))
        already = {other["id"] for other, _, _ in duplicates}
        for i in range(len(hashes)):
            row_a, hash_a = hashes[i]
            for j in range(i + 1, len(hashes)):
                row_b, hash_b = hashes[j]
                if row_b["id"] in already or row_a["id"] in already:
                    continue
                if hamming(hash_a, hash_b) <= NEAR_DUPLICATE_DISTANCE:
                    duplicates.append((row_b, row_a, "perceptual hash within distance "
                                                      f"{NEAR_DUPLICATE_DISTANCE}"))
                    already.add(row_b["id"])
                    counters.bump("resized")

    if args.apply:
        with transaction() as cur:
            for duplicate, keeper, reason in duplicates:
                cur.execute(
                    """
                    UPDATE images
                       SET is_duplicate_of = %s,
                           is_usable_for_training = FALSE,
                           unusable_reason = %s,
                           updated_at = now()
                     WHERE id = %s
                    """,
                    (keeper["id"], f"duplicate of image {keeper['id']}: {reason}", duplicate["id"]),
                )
        log.info("marked %d duplicate(s)", len(duplicates))

    if args.dry_run:
        print(f"[dry-run] would mark {len(duplicates)} duplicate(s) as is_duplicate_of "
              "and exclude them from training. Nothing is deleted.")

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - IMAGE DEDUPLICATION")
    print("=" * 68)
    print(f"images examined : {len(rows)}")
    for key, value in counters.as_dict().items():
        print(f"  {key:<20}: {value}")
    print(f"duplicates found: {len(duplicates)}")
    print(f"applied         : {args.apply and not args.dry_run}")
    if duplicates:
        print()
        print("examples:")
        for duplicate, keeper, reason in duplicates[:15]:
            print(f"  image {duplicate['id']} ({duplicate['file_path']})")
            print(f"      -> duplicate of image {keeper['id']}: {reason}")
        if len(duplicates) > 15:
            print(f"  ... and {len(duplicates) - 15} more")
    print()
    print("No file or row was deleted. Clear is_duplicate_of to undo.")
    print("=" * 68)
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
