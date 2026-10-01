"""Shared pytest fixtures for the PlantDoctor knowledge base.

Safety rules enforced here:

* Tests NEVER touch the development database. The suite refuses to run if
  ``PLANTDOCTOR_DB_NAME`` does not end in ``_test``.
* Migrations are applied to the test database automatically, so the suite is
  self-verifying against the real schema.
* Every test starts from an empty set of knowledge tables.
"""

from __future__ import annotations

import os
import re
import sys
from collections.abc import Iterator
from pathlib import Path

import psycopg
import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_DIR.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))


def _load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_env_file(Path(os.environ.get("PLANTDOCTOR_ENV_FILE", "/plantdoctor-data/.env")))

# Redirect every connection in this process to the throwaway test database.
_BASE_DB = os.environ.get("PLANTDOCTOR_DB_NAME", "plantdoctor")
TEST_DB = os.environ.get("PLANTDOCTOR_DB_TEST_NAME") or f"{_BASE_DB}_test"

if not TEST_DB.endswith("_test"):
    raise RuntimeError(
        f"Refusing to run tests against non-test database {TEST_DB!r}; "
        "the name must end with '_test'."
    )
os.environ["PLANTDOCTOR_DB_NAME"] = TEST_DB

from plantdoctor_api import config as _config  # noqa: E402
from plantdoctor_api.db import close_pool, init_pool  # noqa: E402

_config.get_settings.cache_clear()
TEST_SETTINGS = _config.get_settings()


def _admin_dsn() -> str:
    return (
        f"host={TEST_SETTINGS.db_host} port={TEST_SETTINGS.db_port} "
        f"dbname=postgres user={TEST_SETTINGS.db_user} "
        f"password={TEST_SETTINGS.db_password}"
    )


def _ensure_test_database() -> None:
    with psycopg.connect(_admin_dsn(), autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (TEST_DB,))
            if cur.fetchone() is not None:
                return
            try:
                cur.execute(f'CREATE DATABASE "{TEST_DB}"')
            except psycopg.errors.InsufficientPrivilege as exc:
                raise RuntimeError(
                    f"The test database {TEST_DB!r} does not exist and this role "
                    "may not create databases. Create it once with an "
                    "administrative role, or grant CREATEDB:\n"
                    f'  CREATE DATABASE "{TEST_DB}";'
                ) from exc


def _apply_migrations() -> None:
    """Run scripts/migrate.py logic against the test database."""
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import migrate  # type: ignore[import-not-found]

    if migrate.command_up(False) != 0:
        raise RuntimeError("migrations failed against the test database")


def _knowledge_tables() -> set[str]:
    """Names of the tables the knowledge SQL migrations create.

    Derived from the migrations rather than hard-coded, so the set stays
    correct as the knowledge schema evolves. These tests own exactly this part
    of the database; the application tables next door belong to the
    application suite, which seeds reference data (roles, permissions) and
    creates its rows through the API.
    """
    pattern = re.compile(
        r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?\"?([a-zA-Z_][a-zA-Z0-9_]*)\"?",
        re.IGNORECASE,
    )
    names: set[str] = set()
    for sql_file in sorted((BACKEND_DIR / "migrations").glob("*.sql")):
        names.update(pattern.findall(sql_file.read_text(encoding="utf-8")))
    # schema_migrations is deliberately NOT swept. It is migration bookkeeping,
    # not test data: emptying it makes the next session re-apply migrations onto
    # a schema that already exists, which dies on "type already exists".
    return names


def _populated_tables(cur: psycopg.Cursor) -> set[str]:
    """Return only the knowledge tables that actually hold rows.

    Touching an empty table still costs storage I/O, so the suite only pays
    for the tables a test actually wrote to. Probing with EXISTS is
    effectively free on an empty table.

    The scope is deliberately limited to knowledge tables. This used to sweep
    every table in ``public``, which was wrong in two ways: it truncated
    ``alembic_version`` (leaving the application schema present but unmarked,
    so the next ``alembic upgrade`` died on ``DuplicateTable``), and it deleted
    the role and permission rows the application suite seeds. Cleaning only
    what these tests wrote keeps the two suites from sabotaging each other.
    """
    known = _knowledge_tables()
    cur.execute(
        """
        SELECT tablename FROM pg_tables
         WHERE schemaname = 'public'
           AND tablename <> 'alembic_version'
         ORDER BY tablename
        """
    )
    populated: set[str] = set()
    for row in cur.fetchall():
        name = row["tablename"]
        if name not in known:
            continue
        cur.execute(f'SELECT EXISTS (SELECT 1 FROM "{name}" LIMIT 1) AS present')
        if cur.fetchone()["present"]:
            populated.add(name)
    return populated


def _delete_order(cur: psycopg.Cursor, tables: set[str]) -> list[str] | None:
    """Order `tables` children-first so DELETE never trips a foreign key.

    Returns None when the populated subset contains a dependency cycle, which
    would make a single-pass DELETE impossible without deferring constraints.
    """
    cur.execute(
        """
        SELECT child.relname AS child, parent.relname AS parent
          FROM pg_constraint con
          JOIN pg_class child  ON child.oid  = con.conrelid
          JOIN pg_class parent ON parent.oid = con.confrelid
          JOIN pg_namespace n   ON n.oid     = child.relnamespace
         WHERE con.contype = 'f'
           AND n.nspname = 'public'
        """
    )
    # A table must be emptied only after everything pointing at it is empty.
    blockers: dict[str, set[str]] = {name: set() for name in tables}
    for row in cur.fetchall():
        child, parent = row["child"], row["parent"]
        if child in blockers and parent in blockers and child != parent:
            blockers[child].add(parent)

    ordered: list[str] = []
    remaining = dict(blockers)
    while remaining:
        ready = [name for name, deps in remaining.items() if not deps]
        if not ready:
            return None  # cycle among populated tables
        for name in ready:
            ordered.append(name)
            del remaining[name]
        for deps in remaining.values():
            deps.difference_update(ready)
    return ordered


def _owned_sequences(cur: psycopg.Cursor, tables: list[str]) -> list[str]:
    """Sequences owned by `tables`, so identity columns restart like TRUNCATE did."""
    cur.execute(
        """
        SELECT s.relname AS seq
          FROM pg_class s
          JOIN pg_namespace n ON n.oid = s.relnamespace
          JOIN pg_depend d   ON d.objid = s.oid AND d.deptype = 'a'
          JOIN pg_class t    ON t.oid = d.refobjid
         WHERE n.nspname = 'public'
           AND s.relkind = 'S'
           AND t.relname = ANY(%s)
        """,
        (tables,),
    )
    return [row["seq"] for row in cur.fetchall()]


def _clean_all(cur: psycopg.Cursor) -> None:
    """Empty every knowledge table, cheaply and in a referentially valid order.

    TRUNCATE is deliberately avoided: on this storage a single cascading
    TRUNCATE costs a relation-file sync for all 41 dependent tables even when
    they hold no rows, which made the suite take minutes. DELETE over only the
    populated tables is roughly fifty times faster and keeps every test
    isolated. Sequences are restarted explicitly to preserve the
    RESTART IDENTITY behaviour the suite previously relied on.
    """
    populated = _populated_tables(cur)
    if not populated:
        return

    order = _delete_order(cur, populated)
    if order is None:
        # Rare: mutually referencing populated tables. Fall back to the slow
        # but always-correct path rather than risking a half-cleaned database.
        cur.execute(
            "TRUNCATE TABLE " + ", ".join(f'"{t}"' for t in sorted(populated))
            + " RESTART IDENTITY CASCADE"
        )
        return

    for name in order:
        cur.execute(f'DELETE FROM "{name}"')
    for seq in _owned_sequences(cur, order):
        cur.execute(f'ALTER SEQUENCE "{seq}" RESTART')


def pytest_sessionstart(session: pytest.Session) -> None:
    _ensure_test_database()
    _apply_migrations()


def pytest_sessionfinish(session: pytest.Session, exitstatus: int) -> None:
    close_pool()


@pytest.fixture(scope="session", autouse=True)
def _pool():
    return init_pool(min_size=1, max_size=4)


@pytest.fixture()
def db(_pool):
    """The shared connection pool. Prefer the helpers below over raw access."""
    return _pool


@pytest.fixture()
def clean_db(db) -> Iterator[None]:
    """Empty all knowledge tables so each test starts from a known state."""
    with db.connection() as conn:
        with conn.cursor() as cur:
            _clean_all(cur)
        conn.commit()
    yield


@pytest.fixture()
def client(_pool):
    from fastapi.testclient import TestClient

    from plantdoctor_api.main import app

    with TestClient(app) as test_client:
        yield test_client


# ---------------------------------------------------------------------------
# Factory helpers. Each inserts only values that exist in an authoritative
# public source, and always records provenance. Nothing here is invented
# scientific content.
# ---------------------------------------------------------------------------


def insert_source(cur, key: str, name: str, source_type: str = "TAXONOMIC_DATABASE",
                  license_type: str = "CC_BY_4_0", url: str | None = None) -> int:
    cur.execute(
        """
        INSERT INTO sources (key, name, url, source_type, license, date_accessed)
        VALUES (%s, %s, %s, %s, %s, current_date)
        RETURNING id
        """,
        (key, name, url, source_type, license_type),
    )
    return cur.fetchone()["id"]


def insert_plant(cur, scientific_name: str, source_id: int | None = None,
                 description: str | None = None, verification_status: str = "VERIFIED",
                 common_name: str | None = None) -> int:
    cur.execute(
        """
        INSERT INTO plants (scientific_name, genus, family, description,
                            verification_status, taxonomic_source_id,
                            last_verified, is_accepted)
        VALUES (%s,
                split_part(%s, ' ', 1),
                NULL,
                %s, %s, %s, current_date, TRUE)
        RETURNING id
        """,
        (scientific_name, scientific_name, description, verification_status, source_id),
    )
    plant_id = cur.fetchone()["id"]
    if common_name:
        cur.execute(
            "INSERT INTO plant_names (plant_id, name, is_preferred) VALUES (%s, %s, TRUE)",
            (plant_id, common_name),
        )
    cur.execute("SELECT fn_reindex_plant(%s)", (plant_id,))
    return plant_id


def insert_disease(cur, code: str, name: str, source_id: int | None = None,
                   pathogen_scientific_name: str | None = None,
                   verification_status: str = "VERIFIED") -> int:
    cur.execute(
        """
        INSERT INTO diseases (code, name, pathogen_scientific_name,
                              verification_status, source_id, last_verified)
        VALUES (%s, %s, %s, %s, %s, current_date)
        RETURNING id
        """,
        (code, name, pathogen_scientific_name, verification_status, source_id),
    )
    return cur.fetchone()["id"]


def insert_symptom(cur, code: str, name: str, category: str = "VISUAL",
                   verification_status: str = "VERIFIED") -> int:
    cur.execute(
        "INSERT INTO symptoms (code, name, category, verification_status) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        (code, name, category, verification_status),
    )
    return cur.fetchone()["id"]


def insert_pest(cur, code: str, name: str, scientific_name: str | None = None,
                source_id: int | None = None) -> int:
    cur.execute(
        "INSERT INTO pests (code, name, scientific_name, source_id, last_verified) "
        "VALUES (%s, %s, %s, %s, current_date) RETURNING id",
        (code, name, scientific_name, source_id),
    )
    return cur.fetchone()["id"]


@pytest.fixture()
def src(db, clean_db) -> int:
    """A single verified source usable as provenance for other records."""
    with db.connection() as conn:
        with conn.cursor() as cur:
            source_id = insert_source(cur, "wfo", "World Flora Online (WFO)")
        conn.commit()
    return source_id
