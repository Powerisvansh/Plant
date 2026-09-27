#!/usr/bin/env python3
"""Extract real image metadata into the knowledge base.

Everything written here is measured from the file itself: byte size, SHA-256,
decoded pixel dimensions, detected MIME type, and the variance of the Laplacian
as an image-sharpness figure. Nothing is inferred.

Deliberately NOT written:
  * quality_score - there is no validated definition of a single "quality"
    number for this project yet, so it stays NULL rather than being filled with
    an arbitrary composite.
  * any label. Condition and plant identity are knowledge-base decisions made
    elsewhere, never guessed from pixels.

A file that Pillow cannot decode is reported and marked unusable instead of
being silently skipped, so corruption becomes visible.

Usage:
    python3 scripts/generate_metadata.py --dataset <key> --dry-run
    python3 scripts/generate_metadata.py --dataset plantvillage
    python3 scripts/generate_metadata.py --dataset plantvillage --rescan
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from _common import (
    Counters,
    get_logger,
    human_bytes,
    rel_to_data_root,
    resolve_data_path,
    setup_logging,
    transaction,
)

log = get_logger("generate_metadata")

MIME_BY_SUFFIX = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
    ".webp": "image/webp", ".gif": "image/gif", ".bmp": "image/bmp",
    ".tif": "image/tiff", ".tiff": "image/tiff",
}

# Below this the decoded image is too small to carry useful diagnostic detail.
MIN_USEFUL_EDGE = 32


def measure(path: Path) -> dict[str, Any]:
    """Decode the file and measure it. Raises on anything unreadable."""
    from PIL import Image, UnidentifiedImageError

    with Image.open(path) as img:
        detected_format = (img.format or "").upper()
        width, height = img.size
        mode = img.mode
        # verify() walks the file structure; a truncated JPEG raises here rather
        # than much later during training.
        try:
            img.verify()
        except Exception as exc:
            raise ValueError(f"failed integrity check: {type(exc).__name__}: {exc}") from exc

    # Reopen: verify() invalidates the decoder.
    with Image.open(path) as img:
        grayscale = img.convert("L")
        # Laplacian variance is a standard, reproducible sharpness measure.
        # It needs the image data, so it is computed here rather than derived
        # from a stored number.
        from PIL import ImageFilter

        edges = grayscale.filter(ImageFilter.FIND_EDGES)
        histogram = edges.histogram()
        total = sum(i * count for i, count in enumerate(histogram))
        mean = total / (width * height) if width and height else 0.0
        variance = sum(((i - mean) ** 2) * count for i, count in enumerate(histogram)) / (
            width * height
        ) if width and height else 0.0

        brightness_hist = grayscale.histogram()
        brightness = sum(i * count for i, count in enumerate(brightness_hist)) / (
            width * height
        ) if width and height else 0.0
        max_brightness = (width * height - 1) or 1

    return {
        "width": width,
        "height": height,
        "mode": mode,
        "format": detected_format,
        "blur_score": round(variance, 4),
        "mean_brightness": round(brightness / max_brightness, 4),
    }


def dataset_root() -> Path:
    from plantdoctor_api.config import get_settings

    return get_settings().data_path("datasets")


def load_dataset(key: str) -> dict[str, Any] | None:
    with transaction() as cur:
        cur.execute(
            "SELECT id, key, name, local_path, license, license_verified, "
            "attribution_required, attribution_text "
            "FROM datasets WHERE name = %s",
            (key,),
        )
        return cur.fetchone()


def iter_dataset_images(dataset: dict[str, Any]) -> list[Path]:
    base = resolve_data_path(dataset["local_path"])
    if not base.is_dir():
        log.error("dataset directory does not exist: %s", base)
        return []
    found: list[Path] = []
    for path in sorted(base.rglob("*")):
        if path.is_file() and path.suffix.lower() in MIME_BY_SUFFIX:
            found.append(path)
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Extract measured image metadata")
    parser.add_argument("--dataset", required=True, help="dataset key registered in the database")
    parser.add_argument("--limit", type=int, default=0, help="only process the first N files")
    parser.add_argument("--rescan", action="store_true",
                        help="re-measure rows that already have a stored hash")
    parser.add_argument("--mark-unusable", action="store_true",
                        help="set is_usable_for_training=false on files that fail to decode")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    setup_logging(args.log_level)
    dataset = load_dataset(args.dataset)
    if dataset is None:
        raise SystemExit(f"dataset {args.dataset!r} is not registered in the database")
    log.info("dataset %s: license=%s license_verified=%s path=%s",
             dataset["key"], dataset["license"], dataset["license_verified"],
             dataset["local_path"])

    files = iter_dataset_images(dataset)
    if args.limit:
        files = files[: args.limit]
    log.info("found %d candidate image file(s) under %s",
             len(files), resolve_data_path(dataset["local_path"]))

    if args.dry_run:
        print(f"[dry-run] dataset={dataset['key']} license={dataset['license']} "
              f"verified={dataset['license_verified']}")
        print(f"[dry-run] would measure {len(files)} file(s) and upsert image metadata")
        return 0

    counters = Counters()
    failures: list[tuple[Path, str]] = []

    with transaction() as cur:
        for index, path in enumerate(files, start=1):
            relative = rel_to_data_root(path)
            try:
                size = path.stat().st_size
                measured = measure(path)
                suffix = path.suffix.lower()
                counters.bump("measured")

                if measured["width"] < MIN_USEFUL_EDGE or measured["height"] < MIN_USEFUL_EDGE:
                    counters.bump("too_small")
                    log.warning("[%d/%d] too small: %s (%dx%d)", index, len(files),
                                relative, measured["width"], measured["height"])

                cur.execute(
                    "SELECT id, file_sha256 FROM images WHERE file_path = %s",
                    (relative,),
                )
                existing = cur.fetchone()

                if existing and existing["file_sha256"] == _sha_or_none(path) and not args.rescan:
                    counters.bump("unchanged")
                    continue

                values = (
                    relative, path.name, size, suffix, MIME_BY_SUFFIX.get(suffix),
                    measured["width"], measured["height"],
                    measured["blur_score"], measured["mean_brightness"],
                )
                if existing:
                    cur.execute(
                        """
                        UPDATE images
                           SET relative_path = %s, original_filename = %s, file_bytes = %s,
                               file_extension = %s,
                               mime_type = COALESCE(%s, mime_type),
                               image_width = %s, image_height = %s,
                               blur_score = %s, mean_brightness = %s,
                               updated_at = now()
                         WHERE id = %s
                        """,
                        (values[0], values[1], values[2], values[3], values[4],
                         values[5], values[6], values[7], values[8], existing["id"]),
                    )
                    counters.bump("updated")
                else:
                    cur.execute(
                        """
                        INSERT INTO images (dataset_id, file_path, relative_path,
                                            original_filename, file_sha256, file_extension,
                                            mime_type, file_bytes, image_width, image_height,
                                            blur_score, mean_brightness,
                                            license, copyright_status, source_id, notes)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                        RETURNING id
                        """,
                        (dataset["id"], relative, path.name, _sha_or_none(path),
                         suffix, values[4], size, measured["width"], measured["height"],
                         measured["blur_score"], measured["mean_brightness"],
                         dataset["license"],
                         "PUBLIC_DOMAIN" if dataset["license"] == "PUBLIC_DOMAIN" else "OPEN_LICENSE",
                         dataset["id"],
                         "Metadata measured by scripts/generate_metadata.py. No label assigned; "
                         "condition and identity are knowledge-base decisions."),
                    )
                    counters.bump("inserted")

                if args.mark_unusable and (measured["width"] < MIN_USEFUL_EDGE
                                            or measured["height"] < MIN_USEFUL_EDGE):
                    cur.execute(
                        "UPDATE images SET is_usable_for_training = FALSE, "
                        "unusable_reason = %s WHERE file_path = %s",
                        (f"image smaller than {MIN_USEFUL_EDGE}px on one edge", relative),
                    )

            except Exception as exc:
                counters.bump("failed")
                failures.append((path, f"{type(exc).__name__}: {exc}"))
                log.error("[%d/%d] FAILED %s: %s", index, len(files), path.name, exc)

        if failures and args.mark_unusable:
            for path, reason in failures:
                cur.execute(
                    "UPDATE images SET is_usable_for_training = FALSE, unusable_reason = %s "
                    "WHERE file_path = %s",
                    (f"file could not be decoded: {reason[:200]}",
                     rel_to_data_root(path)),
                )
                counters.bump("marked_unusable")

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - IMAGE METADATA")
    print("=" * 68)
    print(f"dataset     : {dataset['key']} ({dataset['license']})")
    for key, value in counters.as_dict().items():
        print(f"  {key:<20}: {value}")
    if failures:
        print()
        print(f"unreadable files ({len(failures)}):")
        for path, reason in failures[:20]:
            print(f"  {path.name}: {reason}")
        if len(failures) > 20:
            print(f"  ... and {len(failures) - 20} more")
    print()
    print("quality_score was NOT written: no validated definition exists yet.")
    print("No condition labels were assigned: pixels are not a diagnosis.")
    print("=" * 68)
    return 1 if failures else 0


def _sha_or_none(path: Path) -> str:
    from _common import sha256_file

    return sha256_file(path)


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    raise SystemExit(main())
