#!/usr/bin/env python3
"""Aggregate REAL PlantDoctor metrics for the in-app Science Fair dashboard.

Every number printed here is read from an artefact that a build step actually
produced:

  * plant/disease/pest/image/source counts -> the built SQLite database
  * dataset release information           -> knowledge/dist/manifest.json
  * model training figures                -> ml/metrics/training_report.json
  * held-out evaluation figures           -> ml/metrics/evaluation_report.json

If an artefact is missing, the corresponding line prints "Not measured yet."
It never falls back to an estimate, a literature figure, or a remembered value.
That rule is the whole point of this script.

Usage:
    python3 scripts/science_fair_metrics.py
    python3 scripts/science_fair_metrics.py --json
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DB_PATH = REPO_ROOT / "knowledge" / "dist" / "plantdoctor.db"
MANIFEST_PATH = REPO_ROOT / "knowledge" / "dist" / "manifest.json"
TRAINING_PATH = REPO_ROOT / "ml" / "metrics" / "training_report.json"
EVALUATION_PATH = REPO_ROOT / "ml" / "metrics" / "evaluation_report.json"
TFLITE_MANIFEST_PATH = REPO_ROOT / "ml" / "export" / "tflite_export_manifest.json"
SPLIT_REPORT_PATH = REPO_ROOT / "ml" / "data" / "splits" / "split_report.json"

NOT_MEASURED = "Not measured yet."


def load_json(path: Path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None


def database_counts() -> dict:
    if not DB_PATH.exists():
        return {"available": False}
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}

    def count(name: str):
        return int(conn.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0]) \
            if name in tables else None

    result = {
        "available": True,
        "plant_records": count("plants"),
        "plant_names": count("plant_names"),
        "plant_synonyms": count("plant_synonyms"),
        "plant_taxonomy_rows": count("plant_taxonomy"),
        "plant_images": count("plant_images"),
        "diseases": count("diseases"),
        "plant_diseases": count("plant_diseases"),
        "disease_images": count("disease_images"),
        "pests": count("pests"),
        "pest_images": count("pest_images"),
        "nutrient_deficiencies": count("nutrient_deficiencies"),
        "environmental_stresses": count("environmental_stresses"),
        "treatments": count("treatments"),
        "prevention_methods": count("prevention_methods"),
        "toxicity_profiles": count("toxicity_profiles"),
        "human_safety": count("human_safety"),
        "pet_safety": count("pet_safety"),
        "livestock_safety": count("livestock_safety"),
        "sources": count("sources"),
        "source_records": count("source_records"),
        "data_provenance": count("data_provenance"),
        "verification_records": count("verification_records"),
    }
    if "plants" in tables:
        result["distinct_families"] = int(conn.execute(
            "SELECT COUNT(DISTINCT family) FROM plants "
            "WHERE family IS NOT NULL AND trim(family)<>''").fetchone()[0])
        result["distinct_genera"] = int(conn.execute(
            "SELECT COUNT(DISTINCT genus) FROM plants "
            "WHERE genus IS NOT NULL AND trim(genus)<>''").fetchone()[0])
        result["plants_with_common_name"] = int(conn.execute(
            "SELECT COUNT(*) FROM plants "
            "WHERE common_name IS NOT NULL AND trim(common_name)<>''"
        ).fetchone()[0])
        result["plants_verified"] = int(conn.execute(
            "SELECT COUNT(*) FROM plants WHERE "
            "upper(trim(COALESCE(verification_status,'')))='VERIFIED'"
        ).fetchone()[0])
    if "sources" in tables:
        result["source_list"] = [
            {"key": r[0], "name": r[1], "license": r[2], "retrieved_at": r[3]}
            for r in conn.execute(
                "SELECT source_key, name, license, retrieved_at FROM sources "
                "ORDER BY id")]
    conn.close()
    return result


def percent(value) -> str:
    if value is None:
        return NOT_MEASURED
    return f"{100.0 * float(value):.2f}%"


def build() -> dict:
    db = database_counts()
    manifest = load_json(MANIFEST_PATH) or {}
    training = load_json(TRAINING_PATH) or {}
    evaluation = load_json(EVALUATION_PATH) or {}
    tflite = load_json(TFLITE_MANIFEST_PATH) or {}
    split = load_json(SPLIT_REPORT_PATH) or {}

    evaluation_metrics = evaluation.get("metrics") or {}
    evaluated = evaluation.get("status") == "measured"
    trained = bool(training.get("history"))

    model_version = None
    if tflite.get("generated_at"):
        model_version = f"tflite-{tflite['generated_at']}"
    elif training.get("generated_at"):
        model_version = f"keras-{training['generated_at']}"

    sweep = evaluation.get("unknown_rejection_sweep") or []
    rejection_at = None
    for row in sweep:
        if abs(row.get("threshold", 0) - 0.60) < 1e-9:
            rejection_at = row

    return {
        "generated_from": {
            "database": str(DB_PATH) if db.get("available") else None,
            "manifest": str(MANIFEST_PATH) if manifest else None,
            "training_report": str(TRAINING_PATH) if trained else None,
            "evaluation_report": str(EVALUATION_PATH) if evaluated else None,
        },
        "dataset": {
            "data_release": manifest.get("data_release"),
            "schema_version": manifest.get("schema_version"),
            "build_date": manifest.get("build_date"),
            "database_sha256": manifest.get("sha256"),
            "split_unit": split.get("split_unit"),
            "split_seed": split.get("seed"),
            "split_images": (split.get("images") if split else None),
            "classes": (split.get("classes") if split else None),
            "crops": (split.get("crops") if split else None),
        },
        "knowledge_base": db,
        "model": {
            "model_version": model_version,
            "architecture": training.get("architecture"),
            "image_size": training.get("image_size"),
            "num_classes": training.get("num_classes"),
            "device": training.get("device", "cpu"),
            "trained": trained,
            "epochs_completed": (training.get("training") or {}).get(
                "epochs_completed"),
            "train_images_used": (training.get("data") or {}).get(
                "train_images_available"),
            "best_val_accuracy": (training.get("best_epoch") or {}).get(
                "val_accuracy"),
        },
        "evaluation": {
            "measured": evaluated,
            "split": evaluation.get("split"),
            "test_images": evaluation.get("test_images"),
            "top1_accuracy": evaluation_metrics.get("top1_accuracy"),
            "top5_accuracy": evaluation_metrics.get("top5_accuracy"),
            "macro_precision": (evaluation_metrics.get("macro") or {}).get(
                "precision"),
            "macro_recall": (evaluation_metrics.get("macro") or {}).get("recall"),
            "macro_f1": (evaluation_metrics.get("macro") or {}).get("f1"),
            "weighted_f1": (evaluation_metrics.get("weighted") or {}).get("f1"),
            "average_inference_ms": (
                None if evaluation_metrics.get(
                    "average_inference_seconds_per_image") is None
                else 1000.0 * evaluation_metrics[
                    "average_inference_seconds_per_image"]),
            "confusion_matrix_file": evaluation.get("confusion_matrix_file"),
            "unknown_rejection_rate_at_0_60": (
                rejection_at.get("rejection_rate") if rejection_at else None),
            "accuracy_on_accepted_at_0_60": (
                rejection_at.get("accuracy_on_accepted") if rejection_at
                else None),
        },
        "honesty": {
            "rule": "Any field that is null renders as 'Not measured yet.' "
                    "No metric in this file is estimated, extrapolated, or "
                    "copied from an external source.",
        },
    }


def render(report: dict) -> str:
    dataset = report["dataset"]
    db = report["knowledge_base"]
    model = report["model"]
    ev = report["evaluation"]

    lines = [
        "=" * 62,
        "PLANTDOCTOR AI - SCIENCE FAIR METRICS",
        "=" * 62,
        "",
        "DATASET",
        f"  Data release              {dataset['data_release'] or NOT_MEASURED}",
        f"  Schema version            {dataset['schema_version'] or NOT_MEASURED}",
        f"  Build date                {dataset['build_date'] or NOT_MEASURED}",
        f"  Split unit                {dataset['split_unit'] or NOT_MEASURED}",
        f"  Split seed                {dataset['split_seed'] or NOT_MEASURED}",
        f"  Classes                   {dataset['classes'] or NOT_MEASURED}",
        f"  Crops                     {dataset['crops'] or NOT_MEASURED}",
    ]
    if dataset.get("split_images"):
        images = dataset["split_images"]
        lines.append(f"  Train/val/test images     "
                     f"{images.get('train')}/{images.get('val')}/"
                     f"{images.get('test')}")

    lines += ["", "KNOWLEDGE BASE (measured from the built database)"]
    if db.get("available"):
        for label, key in (
            ("Total plant records", "plant_records"),
            ("  with a common name", "plants_with_common_name"),
            ("  marked VERIFIED", "plants_verified"),
            ("Distinct families", "distinct_families"),
            ("Distinct genera", "distinct_genera"),
            ("Common / vernacular names", "plant_names"),
            ("Synonyms", "plant_synonyms"),
            ("Plant images", "plant_images"),
            ("Diseases", "diseases"),
            ("Disease images", "disease_images"),
            ("Pests", "pests"),
            ("Pest images", "pest_images"),
            ("Nutrient deficiencies", "nutrient_deficiencies"),
            ("Environmental stresses", "environmental_stresses"),
            ("Treatments", "treatments"),
            ("Prevention methods", "prevention_methods"),
            ("Toxicity profiles", "toxicity_profiles"),
            ("Human safety records", "human_safety"),
            ("Pet safety records", "pet_safety"),
            ("Livestock safety records", "livestock_safety"),
            ("Registered sources", "sources"),
            ("Source records", "source_records"),
            ("Provenance rows", "data_provenance"),
            ("Verification records", "verification_records"),
        ):
            value = db.get(key)
            lines.append(f"  {label:<30}"
                         f"{NOT_MEASURED if value is None else value}")
        if db.get("source_list"):
            lines.append("  Sources:")
            for row in db["source_list"]:
                lines.append(f"    - {row['name']}  [{row['license']}]")
    else:
        lines.append(f"  database not built - {NOT_MEASURED}")

    lines += ["", "MODEL"]
    lines.append(f"  Model version             {model['model_version'] or NOT_MEASURED}")
    lines.append(f"  Architecture              {model['architecture'] or NOT_MEASURED}")
    lines.append(f"  Classes                   {model['num_classes'] or NOT_MEASURED}")
    lines.append(f"  Input size                {model['image_size'] or NOT_MEASURED}")
    lines.append(f"  Training device           {model['device'] or NOT_MEASURED}")
    lines.append(f"  Train images used         {model['train_images_used'] or NOT_MEASURED}")
    lines.append(f"  Epochs completed          {model['epochs_completed'] or NOT_MEASURED}")
    lines.append(f"  Best validation accuracy  {percent(model['best_val_accuracy'])}")

    lines += ["", "HELD-OUT TEST EVALUATION"]
    if ev.get("measured"):
        lines.append(f"  Split                     {ev.get('split')}")
        lines.append(f"  Test images               {ev['test_images']}")
        lines.append(f"  Top-1 accuracy            {percent(ev['top1_accuracy'])}")
        lines.append(f"  Top-5 accuracy            {percent(ev['top5_accuracy'])}")
        lines.append(f"  Macro precision           {percent(ev['macro_precision'])}")
        lines.append(f"  Macro recall              {percent(ev['macro_recall'])}")
        lines.append(f"  Macro F1                  {percent(ev['macro_f1'])}")
        lines.append(f"  Weighted F1               {percent(ev['weighted_f1'])}")
        latency = ev.get("average_inference_ms")
        lines.append("  Avg inference / image     "
                     f"{NOT_MEASURED if latency is None else f'{latency:.1f} ms (CPU)'}")
        lines.append("  Unknown rejection @0.60   "
                     f"{percent(ev['unknown_rejection_rate_at_0_60'])}")
        lines.append("  Accuracy when accepted    "
                     f"{percent(ev['accuracy_on_accepted_at_0_60'])}")
        lines.append(f"  Confusion matrix          {ev.get('confusion_matrix_file')}")
    else:
        lines.append(f"  {NOT_MEASURED} (run ml/scripts/evaluate_model.py)")

    lines += ["", "-" * 62,
              "This model is a crop-and-condition screener. It is not a",
              "10,000-species identifier and the app never presents it as one.",
              "Figures that have not been measured are shown as "
              f"'{NOT_MEASURED}'", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()
    report = build()
    print(json.dumps(report, indent=2) if args.as_json else render(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
