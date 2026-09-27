#!/usr/bin/env python3
"""Migration runner for the PlantDoctor knowledge base.

Applies every unapplied file in backend/migrations in filename order inside a
single transaction per file, recording each in the `schema_migrations` table.

Usage:
    python3 scripts/migrate.py status
    python3 scripts/migrate.py up
    python3 scripts/migrate.py up --dry-run
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import re
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

from plantdoctor_api.config import get_settings  # noqa: E402
from plantdoctor_api.db import connection  # noqa: E402

MIGRATIONS_DIR = REPO_ROOT / "backend" / "migrations"
MIGRATION_RE = re.compile(r"^(\d{3})_([a-z0-9_]+)\.sql$")

BOOTSTRAP_SQL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     TEXT PRIMARY KEY,
    filename    TEXT NOT NULL,
    checksum    TEXT NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_ms INTEGER NOT NULL
);
"""

log = logging.getLogger("migrate")


def discover() -> list[tuple[str, Path]]:
    files: list[tuple[str, Path]] = []
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        match = MIGRATION_RE.match(path.name)
        if not match:
            raise SystemExit(
                f"Migration filename must look like 001_name.sql, got {path.name!r}"
            )
        files.append((match.group(1), path))
    versions = [v for v, _ in files]
    if len(versions) != len(set(versions)):
        raise SystemExit("Duplicate migration version prefix found")
    return files


def checksum(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def applied_versions(cur) -> dict[str, str]:
    cur.execute("SELECT version, checksum FROM schema_migrations")
    return {row["version"]: row["checksum"] for row in cur.fetchall()}


def command_status() -> int:
    files = discover()
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(BOOTSTRAP_SQL)
            conn.commit()
            done = applied_versions(cur)
    print(f"{'VERSION':<8} {'STATE':<12} FILE")
    for version, path in files:
        state = "applied" if version in done else "pending"
        flag = ""
        if version in done and done[version] != checksum(path):
            flag = "  !! CHECKSUM CHANGED"
        print(f"{version:<8} {state:<12} {path.name}{flag}")
    return 0


def command_up(dry_run: bool) -> int:
    settings = get_settings()
    files = discover()
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(BOOTSTRAP_SQL)
            conn.commit()
            done = applied_versions(cur)

    pending = [(v, p) for v, p in files if v not in done]
    if not pending:
        log.info("No pending migrations. Schema is up to date.")
        return 0

    log.info("%d migration(s) pending.", len(pending))
    for version, path in pending:
        sql = path.read_text(encoding="utf-8")
        if dry_run:
            print(f"[dry-run] would apply {path.name} ({len(sql)} bytes)")
            continue
        started = time.monotonic()
        with connection() as conn:
            try:
                with conn.cursor() as cur:
                    cur.execute(sql)
                    cur.execute(
                        "INSERT INTO schema_migrations (version, filename, checksum, duration_ms) "
                        "VALUES (%s, %s, %s, %s)",
                        (version, path.name, checksum(path), int((time.monotonic() - started) * 1000)),
                    )
                conn.commit()
            except Exception as exc:
                conn.rollback()
                log.error("FAILED %s: %s", path.name, exc)
                raise
        log.info("applied %s in %d ms", path.name, int((time.monotonic() - started) * 1000))

    if not dry_run:
        log.info("Schema at %s is up to date (%d migrations).", settings.db_name, len(files))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PlantDoctor knowledge base migrations")
    parser.add_argument("command", choices=["status", "up"], nargs="?", default="status")
    parser.add_argument("--dry-run", action="store_true", help="print what would run without running it")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(message)s",
        stream=sys.stderr,
    )
    if args.command == "status":
        return command_status()
    return command_up(args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
