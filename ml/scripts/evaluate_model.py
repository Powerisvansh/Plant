#!/usr/bin/env python3
"""Evaluate the PlantDoctor screening model on the held-out test split.

This script is the only place allowed to write evaluation numbers. Every figure
it prints is computed from a forward pass over ``ml/data/splits/test.csv``,
which ``prepare_dataset.py`` built by splitting at *specimen* level so no
specimen appears in more than one split. Nothing here is estimated, copied from
a paper, or carried over from a previous run.

It reports:
  * top-1 and top-5 accuracy
  * per-class precision / recall / F1, plus macro and weighted averages
  * the full 38x38 confusion matrix
  * average single-image inference latency
  * an unknown-rejection sweep: at a given confidence threshold, how many
    predictions the app would refuse to show, and how accurate the remainder is

If no trained model exists, the script says so and writes a report whose
metrics are ``null`` - the app then displays "Not measured yet" instead of a
number.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _ml_common import (  # noqa: E402
    BEST_MODEL_PATH,
    CLASSES_PATH,
    METRICS_DIR,
    MODEL_PATH,
    SPLIT_DIR,
    log,
    read_json,
    utc_now,
    write_json,
)

IMAGE_SIZE = 160
THRESHOLD_SWEEP = (0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90)


def load_split(name: str) -> tuple[list[str], list[int], list[str]]:
    """Read a split CSV, returning (paths, integer labels, class labels)."""
    classes = read_json(CLASSES_PATH)
    if not classes:
        raise SystemExit("ml/data/classes.json missing - run prepare_dataset.py")
    class_list = classes["classes"]
    index = {label: i for i, label in enumerate(class_list)}

    paths: list[str] = []
    labels: list[int] = []
    with (SPLIT_DIR / f"{name}.csv").open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            paths.append(row["abs_path"])
            labels.append(index[row["class_label"]])
    return paths, labels, class_list


def crop_condition(class_label: str) -> tuple[str, str]:
    """Split ``Apple___Apple_scab`` into ("Apple", "Apple scab")."""
    if "___" not in class_label:
        return class_label, ""
    crop, condition = class_label.split("___", 1)
    return crop.replace("_", " "), condition.replace("_", " ")


def predict_all(tf, model, paths: list[str], batch_size: int):
    import numpy as np

    probabilities = np.zeros((len(paths), model.output_shape[-1]),
                             dtype="float32")
    latencies: list[float] = []

    for start in range(0, len(paths), batch_size):
        chunk = paths[start:start + batch_size]
        batch = np.zeros((len(chunk), IMAGE_SIZE, IMAGE_SIZE, 3),
                         dtype="float32")
        for offset, path in enumerate(chunk):
            raw = tf.io.read_file(path).numpy()
            image = tf.io.decode_image(raw, channels=3, expand_animations=False)
            image = tf.image.resize(image, (IMAGE_SIZE, IMAGE_SIZE),
                                    antialias=True)
            batch[offset] = tf.cast(image, tf.float32).numpy()

        began = time.perf_counter()
        output = model.predict(batch, batch_size=len(chunk), verbose=0)
        latencies.append((time.perf_counter() - began) / len(chunk))
        probabilities[start:start + len(chunk)] = output

    return probabilities, latencies


def classification_metrics(np, y_true: np.ndarray, y_pred: np.ndarray,
                            num_classes: int) -> dict:
    """Per-class precision/recall/F1 plus macro and weighted averages."""
    per_class = []
    for index in range(num_classes):
        true_positive = int(np.sum((y_pred == index) & (y_true == index)))
        false_positive = int(np.sum((y_pred == index) & (y_true != index)))
        false_negative = int(np.sum((y_pred != index) & (y_true == index)))
        support = true_positive + false_negative

        precision = (true_positive / (true_positive + false_positive)
                     if true_positive + false_positive else 0.0)
        recall = (true_positive / support if support else 0.0)
        f1 = (2 * precision * recall / (precision + recall)
              if precision + recall else 0.0)
        per_class.append({
            "class_index": index,
            "precision": round(precision, 6),
            "recall": round(recall, 6),
            "f1": round(f1, 6),
            "support": support,
        })

    total_support = sum(row["support"] for row in per_class) or 1
    macro = {
        "precision": round(sum(r["precision"] for r in per_class) / num_classes, 6),
        "recall": round(sum(r["recall"] for r in per_class) / num_classes, 6),
        "f1": round(sum(r["f1"] for r in per_class) / num_classes, 6),
    }
    weighted = {
        "precision": round(sum(r["precision"] * r["support"] for r in per_class)
                           / total_support, 6),
        "recall": round(sum(r["recall"] * r["support"] for r in per_class)
                        / total_support, 6),
        "f1": round(sum(r["f1"] * r["support"] for r in per_class)
                    / total_support, 6),
    }
    return {"per_class": per_class, "macro": macro, "weighted": weighted}


def confusion_matrix(np, y_true: np.ndarray, y_pred: np.ndarray,
                     num_classes: int) -> np.ndarray:
    matrix = np.zeros((num_classes, num_classes), dtype="int64")
    for actual, predicted in zip(y_true, y_pred):
        matrix[actual][predicted] += 1
    return matrix


def threshold_sweep(np, probabilities: np.ndarray, y_true: np.ndarray) -> list:
    """Coverage/accuracy trade-off for the app's 'uncertain' band."""
    top_probabilities = probabilities.max(axis=1)
    predicted = probabilities.argmax(axis=1)
    correct = predicted == y_true
    rows = []
    for threshold in THRESHOLD_SWEEP:
        accepted = top_probabilities >= threshold
        accepted_count = int(accepted.sum())
        rows.append({
            "threshold": threshold,
            "accepted": accepted_count,
            "rejected_as_unknown": int((~accepted).sum()),
            "rejection_rate": round(float((~accepted).mean()), 6),
            "accuracy_on_accepted": (round(float(correct[accepted].mean()), 6)
                                     if accepted_count else None),
        })
    return rows


def write_confusion_csv(path: Path, matrix, class_list: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["actual\\predicted", *class_list])
        for index, row in enumerate(matrix):
            writer.writerow([class_list[index], *[int(v) for v in row]])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=BEST_MODEL_PATH)
    parser.add_argument("--split", default="test")
    parser.add_argument("--batch-size", type=int, default=48)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0,
                        help="evaluate only the first N test images (0 = all)")
    args = parser.parse_args()

    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import numpy as np
    import tensorflow as tf

    try:
        tf.config.threading.set_intra_op_parallelism_threads(args.threads)
        tf.config.threading.set_inter_op_parallelism_threads(1)
    except RuntimeError as exc:
        log.warning("could not pin thread counts: %s", exc)

    paths, labels, class_list = load_split(args.split)
    if args.limit > 0:
        paths = paths[:args.limit]
        labels = labels[:args.limit]
    num_classes = len(class_list)
    log.info("evaluating %d images over %d classes", len(paths), num_classes)

    if not args.model.exists():
        report = {
            "generated_at": utc_now(),
            "status": "no_model",
            "model_path": str(args.model),
            "message": "No trained model found. Run scripts/train_model.py first. "
                       "Metrics are intentionally null rather than estimated.",
            "metrics": None,
        }
        write_json(METRICS_DIR / "evaluation_report.json", report)
        log.error("no model at %s - wrote report with null metrics", args.model)
        return 1

    model = tf.keras.models.load_model(args.model)
    probabilities, latencies = predict_all(tf, model, paths, args.batch_size)

    y_true = np.asarray(labels, dtype="int64")
    y_pred = probabilities.argmax(axis=1)

    order = np.argsort(-probabilities, axis=1)[:, :5]
    top1 = float((y_pred == y_true).mean())
    top5 = float(np.mean([y_true[i] in order[i] for i in range(len(y_true))]))

    metrics = classification_metrics(np, y_true, y_pred, num_classes)
    matrix = confusion_matrix(np, y_true, y_pred, num_classes)
    write_confusion_csv(METRICS_DIR / "confusion_matrix.csv", matrix, class_list)

    crops = sorted({crop_condition(label)[0] for label in class_list})
    healthy = [i for i, label in enumerate(class_list)
               if crop_condition(label)[1].lower() == "healthy"]

    per_class_rows = []
    for index, label in enumerate(class_list):
        crop, condition = crop_condition(label)
        row = dict(metrics["per_class"][index])
        row.update({"class_label": label, "crop": crop, "condition": condition,
                    "is_healthy_class": index in healthy})
        per_class_rows.append(row)

    report = {
        "generated_at": utc_now(),
        "status": "measured",
        "model_path": str(args.model),
        "tensorflow_version": tf.__version__,
        "device": "cpu",
        "image_size": IMAGE_SIZE,
        "split": args.split,
        "test_images": len(paths),
        "num_classes": num_classes,
        "crops_covered": crops,
        "metrics": {
            "top1_accuracy": round(top1, 6),
            "top5_accuracy": round(top5, 6),
            "macro": metrics["macro"],
            "weighted": metrics["weighted"],
            "average_inference_seconds_per_image": round(
                sum(latencies) / len(latencies), 6),
            "inference_note": "CPU forward pass, batch %d, on this machine only. "
                              "Phone latency will differ." % args.batch_size,
        },
        "unknown_rejection_sweep": threshold_sweep(np, probabilities, y_true),
        "per_class": per_class_rows,
        "confusion_matrix_file": str(METRICS_DIR / "confusion_matrix.csv"),
        "note": "Every number above is from this run on the held-out split. "
                "The model is a crop-and-condition screener, not a 2000-species "
                "identifier: it can only name crops it was trained on and "
                "must answer 'uncertain' for anything else.",
    }
    write_json(METRICS_DIR / "evaluation_report.json", report)

    log.info("top1=%.4f top5=%.4f macro_f1=%.4f weighted_f1=%.4f",
             top1, top5, metrics["macro"]["f1"], metrics["weighted"]["f1"])
    log.info("avg inference %.1f ms/image on CPU",
             1000 * report["metrics"]["average_inference_seconds_per_image"])
    for row in report["unknown_rejection_sweep"]:
        accuracy = ("%.4f" % row["accuracy_on_accepted"]
                    if row["accuracy_on_accepted"] is not None else "n/a")
        log.info("threshold %.2f -> rejected %d (%.1f%%), accuracy on kept %s",
                 row["threshold"], row["rejected_as_unknown"],
                 100 * row["rejection_rate"], accuracy)
    log.info("wrote %s", METRICS_DIR / "evaluation_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
