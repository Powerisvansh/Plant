"""Database connection, migration state and test-isolation guarantees."""

from __future__ import annotations

from pathlib import Path

import psycopg

from plantdoctor_api.db import query_one, query_scalar


def test_connection_pool_is_usable(db):
    with db.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 AS ok")
            assert cur.fetchone()["ok"] == 1


def test_server_reachable_and_version_reported():
    assert query_scalar("SELECT version()").startswith("PostgreSQL")


def test_all_migrations_applied():
    rows = query_one(
        """
        SELECT count(*)::int AS applied, max(version) AS latest
          FROM schema_migrations
        """
    )
    migrations_dir = Path(__file__).resolve().parents[1] / "migrations"
    expected = len(list(migrations_dir.glob("*.sql")))
    assert rows["latest"] == f"{expected - 1:03d}", "highest migration on disk must be applied"
    assert rows["applied"] == expected, "every migration file must be applied exactly once"


def test_no_pending_migrations_on_disk():
    """Every migration file on disk must be recorded as applied, with a matching checksum."""
    import hashlib
    from pathlib import Path

    migrations_dir = Path(__file__).resolve().parents[1] / "migrations"
    on_disk = {p.name: p for p in sorted(migrations_dir.glob("*.sql"))}
    assert on_disk, "no migration files found"

    applied = {
        row["filename"]: row["checksum"]
        for row in _fetchall("SELECT filename, checksum FROM schema_migrations")
    }
    assert set(on_disk) == set(applied), (
        f"drift between disk and database: "
        f"only_on_disk={sorted(set(on_disk) - set(applied))} "
        f"only_in_db={sorted(set(applied) - set(on_disk))}"
    )
    for name, path in on_disk.items():
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert applied[name] == digest, f"{name} was modified after being applied"


def _fetchall(sql: str):
    from plantdoctor_api.db import query_all

    return query_all(sql)


def test_required_extensions_present():
    for ext in ("pg_trgm", "btree_gin", "pgcrypto"):
        assert query_scalar("SELECT 1 FROM pg_extension WHERE extname = %s", (ext,)) == 1


def test_tests_run_against_test_database_only():
    from plantdoctor_api.config import get_settings

    assert get_settings().db_name.endswith("_test"), (
        "the suite must never run against the development database"
    )


def test_clean_db_fixture_empties_knowledge_tables(db, clean_db):
    """The isolation fixture must really empty the knowledge tables.

    Verified by seeding rows, running the same cleanup the fixture uses, and
    checking both the row counts and that identity sequences restarted.
    """
    from conftest import _clean_all, insert_plant, insert_source

    with db.connection() as conn:
        with conn.cursor() as cur:
            source_id = insert_source(cur, "wfo", "World Flora Online (WFO)")
            first_plant = insert_plant(cur, "Solanum lycopersicum L.", source_id)
            second_plant = insert_plant(cur, "Ocimum basilicum L.", source_id)
            cur.execute("SELECT count(*) AS n FROM plants")
            assert cur.fetchone()["n"] == 2

            _clean_all(cur)

            cur.execute("SELECT count(*) AS n FROM plants")
            assert cur.fetchone()["n"] == 0
            cur.execute("SELECT count(*) AS n FROM sources")
            assert cur.fetchone()["n"] == 0

            # Sequences restart, so identity columns do not drift test to test.
            fresh_source = insert_source(cur, "powo", "Plants of the World Online")
            new_plant = insert_plant(cur, "Mentha spicata L.", fresh_source)
            assert new_plant == first_plant
            assert new_plant != second_plant
        conn.rollback()

    # Leave the shared database clean for whatever runs next.
    with db.connection() as conn:
        with conn.cursor() as cur:
            _clean_all(cur)
        conn.commit()
