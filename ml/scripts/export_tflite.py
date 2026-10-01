#!/usr/bin/env python3
"""Export the trained Keras model to TensorFlow Lite for the Flutter app.

What this does:
  * loads the best model (``ml/models/plantvillage_best.keras``) by default
  * converts to TFLite with dynamic-range quantisation to shrink size
  * writes ``ml/export/plantvillage.tflite``
  * writes ``ml/export/labels.txt`` in the order the model outputs classes

The exported labels.txt is what the Flutter TFLite interpreter uses to map
index -> human-readable class (crop___condition). The app does *not* trust a
TFLite output alone to name a 2000-species plant: it only uses these predictions
as "crop-and-condition suggestions" or returns 'uncertain' when confidence is
too low (per the spec).
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _ml_common import (  # noqa: E402
    BEST_MODEL_PATH,
    CLASSES_PATH,
    EXPORT_DIR,
    LABELS_PATH,
    MODEL_PATH,
    TFLITE_PATH,
    log,
    read_json,
    utc_now,
    write_json,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=BEST_MODEL_PATH)
    parser.add_argument("--optimize", action="store_true", default=True,
                        help="apply dynamic-range quantisation")
    parser.add_argument("--no-optimize", action="store_false", dest="optimize")
    args = parser.parse_args()

    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf

    if not args.model.exists():
        log.error("model not found: %s", args.model)
        return 1

    model = tf.keras.models.load_model(args.model)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if args.optimize:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        log.info("quantisation: dynamic-range (DEFAULT)")

    tflite = converter.convert()
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    TFLITE_PATH.write_bytes(tflite)
    log.info("wrote %s (%.1f KB)", TFLITE_PATH, len(tflite) / 1024.0)

    classes = read_json(CLASSES_PATH) or {}
    if classes.get("classes"):
        class_list = list(classes["classes"])
        LABELS_PATH.write_text("\n".join(class_list) + "\n", encoding="utf-8")
        log.info("wrote %s (%d lines)", LABELS_PATH, len(class_list))

    manifest = {
        "generated_at": utc_now(),
        "model_source": str(args.model),
        "tflite_path": str(TFLITE_PATH),
        "labels_path": str(LABELS_PATH),
        "quantised": bool(args.optimize),
        "image_size": 160,
        "input_tensor": "image",
        "output_tensor": "class_probabilities",
        "note": "This is the PlantVillage crop-and-condition screener. "
                "It does NOT claim to identify 2000+ species. "
                "The app maps low-confidence outputs to 'uncertain'.",
    }
    write_json(EXPORT_DIR / "tflite_export_manifest.json", manifest)
    log.info("wrote export manifest")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
