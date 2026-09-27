#!/usr/bin/env python3
"""Shared helpers for the PlantDoctor import, validation and backup scripts.

Kept deliberately small: only behaviour that every script genuinely needs lives
here, so each script still reads as a standalone tool.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from plantdoctor_api.db import transaction  # noqa: E402

# Files whose presence or absence must never be guessed at.
CHECKER_VERSION = "1.0.0"

# Licences under which an imported dataset may be redistributed by this project.
# Anything outside this set has to be approved by a human before import.
REDISTRIBUTABLE_LICENSES = {
    "CC0",
    "CC_BY_3_0",
    "CC_BY_4_0",
    "CC_BY_SA_3_0",
    "CC_BY_SA_4_0",
    "CC_BY_NC_4_0",
    "PUBLIC_DOMAIN",
    "ODC_BY_1_0",
    "PERMISSION_GRANTED",
}


def setup_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        stream=sys.stderr,
    )


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


@dataclass
class Counters:
    """Uniform counters so every script reports progress the same way."""

    fields_: dict[str, int] = field(default_factory=dict)

    def bump(self, key: str, amount: int = 1) -> None:
        self.fields_[key] = self.fields_.get(key, 0) + amount

    def get(self, key: str) -> int:
        return self.fields_.get(key, 0)

    def as_dict(self) -> dict[str, int]:
        return dict(sorted(self.fields_.items()))

    def summary(self) -> str:
        return " ".join(f"{k}={v}" for k, v in self.as_dict().items())


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path: Path, chunk_size: int = 1 << 20) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(chunk_size), b""):
            digest.update(block)
    return digest.hexdigest()


def require_source(cur, key: str, *, must_be_approved: bool = True) -> dict[str, Any]:
    """Fetch a registered source, refusing to proceed on an unapproved one.

    Every importer must name the source it imported from. If that source is not
    registered, or is still pending review, the import is refused rather than
    silently attributing data to a source nobody vetted.
    """
    cur.execute(
        """
        SELECT id, key, name, license, approval_status, redistribution_allowed
          FROM sources WHERE key = %s
        """,
        (key,),
    )
    row = cur.fetchone()
    if row is None:
        raise SystemExit(
            f"source {key!r} is not registered; add it to data/sources.json and run "
            "scripts/seed_sources.py before importing"
        )
    if must_be_approved and row["approval_status"] != "APPROVED":
        raise SystemExit(
            f"source {key!r} has approval_status={row['approval_status']}; refusing to import. "
            "Set approval_status to APPROVED in data/sources.json once the licence and terms "
            "have actually been checked."
        )
    return dict(row)


def add_provenance(
    cur,
    table: str,
    record_id: int,
    source_id: int | None,
    field_name: str | None,
    method: str,
    value: str | None,
    confidence: float | None,
    verification: str,
    notes: str,
) -> None:
    """Record where a fact came from. Idempotent on the active (unsuperseded) row."""
    cur.execute(
        "SELECT 1 FROM data_provenance WHERE table_name=%s AND record_id=%s "
        "AND COALESCE(field_name,'')=COALESCE(%s,'') AND superseded_at IS NULL",
        (table, record_id, field_name),
    )
    if cur.fetchone():
        return
    cur.execute(
        """
        INSERT INTO data_provenance (table_name, record_id, field_name, source_id,
                                     extracted_value, extraction_method, confidence,
                                     verification_status, notes)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (table, record_id, field_name, source_id,
         (value or "")[:4000] if value else None,
         method, confidence, verification, notes),
    )


def read_json_records(path: Path) -> list[dict[str, Any]]:
    """Read a JSON file that is either a list or {"records": [...]} / {"<key>": [...]}."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for value in payload.values():
            if isinstance(value, list):
                return value
    raise SystemExit(f"{path}: expected a JSON list of records")


def data_root() -> Path:
    from plantdoctor_api.config import get_settings

    return get_settings().data_root


def rel_to_data_root(path: Path) -> str:
    """Store paths relative to the data root so the database survives a remount."""
    root = data_root().resolve()
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(root))
    except ValueError:
        return str(resolved)


def resolve_data_path(relative_or_absolute: str) -> Path:
    candidate = Path(relative_or_absolute)
    if candidate.is_absolute():
        return candidate
    return data_root() / candidate


def human_bytes(count: int) -> str:
    step = float(count)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if step < 1024 or unit == "TiB":
            return f"{step:.1f} {unit}"
        step /= 1024
    return f"{step:.1f} TiB"


def run_tool(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    """Run an external tool, logging the exact command for auditability.

    `env` is merged onto the current environment rather than replacing it, so
    callers only need to supply the one variable a tool actually needs (for
    example PGPASSWORD).
    """
    log = logging.getLogger("tool")
    log.info("exec: %s", " ".join(cmd))
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
        env={**os.environ, **env} if env else None,
    )


def normalise_license(raw: str | None) -> str:
    if not raw:
        return "UNKNOWN"
    token = re.sub(r"[^A-Z0-9]+", "_", raw.strip().upper()).strip("_")
    aliases = {
        "CC0": "CC0",
        "CC_BY_4_0": "CC_BY_4_0",
        "CC_BY_3_0": "CC_BY_3_0",
        "CC0_1_0": "CC0",
        "PUBLIC_DOMAIN": "PUBLIC_DOMAIN",
        "PDM": "PUBLIC_DOMAIN",
        "US_GOV": "PUBLIC_DOMAIN",
    }
    return aliases.get(token, token)


def today() -> str:
    return date.today().isoformat()


def iter_batches(items: list[Any], size: int) -> Iterable[list[Any]]:
    for start in range(0, len(items), size):
        yield items[start:start + size]
