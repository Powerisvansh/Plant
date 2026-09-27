"""Configuration loaded from environment only. No credentials are stored in code."""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

DEFAULT_ENV_FILE = Path("/plantdoctor-data/.env")


def _load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_name: str
    db_test_name: str
    db_user: str
    db_password: str
    data_root: Path
    log_level: str
    api_host: str
    api_port: int
    max_upload_bytes: int
    allowed_image_mimes: tuple[str, ...]

    @property
    def dsn(self) -> str:
        return self._dsn(self.db_name)

    @property
    def test_dsn(self) -> str:
        return self._dsn(self.db_test_name)

    def _dsn(self, database: str) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={database} "
            f"user={self.db_user} password={self.db_password} application_name=plantdoctor"
        )

    def data_path(self, *parts: str) -> Path:
        return self.data_root.joinpath(*parts)


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise RuntimeError(f"Environment variable {name} must be an integer, got {raw!r}") from exc


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    _load_env_file(Path(os.environ.get("PLANTDOCTOR_ENV_FILE", DEFAULT_ENV_FILE)))

    missing = [k for k in ("PLANTDOCTOR_DB_NAME", "PLANTDOCTOR_DB_USER", "PLANTDOCTOR_DB_PASSWORD")
               if not os.environ.get(k)]
    if missing:
        raise RuntimeError(
            "Missing required configuration: " + ", ".join(missing) + ". "
            f"Set them in {os.environ.get('PLANTDOCTOR_ENV_FILE', DEFAULT_ENV_FILE)}."
        )

    return Settings(
        db_host=os.environ.get("PLANTDOCTOR_DB_HOST", "127.0.0.1"),
        db_port=_int_env("PLANTDOCTOR_DB_PORT", 5432),
        db_name=os.environ["PLANTDOCTOR_DB_NAME"],
        db_test_name=os.environ.get("PLANTDOCTOR_DB_TEST_NAME", os.environ["PLANTDOCTOR_DB_NAME"] + "_test"),
        db_user=os.environ["PLANTDOCTOR_DB_USER"],
        db_password=os.environ["PLANTDOCTOR_DB_PASSWORD"],
        data_root=Path(os.environ.get("PLANTDOCTOR_DATA_ROOT", "/plantdoctor-data")),
        log_level=os.environ.get("PLANTDOCTOR_LOG_LEVEL", "INFO").upper(),
        api_host=os.environ.get("PLANTDOCTOR_API_HOST", "127.0.0.1"),
        api_port=_int_env("PLANTDOCTOR_API_PORT", 8080),
        max_upload_bytes=_int_env("PLANTDOCTOR_MAX_UPLOAD_BYTES", 12 * 1024 * 1024),
        allowed_image_mimes=("image/jpeg", "image/png", "image/webp"),
    )
