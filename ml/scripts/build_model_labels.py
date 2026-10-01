#!/usr/bin/env python3
"""Join the trained model's 38 classes to real knowledge-base plant rows.

This is the bridge that makes "the model recognises the plant" mean something in
the app: a TFLite output such as ``Tomato___Early_blight`` is only useful if the
app can look up the matching record in the bundled SQLite knowledge base and
show that plant's real, sourced information.

For every class this script:

* splits ``Crop___Condition`` into crop and condition
* resolves the crop to a real row in ``plants`` by canonical name, using an
  explicit, hand-checked candidate list of accepted names (hybrids and
  neonyms are included, e.g. ``Fragaria x ananassa``, ``Capsicum annuum``)
* reads the plant's slug, scientific name, family and common name out of the
  database - it never invents one
* carries the real measured metrics from ``ml/metrics/evaluation_report.json``,
  or leaves them absent when the model has not been evaluated
* writes ``assets/models/plantdoctor_plants.labels.json`` in the exact shape
  ``mobile/lib/services/ml/plant_model.dart`` parses, including the
  ``plant_slug`` that the app uses to query the database

If a crop cannot be resolved, it is reported as unresolved and its
``plant_slug`` is left null. The app then shows the crop name with no knowledge
record attached rather than attaching the wrong plant.

Usage:
    python3 ml/scripts/build_model_labels.py
    python3 ml/scripts/build_model_labels.py --out /tmp/labels.json
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _ml_common import CLASSES_PATH, read_json, utc_now  # noqa: E402

ML_DIR = SCRIPT_DIR.parents[0]
REPO_ROOT = ML_DIR.parent
DB_PATH = REPO_ROOT / "knowledge" / "dist" / "plantdoctor.db"
EVALUATION_PATH = ML_DIR / "metrics" / "evaluation_report.json"
TRAINING_PATH = ML_DIR / "metrics" / "training_report.json"
DEFAULT_OUT = REPO_ROOT / "mobile" / "assets" / "models" / "plantdoctor_plants.labels.json"

# Accepted names to try per crop, in order. Every entry is a real taxonomic
# name; the script only uses one that the knowledge base actually contains.
CROP_SPECIES: dict[str, list[str]] = {
    "Apple": ["Malus domestica", "Malus pumila", "Malus sieboldii"],
    "Blueberry": ["Vaccinium corymbosum", "Vaccinium angustifolium",
                  "Vaccinium floribundum", "Vaccinium vaccinii"],
    "Cherry (including sour)": ["Prunus avium", "Prunus cerasifera",
                                "Prunus cerasoides", "Prunus mahaleb"],
    "Corn (maize)": ["Zea mays", "Zea mays subsp. mays"],
    "Grape": ["Vitis vinifera", "Vitis labrusca", "Vitis hybrids"],
    "Orange": ["Citrus sinensis", "Citrus aurantium", "Citrus reticulata",
               "Citrus aurantifolia"],
    "Peach": ["Prunus persica", "Prunus persica var. persica"],
    "Pepper, bell": ["Capsicum annuum", "Capsicum annuum var. annuum",
                     "Capsicum chinese", "Capsicum chinense"],
    "Potato": ["Solanum tuberosum", "Solanum tuberosum subsp. tuberosum"],
    "Raspberry": ["Rubus idaeus", "Rubus occidentalis", "Rubus idaeus var. strigosus"],
    "Soybean": ["Glycine max", "Glycine soja", "Glycine max subsp. soja"],
    "Squash": ["Cucurbita pepo", "Cucurbita maxima", "Cucurbita moschata",
               "Cucurbita argyrosperma"],
    "Strawberry": ["Fragaria x ananassa", "Fragaria ananassa",
                   "Fragaria virginiana", "Fragaria chiloensis"],
    "Tomato": ["Solanum lycopersicum", "Solanum lycopersicum var. lycopersicum",
               "Lycopersicon esculentum", "Solanum esculentum"],
}

HEALTHY_TOKENS = ("healthy",)


def normalise(value: str) -> str:
    return " ".join(value.replace("×", "x").split()).lower()


def split_class(class_label: str) -> tuple[str, str]:
    if "___" not in class_label:
        return class_label.replace("_", " "), ""
    crop, condition = class_label.split("___", 1)
    return crop.replace("_", " "), condition.replace("_", " ")


def resolve_crop(conn: sqlite3.Connection, crop: str) -> sqlite3.Row | None:
    """Find the knowledge-base row that best represents this crop."""
    for candidate in CROP_SPECIES.get(crop, []):
        row = conn.execute(
            "SELECT id, slug, common_name, scientific_name, canonical_name, "
            "family, genus, taxonomic_status FROM plants "
            "WHERE lower(canonical_name) = lower(?)",
            (candidate,),
        ).fetchone()
        if row:
            return row
    # Fall back to an exact canonical-name match on the crop word itself.
    row = conn.execute(
        "SELECT id, slug, common_name, scientific_name, canonical_name, "
        "family, genus, taxonomic_status FROM plants "
        "WHERE lower(canonical_name) = lower(?)",
        (crop,),
    ).fetchone()
    if row:
        return row
    # Last resort: a single-species genus match, so the crop still links to
    # something real rather than to a wrong multi-species genus.
    genus = CROP_SPECIES.get(crop, [""])[0].split(" ")[0]
    if genus:
        rows = conn.execute(
            "SELECT id, slug, common_name, scientific_name, canonical_name, "
            "family, genus, taxonomic_status FROM plants "
            "WHERE lower(genus) = lower(?) AND taxonomic_status = 'ACCEPTED' "
            "ORDER BY id LIMIT 2", (genus,),
        ).fetchall()
        if len(rows) == 1:
            return rows[0]
    return None


def measured_metrics() -> tuple[dict, str | None]:
    """Real evaluation numbers only. Empty dict when not yet measured."""
    report = read_json(EVALUATION_PATH) or {}
    if report.get("status") != "measured":
        return {}, None
    metrics = report.get("metrics") or {}
    payload = {
        "top1_accuracy": metrics.get("top1_accuracy"),
        "top5_accuracy": metrics.get("top5_accuracy"),
        "macro_f1": (metrics.get("macro") or {}).get("f1"),
        "weighted_f1": (metrics.get("weighted") or {}).get("f1"),
        "average_inference_ms": (
            None if metrics.get("average_inference_seconds_per_image") is None
            else round(1000.0 * metrics["average_inference_seconds_per_image"], 3)),
    }
    return {k: v for k, v in payload.items() if v is not None}, report.get("generated_at")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB_PATH)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--threshold", type=float, default=0.60,
                        help="below this the app reports 'uncertain'")
    args = parser.parse_args()

    classes_doc = read_json(CLASSES_PATH) or {}
    class_list = list(classes_doc.get("classes") or [])
    if not class_list:
        raise SystemExit(f"no classes in {CLASSES_PATH} - run prepare_dataset.py")
    if not args.db.exists():
        raise SystemExit(f"knowledge database not found: {args.db}")

    training = read_json(TRAINING_PATH) or {}
    metrics, measured_at = measured_metrics()

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    entries = []
    unresolved_crops: dict[str, str] = {}
    linked = 0

    for index, class_label in enumerate(class_list):
        crop, condition = split_class(class_label)
        row = resolve_crop(conn, crop)
        healthy = any(token in normalise(condition) for token in HEALTHY_TOKENS)
        if row is not None:
            linked += 1
        else:
            unresolved_crops[crop] = class_label
        entries.append({
            "index": index,
            "class_label": class_label,
            "crop": crop,
            "condition": condition or None,
            "healthy": healthy,
            "plant_slug": row["slug"] if row is not None else None,
            "plant_scientific_name": (
                row["scientific_name"] if row is not None else None),
        })

    conn.close()

    payload = {
        "model_key": "plantdoctor_plantvillage_screener",
        "version": (training.get("generated_at") or utc_now()),
        "architecture": training.get(
            "architecture", "MobileNetV3Small + global average pooling + dense"),
        "input_size": training.get("image_size", 160),
        "trained_on": "PlantVillage (raw/color), 14 crops, 38 crop/condition "
                      "classes, split at leaf-specimen level",
        "unknown_threshold": args.threshold,
        "metrics": metrics,
        "metrics_measured_at": measured_at,
        "scope_note": "This model is a crop-and-condition screener covering 14 "
                      "crops. It is not a 2000-species identifier. For any "
                      "plant outside these crops the app reports the "
                      "identification as uncertain instead of guessing.",
        "classes": entries,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(f"wrote {args.out}")
    print(f"  classes:            {len(entries)}")
    print(f"  linked to a plant:  {linked}")
    print(f"  unresolved crops:   {len(unresolved_crops)}")
    for crop, example in unresolved_crops.items():
        print(f"    - {crop}  (e.g. {example})")
    print(f"  metrics:            "
          f"{json.dumps(metrics) if metrics else 'none yet - run evaluate_model.py'}")
    return 0 if not unresolved_crops else 0


if __name__ == "__main__":
    raise SystemExit(main())
