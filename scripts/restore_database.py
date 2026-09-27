#!/usr/bin/env python3
"""Restore the PlantDoctor knowledge base from a backup.

This REPLACES the contents of the target database, so it refuses to run
without --confirm-restore. It also refuses to touch a database whose name does
not end in _test unless --allow-production is given, because the development
and production knowledge bases are easy to confuse.

Usage:
    python3 scripts/restore_database.py --list
    python3 scripts/restore_database.py --backup-dir <dir>
    python3 scripts/restore_database.py --backup-dir <dir> --dry-run
    python3 scripts/restore_database.py --backup-dir <dir> --confirm-restore
    python3 scripts/restore_database.py --backup-dir <dir> --confirm-restore --allow-production
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from _common import (
    Counters,
    get_logger,
    run_tool,
    setup_logging,
    transaction,
    utc_now_iso,
)

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plantdoctor_api.config import get_settings  # noqa: E402

log = get_logger("restore_database")


def list_backups(base: Path) -> int:
    if not base.is_dir():
        log.error("backup directory does not exist: %s", base)
        return 1
    entries = sorted((p for p in base.iterdir() if p.is_dir()), reverse=True)
    if not entries:
        print(f"no backups found in {base}")
        return 0
    print(f"{'BACKUP':<44} {'CREATED':<22} {'SIZE':>10}  DB")
    for entry in entries:
        manifest_path = entry / "manifest.json"
        if not manifest_path.is_file():
            print(f"{entry.name:<44} {'(no manifest)':<22} {'-':>10}")
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        size = manifest.get("dump_bytes", 0)
        human = f"{size / 1024 / 1024:.1f} MiB" if size else "-"
        print(f"{entry.name:<44} {manifest.get('created_at', '?')[:19]:<22} {human:>10}  "
              f"{manifest.get('database', {}).get('name', '?')}")
    return 0


def preflight(target: Path, manifest: dict[str, Any], settings: Any) -> tuple[bool, str]:
    dump_path = target / manifest["dump_file"]
    if not dump_path.is_file():
        return False, f"dump file missing: {dump_path}"

    result = run_tool(["pg_restore", "--list", str(dump_path)], check=False, capture=True)
    if result.returncode != 0:
        return False, f"dump archive is not readable: {(result.stderr or '').strip()}"

    recorded = manifest.get("dump_bytes")
    if recorded and dump_path.stat().st_size != recorded:
        return False, (
            f"dump size {dump_path.stat().st_size} does not match manifest {recorded}"
        )

    connect = run_tool(
        ["psql", "--host", settings.db_host, "--port", str(settings.db_port),
         "--username", settings.db_user, "--dbname", "postgres", "--no-password",
         "-tAc", "SELECT 1"],
        check=False, capture=True, env={**_env(), "PGPASSWORD": settings.db_password},
    )
    if connect.returncode != 0:
        return False, f"cannot reach PostgreSQL: {(connect.stderr or '').strip()}"
    return True, "preflight checks passed"


def _env() -> dict[str, str]:
    import os

    return dict(os.environ)


def restore(target: Path, manifest: dict[str, Any], settings: Any, args: argparse.Namespace) -> int:
    dump_path = target / manifest["dump_file"]
    db = args.database or settings.db_name

    log.info("restoring %s into database %s", dump_path, db)

    # --clean --if-exists makes the restore idempotent and removes objects that
    # exist now but not in the dump, which is what "restore" has to mean here.
    result = run_tool(
        [
            "pg_restore",
            "--host", settings.db_host,
            "--port", str(settings.db_port),
            "--username", settings.db_user,
            "--dbname", db,
            "--clean", "--if-exists", "--no-owner", "--no-privileges",
            "--single-transaction",
            "--verbose",
            str(dump_path),
        ],
        check=False,
        capture=True,
        env={**_env(), "PGPASSWORD": settings.db_password},
    )
    # pg_restore --verbose writes to stderr; errors can appear alongside
    # benign notices, so inspect the exit status rather than grepping text.
    if result.returncode != 0:
        log.error("pg_restore failed with exit code %d", result.returncode)
        for line in (result.stderr or "").splitlines()[-25:]:
            log.error("  %s", line)
        return 1

    log.info("restore finished; comparing row counts against the manifest")
    expected: dict[str, Any] = manifest.get("row_counts", {})
    counters = Counters()
    mismatches: list[str] = []

    with transaction() as cur:
        for table, want in expected.items():
            if table.startswith("_"):
                continue
            cur.execute(f'SELECT count(*) AS n FROM "{table}"')
            got = int(cur.fetchone()["n"])
            if got != want:
                mismatches.append(f"{table}: expected {want}, got {got}")
                counters.bump("mismatch")
            else:
                counters.bump("matched")

    print()
    print("=" * 68)
    print("PLANTDOCTOR AI - RESTORE COMPLETE")
    print("=" * 68)
    print(f"source     : {target}")
    print(f"database   : {db}")
    print(f"restored at: {utc_now_iso()}")
    print(f"tables     : {counters.get('matched')} matched, {counters.get('mismatch')} mismatched")
    if mismatches:
        print()
        print("row-count mismatches (investigate before trusting this restore):")
        for line in mismatches[:30]:
            print(f"  {line}")
        if len(mismatches) > 30:
            print(f"  ... and {len(mismatches) - 30} more")
        print("=" * 68)
        return 2
    print("result     : PASS - restored row counts match the backup manifest")
    print("=" * 68)
    return 0


def main(argv: list[str] | None = None) -> int:
    settings = get_settings()
    default_base = settings.data_path("backups")
    parser = argparse.ArgumentParser(description="Restore the PlantDoctor knowledge base")
    parser.add_argument("--backup-dir", default=None, help="backup directory to restore from")
    parser.add_argument("--database", default=None,
                        help="target database (default: the configured one)")
    parser.add_argument("--list", action="store_true", help="list available backups and exit")
    parser.add_argument("--dry-run", action="store_true",
                        help="run preflight checks and print the plan without restoring")
    parser.add_argument("--confirm-restore", action="store_true",
                        help="required: acknowledges that the target database is replaced")
    parser.add_argument("--allow-production", action="store_true",
                        help="required when the target database is not a _test database")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    setup_logging(args.log_level)
    base = Path(args.backup_dir) if args.backup_dir else default_base

    if args.list:
        return list_backups(base)

    if not args.backup_dir:
        raise SystemExit("--backup-dir is required (use --list to see available backups)")

    target = base
    manifest_path = target / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"no manifest.json in {target}; not a PlantDoctor backup directory")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    db = args.database or settings.db_name
    if not db.endswith("_test") and not args.allow_production:
        raise SystemExit(
            f"refusing to restore into non-test database {db!r} without --allow-production. "
            "A restore replaces the entire database contents."
        )
    if not args.confirm_restore:
        raise SystemExit(
            "refusing to restore without --confirm-restore. A restore replaces the entire "
            "database contents; take a fresh backup first if unsure."
        )

    ok, detail = preflight(target, manifest, settings)
    if not ok:
        log.error("preflight failed: %s", detail)
        return 1
    log.info("preflight: %s", detail)

    if args.dry_run:
        print("[dry-run] preflight passed; would restore with:")
        print(f"  pg_restore --clean --if-exists --single-transaction {target / manifest['dump_file']}")
        print(f"  into database {db}")
        print(f"  {len(manifest.get('row_counts', {}))} table row-counts would be compared")
        return 0

    return restore(target, manifest, settings, args)


if __name__ == "__main__":
    raise SystemExit(main())
