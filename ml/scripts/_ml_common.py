"""Shared paths and helpers for the PlantDoctor model pipeline.

Everything the ML scripts write lands under ``ml/`` (datasets, splits, models,
metrics, logs). Nothing here is allowed to invent a number: metrics reported by
these scripts come from a real evaluation run on the held-out test split.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

ML_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = ML_DIR.parent
DATA_DIR = ML_DIR / "data"
DATASET_ROOT = DATA_DIR / "data"
SPLIT_DIR = DATA_DIR / "splits"
MODEL_DIR = ML_DIR / "models"
METRICS_DIR = ML_DIR / "metrics"
LOG_DIR = ML_DIR / "logs"
EXPORT_DIR = ML_DIR / "export"

CLASSES_PATH = DATA_DIR / "classes.json"
LABELS_PATH = EXPORT_DIR / "labels.txt"
MODEL_PATH = MODEL_DIR / "plantvillage_mobilenetv3.keras"
BEST_MODEL_PATH = MODEL_DIR / "plantvillage_best.keras"
TFLITE_PATH = EXPORT_DIR / "plantvillage.tflite"

for _directory in (DATA_DIR, SPLIT_DIR, MODEL_DIR, METRICS_DIR, LOG_DIR,
                   EXPORT_DIR):
    _directory.mkdir(parents=True, exist_ok=True)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def setup_logging(name: str, level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(level)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    stream = logging.StreamHandler()
    stream.setFormatter(formatter)
    logger.addHandler(stream)
    handler = logging.FileHandler(LOG_DIR / f"{name}.log", encoding="utf-8")
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger


log = setup_logging("ml")


def read_json(path: Path, default=None):
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    tmp.replace(path)
