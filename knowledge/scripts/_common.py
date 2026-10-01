"""Shared helpers for the PlantDoctor offline knowledge pipeline.

Everything under knowledge/scripts writes to a single staging directory and
builds one SQLite file. No step is allowed to invent data: importers only copy
values that a source actually returned, and record where each value came from.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

KNOWLEDGE_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = KNOWLEDGE_DIR.parent
RAW_DIR = KNOWLEDGE_DIR / "data" / "raw"
CURATED_DIR = KNOWLEDGE_DIR / "data" / "curated"
DIST_DIR = KNOWLEDGE_DIR / "dist"
LOG_DIR = KNOWLEDGE_DIR / "logs"

DB_PATH = DIST_DIR / "plantdoctor.db"
MANIFEST_PATH = DIST_DIR / "manifest.json"

# The app ships the bundle as a Flutter asset, so a build has to land in both
# places: knowledge/dist for inspection, and the asset path the APK packages.
ASSET_DB_PATH = REPO_ROOT / "mobile" / "assets" / "plant_knowledge" / "plantdoctor.db"

for _d in (RAW_DIR, CURATED_DIR, DIST_DIR, LOG_DIR):
    _d.mkdir(parents=True, exist_ok=True)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def setup_logging(name: str, level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(level)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    stream = logging.StreamHandler()
    stream.setFormatter(fmt)
    logger.addHandler(stream)
    file_handler = logging.FileHandler(LOG_DIR / f"{name}.log", encoding="utf-8")
    file_handler.setFormatter(fmt)
    logger.addHandler(file_handler)
    return logger


USER_AGENT = "PlantDoctorAI/0.1 (offline knowledge pipeline; contact: vanshdhimang9@gmail.com)"


def http_get_json(url: str, retries: int = 4, timeout: int = 40) -> Any:
    """GET a JSON document with exponential backoff. Raises on final failure."""
    delay = 1.0
    last: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, ValueError, OSError) as exc:
            last = exc
            if attempt == retries:
                break
            time.sleep(delay)
            delay *= 2
    raise RuntimeError(f"GET {url} failed after {retries} attempts: {last}")


def gbif(path: str, params: dict[str, Any] | None = None) -> Any:
    url = "https://api.gbif.org/v1" + path
    if params:
        clean = {k: v for k, v in params.items() if v is not None}
        if clean:
            url += "?" + urllib.parse.urlencode(clean)
    return http_get_json(url)


def read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=False)
        handle.write("\n")
    tmp.replace(path)


def slugify(scientific_name: str) -> str:
    """Stable, human-readable identifier: 'Solanum lycopersicum' -> solanum-lycopersicum'."""
    cleaned = []
    for ch in scientific_name.lower().strip():
        if ch.isalnum():
            cleaned.append(ch)
        elif ch in " -×":
            cleaned.append("-")
    slug = "".join(cleaned)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-")


def normalise_name(name: str) -> str:
    return " ".join(name.replace("×", "x").split()).lower()
