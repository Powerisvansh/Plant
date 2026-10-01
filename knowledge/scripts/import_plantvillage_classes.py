#!/usr/bin/env python3
"""Derive the PlantVillage class list and per-class image counts.

The dataset ships as a single archive (``ml/data/data.zip``) whose entries look
like ``raw/color/<Crop>___<Condition>/<file>.JPG``. This script reads the archive
index - it does not extract images - and writes the *measured* class inventory to
``knowledge/data/raw/plantvillage_class_counts.json``.

Those counts are what the app and the evaluation report actually use. No count in
this project is ever estimated or hand-written.

Usage
-----
    python3 knowledge/scripts/import_plantvillage_classes.py
    python3 knowledge/scripts/import_plantvillage_classes.py --archive /path/data.zip
"""

from __future__ import annotations

import argparse
import collections
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import (  # noqa: E402
    RAW_DIR,
    REPO_ROOT,
    setup_logging,
    utc_now,
    write_json,
)

log = setup_logging("import_plantvillage_classes")

DEFAULT_ARCHIVE = REPO_ROOT / "ml" / "data" / "data.zip"
OUT_PATH = RAW_DIR / "plantvillage_class_counts.json"

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}


def scan(archive: Path, subset: str = "color") -> dict:
    if not archive.exists():
        raise SystemExit(
            f"PlantVillage archive not found: {archive}\n"
            "Download it first (see docs/image-dataset.md)."
        )

    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()

    counts: collections.Counter = collections.Counter()
    subsets_seen: set[str] = set()
    for name in names:
        parts = name.split("/")
        # Expect raw/<subset>/<Crop>___<Condition>/<file>
        if len(parts) < 4 or parts[0] != "raw":
            continue
        subsets_seen.add(parts[1])
        if parts[1] != subset:
            continue
        if "___" not in parts[2]:
            continue
        if Path(parts[-1]).suffix.lower() not in IMAGE_SUFFIXES:
            continue
        counts[parts[2]] += 1

    if not counts:
        raise SystemExit(
            f"No images found under raw/{subset}/ in {archive}. "
            f"Subsets present: {sorted(subsets_seen)}"
        )

    crops: collections.Counter = collections.Counter()
    for class_name in counts:
        crops[class_name.split("___")[0]] += 1

    classes = [
        {
            "class_name": class_name,
            "crop": class_name.split("___")[0],
            "condition": class_name.split("___", 1)[1],
            "is_healthy": class_name.split("___", 1)[1].strip().lower() == "healthy",
            "image_count": counts[class_name],
        }
        for class_name in sorted(counts)
    ]

    return {
        "_meta": {
            "file": OUT_PATH.name,
            "purpose": (
                "Measured class inventory of the PlantVillage archive. The "
                "image counts are counted from the archive index at import time."
            ),
            "dataset": "PlantVillage Dataset (raw/color)",
            "dataset_url": "https://github.com/spMohanty/PlantVillage-Dataset",
            "dataset_license": "CC BY-SA 3.0",
            "archive": str(archive),
            "subset": f"raw/{subset}",
            "subsets_available": sorted(subsets_seen),
            "derived_at": utc_now(),
            "note": (
                "PlantVillage covers 14 crop species with foliar conditions "
                "only. It is one component of the health-screening model and "
                "does not represent the species knowledge base."
            ),
        },
        "totals": {
            "classes": len(classes),
            "crops": len(crops),
            "images": sum(counts.values()),
        },
        "crops": [
            {"crop": crop, "classes": crops[crop],
             "images": sum(counts[c] for c in counts if c.split("___")[0] == crop)}
            for crop in sorted(crops)
        ],
        "classes": classes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--subset", default="color",
                        help="raw/<subset> folder inside the archive (color)")
    args = parser.parse_args()

    payload = scan(args.archive, args.subset)
    write_json(OUT_PATH, payload)

    _meta = payload["_meta"]

    totals = payload["totals"]
    log.info("subset=%s classes=%s crops=%s images=%s",
             _meta["subset"], totals["classes"], totals["crops"],
             totals["images"])
    for row in payload["crops"]:
        log.info("  %-22s classes=%-3s images=%s",
                 row["crop"], row["classes"], row["images"])
    print(f"\nwrote {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
