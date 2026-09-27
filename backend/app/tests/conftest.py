"""Fixtures for the new application's own tests.

These sit alongside ``tests/conftest.py``, which owns the knowledge-base suite.
The two deliberately do not share fixtures: the knowledge tests insert raw rows
through psycopg and clean up with a dependency-ordered DELETE, while the
application tests go through SQLAlchemy and the HTTP API. Mixing them would
mean two different notions of "a clean database" in one session.

Everything here runs against ``plantdoctor_test``. ``tests/conftest.py`` refuses
to start unless the database name ends in ``_test``, and that check runs at
collection time before this file is imported.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if BACKEND_DIR not in os.sys.path:
    os.sys.path.insert(0, BACKEND_DIR)


def _redirect_to_test_database() -> str:
    """Point every later database connection at the throwaway database.

    This has to happen at *import* time, before any application module builds
    an engine, and it has to rewrite ``DATABASE_URL`` specifically. The engine
    reads ``DATABASE_URL`` first and only falls back to
    ``PLANTDOCTOR_DB_NAME``, and the env file sets ``DATABASE_URL`` to the
    production database. Setting only the name therefore leaves the engine
    connected to production while Alembic creates its tables somewhere else -
    the failure mode this whole guard exists to prevent.

    ``os.environ`` is set before the engine exists, and ``ensure_env_loaded``
    uses setdefault semantics, so the file cannot put it back.
    """
    from app.core.env import ensure_env_loaded

    ensure_env_loaded()
    from app.core.config import Settings

    url = Settings().build_database_url(test=True)
    name = url.rsplit("/", 1)[-1].split("?", 1)[0]
    if not name.endswith("_test"):
        raise RuntimeError(
            f"Refusing to run application tests against {name!r}: the database "
            "name must end in '_test'."
        )
    os.environ["DATABASE_URL"] = url
    os.environ["PLANTDOCTOR_DB_NAME"] = name
    return url


TEST_DATABASE_URL = _redirect_to_test_database()


def _ensure_test_database() -> None:
    """Create the throwaway database if it does not exist yet.

    ``tests/conftest.py`` does this too, but in ``pytest_sessionstart`` - and
    ``pytest_configure`` runs first. Without this, ``pytest app/tests`` on a
    machine that has never run the suite dies with "database does not exist"
    before collecting a single test. Connecting to the maintenance database is
    the only way to issue CREATE DATABASE.
    """
    import psycopg
    from sqlalchemy.engine import make_url

    url = make_url(TEST_DATABASE_URL)
    name = url.database or ""
    if not name.endswith("_test"):
        raise RuntimeError(f"Refusing to create non-test database {name!r}")
    dsn = (
        f"host={url.host} port={url.port or 5432} dbname=postgres "
        f"user={url.username} password={url.password or ''}"
    )
    with psycopg.connect(dsn, autocommit=True) as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (name,))
        if cur.fetchone() is not None:
            return
        try:
            cur.execute(f'CREATE DATABASE "{name}"')
        except psycopg.errors.InsufficientPrivilege as exc:
            raise RuntimeError(
                f"The test database {name!r} does not exist and the role "
                f"{url.username!r} may not create databases. Create it once "
                "with an administrative role, or grant CREATEDB:\n"
                f'  CREATE DATABASE "{name}";'
            ) from exc


_ensure_test_database()

from app.core.config import get_settings  # noqa: E402
from app.database.session import get_session_factory  # noqa: E402

#: Argon2 is deliberately slow. Running the real cost parameters in a unit-test
#: suite turns a 30-second run into several minutes, so the tests use the
#: cheapest parameters that still exercise the real algorithm.
TEST_ENV_OVERRIDES = {
    "ARGON2_TIME_COST": 1,
    "ARGON2_MEMORY_COST_KIB": 8192,
    "ARGON2_PARALLELISM": 1,
    "ACCESS_TOKEN_TTL_MINUTES": 15,
    "REFRESH_TOKEN_TTL_DAYS": 7,
    "RATE_LIMIT_ENABLED": "false",
    "ENVIRONMENT": "test",
}


def _alembic_state() -> tuple[str | None, bool]:
    """Return ``(current revision, application schema present)``.

    ``revision`` is ``None`` when Alembic has never stamped this database, and
    the boolean reports whether any application table already exists. Both are
    needed to tell "fresh database" apart from "schema present but unmarked".
    """
    from sqlalchemy import inspect, text

    from app.database.session import get_engine
    from app.models import APPLICATION_TABLES

    engine = get_engine()
    with engine.connect() as conn:
        has_version_table = bool(
            conn.execute(
                text("SELECT to_regclass('public.alembic_version') IS NOT NULL")
            ).scalar()
        )
        revision: str | None = None
        if has_version_table:
            revision = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
    inspector = inspect(engine)
    app_tables = [t for t in inspector.get_table_names() if t in APPLICATION_TABLES]
    return revision, bool(app_tables)


def _apply_knowledge_migrations() -> None:
    """Apply the legacy knowledge-base schema that the app tables reference.

    The application schema is intentionally allowed to declare foreign keys into
    the knowledge tables (for example ``sources.id``), but those tables do not
    exist until the SQL migration stack runs. The production stack does this in
    ``docker-compose.yml`` before Alembic, and the test bootstrap should match
    that ordering.
    """
    import subprocess
    import sys

    repo_root = Path(__file__).resolve().parents[3]
    script = repo_root / "scripts" / "migrate.py"
    subprocess.run(
        [sys.executable, str(script), "up"],
        cwd=str(repo_root),
        check=True,
        env={
            **os.environ,
            "PYTHONPATH": str(repo_root / "backend") + os.pathsep + os.environ.get("PYTHONPATH", ""),
        },
    )


def _apply_alembic() -> None:
    """Bring the application schema up to head in the test database.

    Normally this is a plain ``upgrade``. The database can also arrive with the
    application tables present but no Alembic marker, which happens if some
    other tooling truncated ``alembic_version``. Replaying ``0001`` then fails
    on ``DuplicateTable`` and the whole session dies before a single test
    runs, so that case is repaired by stamping head instead.
    """
    from alembic import command
    from alembic.config import Config

    cfg = Config(os.path.join(BACKEND_DIR, "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(BACKEND_DIR, "alembic"))
    cfg.set_main_option("sqlalchemy.url", TEST_DATABASE_URL)

    revision, schema_present = _alembic_state()
    if schema_present and revision is None:
        command.stamp(cfg, "head")
        return
    command.upgrade(cfg, "head")


def _seed_roles() -> None:
    """Make sure roles and permission links exist in the test database.

    Uses the same idempotent function the ``seed-roles`` CLI command calls, so a
    test that depends on a permission code depends on exactly the thing
    production reconciliation produces.
    """
    from app.database.session import session_scope
    from app.services.role_service import seed_roles_and_permissions

    with session_scope() as session:
        seed_roles_and_permissions(session)


def pytest_configure(config: pytest.Config) -> None:
    for key, value in TEST_ENV_OVERRIDES.items():
        os.environ.setdefault(key, str(value))
    # The app's settings object may already be built by an earlier import.
    get_settings.cache_clear()
    _apply_knowledge_migrations()
    _apply_alembic()
    _seed_roles()


@pytest.fixture(scope="session")
def app():
    from app.main import create_app

    return create_app()


@pytest.fixture()
def client(app) -> Iterator:
    from fastapi.testclient import TestClient

    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture()
def db() -> Iterator:
    session = get_session_factory()()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


#: Per-test application tables, children first, so a single pass of DELETEs is
#: referentially valid. The knowledge tables and the role/permission reference
#: data are deliberately excluded: the knowledge tables are shared and
#: read-only here, and roles are seeded once per session.
#:
#: This is a plain DELETE rather than ``TRUNCATE ... CASCADE`` because CASCADE
#: reaches the 83 knowledge tables that the application foreign-keys point at,
#: and truncating those forces a relation-file sync for every one of them even
#: when they are empty. That made a single reset take seconds and the suite look
#: like it had hung. ``tests/conftest.py`` documents the same trade-off.
_APP_TABLES = (
    "login_attempts",
    "refresh_tokens",
    "user_state_versions",
    "user_sessions",
    "user_roles",
    "user_profiles",
    "audit_logs",
    "users",
)


@pytest.fixture()
def clean_app(client) -> Iterator:
    """Empty the per-test application tables before and after each test.

    The suite is function-scoped, so a test that creates a user cannot leak into
    the next one. Resetting before *and* after means a failing test cannot
    poison its successor either.
    """
    def _reset() -> None:
        from sqlalchemy import text

        session = get_session_factory()()
        try:
            for table in _APP_TABLES:
                session.execute(text(f'DELETE FROM "{table}"'))
            session.commit()
        finally:
            session.close()

    _reset()
    yield
    _reset()


@pytest.fixture()
def password() -> str:
    """Meets every policy rule without being memorable-looking."""
    return "Garden-Mango-47!"


@pytest.fixture()
def make_user(clean_app, password):
    """Create a user straight through the service, bypassing registration.

    Real registration creates a ``PENDING_VERIFICATION`` account that cannot log
    in, which is correct behaviour but makes it impossible to test login without
    also implementing OTP. These fixtures mark the account verified so the auth
    mechanics can be tested in isolation; the OTP flow gets its own tests later.
    """
    from app.core.timeutils import now_utc
    from app.models.enums import UserStatus
    from app.repositories.user_repository import UserRepository
    from app.security.passwords import hash_password
    from app.models.identity import User
    from app.database.session import session_scope

    created: list[User] = []

    def _make(
        *,
        email: str | None = None,
        phone: str | None = None,
        full_name: str = "Test Grower",
        role: str = "USER",
        verified: bool = True,
        active: bool = True,
        with_password: bool = True,
        user_status: UserStatus | None = None,
    ) -> User:
        from app.core.identifiers import normalise_email, normalise_phone

        email_norm = normalise_email(email) if email else None
        phone_e164 = None
        if phone:
            phone_e164, _ = normalise_phone(phone)
        now = now_utc()
        with session_scope() as session:
            user = User(
                full_name=full_name,
                email=email,
                email_normalised=email_norm,
                phone_e164=phone_e164,
                phone_display=phone,
                password_hash=hash_password(password) if with_password else "!unusable",
                password_changed_at=now,
                status=user_status
                or (UserStatus.ACTIVE if verified else UserStatus.PENDING_VERIFICATION),
                email_verified_at=now if (verified and email_norm) else None,
                phone_verified_at=now if (verified and phone_e164) else None,
                is_active=active,
                terms_accepted_at=now,
            )
            session.add(user)
            session.flush()
            repo = UserRepository(session)
            role_row = repo.get_role(role)
            assert role_row is not None, f"role {role} missing; run seed-roles"
            repo.assign_role(user, role_row)
            user.is_staff = role.upper() in {"ADMIN", "SUPER_ADMIN"}
            user.is_superuser = role.upper() == "SUPER_ADMIN"
            session.flush()
            session.expunge(user)
            created.append(user)
            return user

    return _make


@pytest.fixture()
def auth_client(client, make_user, password):
    """A TestClient already carrying a valid access token.

    Returns an object with the client, the user and the token, so a test can
    assert on identity without re-deriving it.
    """
    from dataclasses import dataclass

    @dataclass
    class LoggedIn:
        client: object
        user: object
        access_token: str
        refresh_token: str
        session_id: str
        password: str

        def auth(self) -> dict[str, str]:
            return {"Authorization": f"Bearer {self.access_token}"}

    def _login(
        *,
        email: str | None = None,
        phone: str | None = None,
        role: str = "USER",
        full_name: str = "Test Grower",
        **kwargs,
    ) -> LoggedIn:
        address = email or phone or f"user-{uuid.uuid4().hex[:10]}@example.test"
        user = make_user(email=address, phone=phone, role=role, full_name=full_name, **kwargs)
        identifier = address
        response = client.post(
            "/api/v1/auth/login",
            json={"identifier": identifier, "password": password},
        )
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        return LoggedIn(
            client=client,
            user=user,
            access_token=data["access_token"],
            refresh_token=data["refresh_token"],
            session_id=data["session_id"],
            password=password,
        )

    return _login


@pytest.fixture()
def unique_email():
    def _make(prefix: str = "user") -> str:
        return f"{prefix}-{uuid.uuid4().hex[:12]}@example.test"

    return _make
