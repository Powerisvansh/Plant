#!/usr/bin/env python3
"""Split the PlantVillage dataset into train / validation / test sets.

Splitting methodology (this matters, so it is stated explicitly)
---------------------------------------------------------------
PlantVillage file names look like::

    <specimen-uuid>___<annotator code> <frame number>.JPG

The UUID before ``___`` identifies the *leaf specimen* that was photographed,
and the same specimen appears in several frames. Splitting randomly per image
would put different photographs of the same leaf in both train and test, which
inflates accuracy. This script therefore splits by **specimen group**: every
image of a given UUID goes entirely into one split.

* 70% of specimens -> train
* 15% of specimens -> validation  (model selection / early stopping)
* 15% of specimens -> test        (reported metrics only, never trained on)

Groups are assigned with a fixed seed so the split is reproducible, and a
specimen may never appear in two splits (asserted before writing).

Outputs
-------
* ``ml/data/splits/{train,val,test}.csv``  - path,class,crop,condition,group
* ``ml/data/splits/split_report.json``     - counts, class balance, checks
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _ml_common import (  # noqa: E402
    CLASSES_PATH,
    DATASET_ROOT,
    SPLIT_DIR,
    log,
    write_json,
)

SEED = 20260927
TRAIN_FRACTION = 0.70
VAL_FRACTION = 0.15
# The remaining fraction goes to test.

UUID_RE = re.compile(r"^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                     r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12})")


def parse_name(path: Path) -> tuple[str, str, str, str] | None:
    """Return (class_label, crop, condition, specimen_group) or None."""
    stem = path.name
    label = path.parent.name
    if "___" not in label:
        return None
    crop, _, condition = label.partition("___")
    match = UUID_RE.match(stem)
    if match:
        group = f"{label}:{match.group(1)}"
    else:
        group = f"{label}:{stem}"
    return label, crop, condition, group


def collect(root: Path) -> list[dict]:
    rows: list[dict] = []
    for pattern in ("*/*.JPG", "*/*.jpg"):
        for path in sorted(root.glob(pattern)):
            parsed = parse_name(path)
            if parsed is None:
                continue
            label, crop, condition, group = parsed
            rows.append({
                "abs_path": str(path),
                "class_label": label,
                "crop": crop,
                "condition": condition,
                "group": group,
            })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path,
                        default=DATASET_ROOT / "raw" / "color",
                        help="directory containing the class subfolders")
    args = parser.parse_args()

    root: Path = args.root
    if not root.exists():
        log.error("dataset root not found: %s", root)
        log.error("extract ml/data/data.zip first (raw/color) or pass --root")
        return 1

    rows = collect(root)
    if not rows:
        log.error("no images found under %s", root)
        return 1
    log.info("found %d images in %d classes", len(rows),
             len({r["class_label"] for r in rows}))

    # Split specimens, per class, so every class appears in all three splits
    # with roughly the intended proportions.
    by_class_groups: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        by_class_groups[row["class_label"]].append(row["group"])

    rng = random.Random(SEED)
    assignment: dict[str, str] = {}
    for label, groups in by_class_groups.items():
        unique = sorted(set(groups))
        rng.shuffle(unique)
        if len(unique) >= 8:
            n_train = int(round(len(unique) * TRAIN_FRACTION))
            n_val = int(round(len(unique) * VAL_FRACTION))
            n_train = min(n_train, len(unique) - 2)
            n_val = min(n_val, len(unique) - n_train - 1)
        else:
            # Very small classes still need one specimen in each split.
            n_train = max(1, len(unique) - 2)
            n_val = 1 if len(unique) >= 2 else 0
        for index, group in enumerate(unique):
            if index < n_train:
                assignment[group] = "train"
            elif index < n_train + n_val:
                assignment[group] = "val"
            else:
                assignment[group] = "test"

    splits: dict[str, list[dict]] = {"train": [], "val": [], "test": []}
    for row in rows:
        splits[assignment[row["group"]]].append(row)

    # Hard check: no specimen group may appear in more than one split.
    group_sets = {name: {r["group"] for r in items}
                  for name, items in splits.items()}
    overlap = ((group_sets["train"] & group_sets["val"])
               | (group_sets["train"] & group_sets["test"])
               | (group_sets["val"] & group_sets["test"]))
    if overlap:
        log.error("LEAKAGE: %d specimen groups appear in multiple splits",
                  len(overlap))
        return 1

    SPLIT_DIR.mkdir(parents=True, exist_ok=True)
    for name, items in splits.items():
        with (SPLIT_DIR / f"{name}.csv").open("w", newline="",
                                              encoding="utf-8") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=["abs_path", "class_label", "crop",
                                    "condition", "group"])
            writer.writeheader()
            for item in sorted(items, key=lambda r: r["abs_path"]):
                writer.writerow(item)
        log.info("%-5s %6d images  %5d specimens", name, len(items),
                 len(group_sets[name]))

    classes = sorted({r["class_label"] for r in rows})
    crops = sorted({r["crop"] for r in rows})
    CLASSES_PATH.parent.mkdir(parents=True, exist_ok=True)
    write_json(CLASSES_PATH, {
        "dataset": "PlantVillage",
        "archive": "ml/data/data.zip",
        "subset": "raw/color",
        "classes": classes,
        "crops": crops,
        "image_counts": dict(sorted(Counter(
            r["class_label"] for r in rows).items())),
        "note": (
            "PlantVillage covers these crops and foliar conditions only. It is "
            "not a species-level dataset for the wider plant knowledge base."
        ),
    })

    report = {
        "seed": SEED,
        "split_unit": "leaf specimen (filename UUID)",
        "fractions": {"train": TRAIN_FRACTION, "val": VAL_FRACTION,
                      "test": round(1 - TRAIN_FRACTION - VAL_FRACTION, 2)},
        "images": {name: len(items) for name, items in splits.items()},
        "specimens": {name: len(groups) for name, groups in group_sets.items()},
        "classes": len(classes),
        "crops": len(crops),
        "leakage_check": "PASS (no specimen group in more than one split)",
        "per_class_images": {
            name: dict(sorted(Counter(
                r["class_label"] for r in items).items()))
            for name, items in splits.items()
        },
    }
    write_json(SPLIT_DIR / "split_report.json", report)
    print(json.dumps({k: report[k] for k in
                      ("images", "specimens", "classes", "crops",
                       "leakage_check")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
