"""Single source of truth for environment loading.

The server and the legacy knowledge-base module share one env file so there is
exactly one place where credentials live on this machine. Existing process
environment variables always win, so container/CI injection keeps priority.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

_ENV_LOADED = False

#: Search order for the env file. The first existing file wins.
CANDIDATE_ENV_FILES: tuple[str, ...] = (
    "/plantdoctor-data/.env",
    str(Path(__file__).resolve().parents[2] / ".env"),
)


def candidate_paths() -> list[Path]:
    explicit = os.environ.get("PLANTDOCTOR_ENV_FILE", "").strip()
    if explicit:
        return [Path(explicit), *CANDIDATE_ENV_FILES]
    return [Path(p) for p in CANDIDATE_ENV_FILES]


def load_env_file(path: Path | None = None, *, override: bool = False) -> Path | None:
    """Merge an env file into ``os.environ``.

    Returns the path that was loaded, or ``None`` when no file was found.
    Never raises for a missing file: a container may supply every value
    directly through the environment.
    """
    targets = [path] if path is not None else candidate_paths()
    for candidate in targets:
        if not candidate.is_file():
            continue
        for raw_line in candidate.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if not key:
                continue
            if override or key not in os.environ:
                os.environ[key] = value
        return candidate
    return None


def ensure_env_loaded() -> Path | None:
    global _ENV_LOADED
    if _ENV_LOADED:
        return None
    _ENV_LOADED = True
    return load_env_file()


def describe_sources() -> dict[str, object]:
    """Diagnostics for /health and startup logs. Never returns values."""
    return {
        "env_file_loaded": any(p.is_file() for p in candidate_paths()),
        "env_file_candidates": [str(p) for p in candidate_paths()],
        "python": sys.version.split()[0],
    }
