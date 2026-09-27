"""SQLAlchemy engine, session factory and declarative base.

The engine is shared by the new application domain (ORM) and by the knowledge
base read repositories (parameterised Core SQL). The existing
``plantdoctor_api`` psycopg pool is intentionally left untouched so its tests
and behaviour are unchanged; both talk to the same PostgreSQL database.
"""

from __future__ import annotations

import time
from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine, event, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import Settings, get_settings
from app.core.logging_config import get_logger

log = get_logger("plantdoctor.database")


class Base(DeclarativeBase):
    """Declarative base for every table owned by the new application."""

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        pk = getattr(self, "id", None)
        return f"<{type(self).__name__} id={pk}>"


_engine: Engine | None = None
_SessionFactory: sessionmaker[Session] | None = None


def _create_engine(settings: Settings, *, url: str | None = None) -> Engine:
    dsn = url or settings.build_database_url()
    connect_args: dict[str, object] = {"connect_timeout": 10}
    if settings.ENVIRONMENT == "test":
        connect_args["application_name"] = "plantdoctor-test"
    engine = create_engine(
        dsn,
        pool_pre_ping=True,
        pool_size=settings.DB_POOL_SIZE,
        max_overflow=settings.DB_MAX_OVERFLOW,
        pool_timeout=settings.DB_POOL_TIMEOUT,
        pool_recycle=1800,
        echo=settings.DB_ECHO,
        future=True,
        connect_args=connect_args,
    )

    @event.listens_for(engine, "connect")
    def _set_session_defaults(dbapi_connection, _record) -> None:  # noqa: ANN001
        with dbapi_connection.cursor() as cur:
            # Fail fast and safely on malformed identifiers rather than
            # silently truncating, and keep every timestamp unambiguous.
            cur.execute("SET TIME ZONE 'UTC'")
            cur.execute("SET statement_timeout = '60s'")
            cur.execute("SET idle_in_transaction_session_timeout = '120s'")

    return engine


def get_engine() -> Engine:
    global _engine
    if _engine is None:
        settings = get_settings()
        _engine = _create_engine(settings)
    return _engine


def get_session_factory() -> sessionmaker[Session]:
    global _SessionFactory
    if _SessionFactory is None:
        _SessionFactory = sessionmaker(
            bind=get_engine(),
            autoflush=False,
            autocommit=False,
            expire_on_commit=False,
            future=True,
        )
    return _SessionFactory


def wait_for_database(
    *,
    url: str | None = None,
    attempts: int | None = None,
    delay: float | None = None,
) -> None:
    """Block until PostgreSQL answers, so container start order never matters."""
    settings = get_settings()
    attempts = attempts or settings.DB_CONNECT_RETRIES
    delay = delay if delay is not None else settings.DB_CONNECT_RETRY_DELAY
    engine = get_engine()
    last: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            log.info("database_ready", extra={"attempt": attempt})
            return
        except OperationalError as exc:  # pragma: no cover - startup path
            last = exc
            log.warning(
                "database_unavailable attempt=%s/%s", attempt, attempts
            )
            if attempt < attempts:
                time.sleep(delay)
    raise RuntimeError(f"PostgreSQL did not become ready after {attempts} attempts: {last}")


@contextmanager
def session_scope() -> Iterator[Session]:
    """Transactional scope for CLI jobs and background work."""
    session = get_session_factory()()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def get_db() -> Iterator[Session]:
    """FastAPI dependency: one session per request, committed by the route."""
    session = get_session_factory()()
    try:
        yield session
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def dispose_engine() -> None:
    global _engine, _SessionFactory
    if _engine is not None:
        _engine.dispose()
        _engine = None
        _SessionFactory = None
