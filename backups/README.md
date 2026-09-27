# `backups/` — offline copy target

This directory is a **staging area only**. The authoritative backups are written
by the server to `data/plantdoctor/backups/` (or the `plantdoctor_backups`
Docker volume), and this folder exists so you can copy a verified backup onto a
**separate physical drive**.

> **Rule 12: create a backup before any destructive database migration.**
>
> A backup that lives on the same disk as the database is not a backup. It only
> survives accidental deletion; it does not survive disk failure, a stolen
> laptop, or a fire. Copy every backup here, and then to an external drive.

## What is backed up

* the full PostgreSQL database, as a compressed custom-format `pg_dump`
* a `manifest.json` recording the backup time, the schema revision, every table
  name, row counts, the tool version and a SHA-256 checksum of the dump
* non-secret configuration snapshots: the source registry and seed lists

## What is deliberately NOT backed up

* **`.env`** — it holds the database password and the JWT signing keys. Store it
  separately, encrypted, in a password manager. Never in a backup archive that
  might be copied to a shared drive.
* **Uploaded images** — large and reproducible from their metadata rows. Their
  count and location are recorded in the manifest instead. If you need the
  images themselves, use a file-level sync of `data/plantdoctor/uploads/`.

## Routine

```bash
# 1. create and verify a backup (retention is applied automatically)
cd backend
python -m app.cli backup --label before-schema-change

# 2. see what exists, with checksum verification
python -m app.cli backup --list

# 3. copy the newest one here, then to the external drive
cp "$(python -m app.cli backup --list --json | ... )" ../backups/
```

Automate with the `backup` compose service (`--profile tools`) or with a
host cron entry — see `docs/DEPLOYMENT.md`.

## Restoring

```bash
cd backend
python -m app.cli backup --list                 # find the file
python -m app.cli restore plantdoctor_20260927_1430.dump.zst
# A fresh pre-restore backup is always taken first. You are asked to confirm.
```

Verify a restore by checking `/health/database` and that the knowledge row
counts match the manifest.

## Retention

`BACKUP_RETENTION_COUNT` (default 14) is applied after every successful backup:
the oldest dumps beyond that count are removed. Deleting a backup is a normal
part of the cycle, but never delete the only copy of the newest verified dump.
