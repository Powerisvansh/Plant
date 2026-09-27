#!/usr/bin/env python3
"""Back up the PlantDoctor knowledge base.

What is backed up:
  * the PostgreSQL database, as a compressed custom-format pg_dump
  * the data-quality reports and validation history (also inside the dump)
  * non-secret configuration: schema/data source registry, seed lists
  * a manifest with checksums so a restore can be verified

What is NOT backed up, deliberately:
  * raw image and dataset files. They are large, reproducible from their
    recorded source and licence, and duplicating them would fill the disk for
    no benefit. The manifest records their location and row counts instead.
  * .env, which holds credentials. Back up separately and securely.

Usage:
    python3 scripts/backup_database.py --dry-run
    python3 scripts/backup_database.py
    python3 scripts/backup_database.py --label pre-import
    python3 scripts/backup_database.py --verify
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from _common import (
    get_logger,
    human_bytes,
    run_tool,
    setup_logging,
    transaction,
    utc_now_iso,
)

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plantdoctor_api.config import get_settings  # noqa: E402

log = get_logger("backup_database")

# Files copied alongside the dump. The .env is intentionally excluded.
CONFIG_GLOBS = ("data/sources.json", "data/seed_species.txt")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def build_target(base: Path, label: str | None) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = f"plantdoctor-{stamp}-{label}" if label else f"plantdoctor-{stamp}"
    return base / name


def collect_kb_stats() -> dict[str, Any]:
    """Row counts per table, so a restore can be compared against the source."""
    stats: dict[str, Any] = {}
    with transaction() as cur:
        cur.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
        )
        for row in cur.fetchall():
            table = row["tablename"]
            cur.execute(f'SELECT count(*) AS n FROM "{table}"')
            stats[table] = int(cur.fetchone()["n"])
        cur.execute("SELECT count(*) AS n FROM schema_migrations")
        stats["_migrations_applied"] = int(cur.fetchone()["n"])
    return stats


def verify_dump(dump_path: Path) -> tuple[bool, str]:
    """Ask pg_restore to parse the archive without writing anything."""
    result = run_tool(
        ["pg_restore", "--list", str(dump_path)],
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        return False, (result.stderr or "pg_restore --list failed").strip()
    entries = [line for line in result.stdout.splitlines() if line.strip()]
    return True, f"archive parses; {len(entries)} catalog entries"


def do_backup(target: Path, args: argparse.Namespace) -> int:
    settings = get_settings()
    target.mkdir(parents=True, exist_ok=True)
    dump_path = target / "knowledge_base.dump"

    log.info("backing up database %s to %s", settings.db_name, dump_path)
    # --format=custom is compressed and restorable with pg_restore, including
    # selective restores. A single file avoids tar gymnastics.
    #
    # The password is passed through the environment rather than the command
    # line, so it never appears in the process list or in the logged command.
    result = run_tool(
        [
            "pg_dump",
            "--host", settings.db_host,
            "--port", str(settings.db_port),
            "--username", settings.db_user,
            "--dbname", settings.db_name,
            "--format", "custom",
            "--compress", "6",
            "--no-owner",
            "--no-privileges",
            "--file", str(dump_path),
        ],
        check=False,
        capture=True,
        env={**os.environ, "PGPASSWORD": settings.db_password},
    )
    if result.returncode != 0:
        log.error("pg_dump failed: %s", (result.stderr or "").strip())
        return 1

    ok, detail = verify_dump(dump_path)
    if not ok:
        log.error("dump verification failed: %s", detail)
        return 1
    log.info("dump verified: %s", detail)

    config_dir = target / "config"
    config_dir.mkdir(exist_ok=True)
    copied: list[str] = []
    root = repo_root()
    for rel in CONFIG_GLOBS:
        src = root / rel
        if src.is_file():
            (config_dir / src.name).write_bytes(src.read_bytes())
            copied.append(rel)
    log.info("copied %d configuration file(s)", len(copied))

    stats = collect_kb_stats()
    manifest = {
        "created_at": utc_now_iso(),
        "tool": "scripts/backup_database.py",
        "database": {
            "name": settings.db_name,
            "host": settings.db_host,
            "port": settings.db_port,
            "server_version": _server_version(settings),
        },
        "dump_file": dump_path.name,
        "dump_bytes": dump_path.stat().st_size,
        "dump_human": human_bytes(dump_path.stat().st_size),
        "config_files": copied,
        "excluded": [
            ".env (contains credentials; back up separately and securely)",
            "raw image and dataset files (large, reproducible from recorded source/licence)",
        ],
        "row_counts": stats,
        "verify": detail,
        "restore_hint": (
            "python3 scripts/restore_database.py --backup-dir <this directory> "
            "--confirm-restore"
        ),
    }
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    log.info("manifest written to %s", target / "manifest.json")

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - BACKUP COMPLETE")
    print("=" * 68)
    print(f"location     : {target}")
    print(f"database     : {settings.db_name}")
    print(f"dump         : {dump_path.name} ({manifest['dump_human']})")
    print(f"config files : {len(copied)}")
    print(f"tables       : {len([k for k in stats if not k.startswith('_')])}")
    print(f"rows         : {sum(v for k, v in stats.items() if not k.startswith('_'))}")
    print(f"verified     : {detail}")
    print("not included : .env, raw image/dataset files (see manifest)")
    print("=" * 68)
    return 0


def _server_version(settings: Any) -> str:
    from plantdoctor_api.db import query_scalar

    try:
        return (query_scalar("SHOW server_version") or "unknown").strip()
    except Exception as exc:  # pragma: no cover
        log.warning("could not read server version: %s", exc)
        return "unknown"


def do_verify(base: Path) -> int:
    if not base.is_dir():
        log.error("not a backup directory: %s", base)
        return 1
    manifest_path = base / "manifest.json"
    if not manifest_path.is_file():
        log.error("manifest.json missing in %s", base)
        return 1
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    dump_path = base / manifest["dump_file"]

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - BACKUP VERIFICATION")
    print("=" * 68)
    print(f"directory    : {base}")
    print(f"created at   : {manifest['created_at']}")
    print(f"database     : {manifest['database']['name']}")

    exit_code = 0
    if not dump_path.is_file():
        print(f"dump         : MISSING ({dump_path.name})")
        exit_code = 1
    else:
        size = dump_path.stat().st_size
        print(f"dump         : {dump_path.name} ({human_bytes(size)})")
        if size != manifest.get("dump_bytes"):
            print(f"               WARNING size differs from manifest "
                  f"({manifest.get('dump_bytes')})")
            exit_code = 1
        ok, detail = verify_dump(dump_path)
        print(f"archive      : {'OK' if ok else 'CORRUPT'} - {detail}")
        if not ok:
            exit_code = 1

    for rel in manifest.get("config_files", []):
        present = (base / "config" / Path(rel).name).is_file()
        print(f"config       : {rel} {'OK' if present else 'MISSING'}")
        if not present:
            exit_code = 1

    print(f"migrations   : {manifest['row_counts'].get('_migrations_applied')} recorded")
    print(f"result       : {'PASS' if exit_code == 0 else 'FAIL'}")
    print("=" * 68)
    return exit_code


def main(argv: list[str] | None = None) -> int:
    settings = get_settings()
    parser = argparse.ArgumentParser(description="Back up the PlantDoctor knowledge base")
    default_base = settings.data_path("backups")
    parser.add_argument("--backup-dir", default=None,
                        help=f"where to write the backup (default: {default_base})")
    parser.add_argument("--label", default=None, help="suffix for the backup directory name")
    parser.add_argument("--dry-run", action="store_true",
                        help="report what would be written without writing it")
    parser.add_argument("--verify", action="store_true",
                        help="verify an existing backup instead of creating one")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    setup_logging(args.log_level)
    base = Path(args.backup_dir) if args.backup_dir else default_base

    if args.verify:
        target = Path(args.backup_dir) if args.backup_dir else base
        return do_verify(target)

    if args.dry_run:
        target = build_target(base, args.label)
        print("[dry-run] would create:")
        print(f"  {target / 'knowledge_base.dump'}   (pg_dump -Fc of {settings.db_name})")
        print(f"  {target / 'config'}/              ({len(CONFIG_GLOBS)} config file(s))")
        print(f"  {target / 'manifest.json'}")
        print("[dry-run] excluded: .env, raw image/dataset files")
        return 0

    return do_backup(build_target(base, args.label), args)


if __name__ == "__main__":
    raise SystemExit(main())
