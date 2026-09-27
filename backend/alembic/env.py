"""Alembic environment.

Two rules make this safe to run next to a pre-existing knowledge base:

1. The URL comes from :mod:`app.core.config` (the environment), never from
   ``alembic.ini``.
2. ``include_object`` refuses to touch any table that is not owned by the
   application schema, so autogenerate can never propose dropping or altering a
   knowledge-base table.
"""

from __future__ import annotations

import os
import sys
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import engine_from_config, pool

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.config import get_settings  # noqa: E402
from app.core.env import ensure_env_loaded  # noqa: E402

ensure_env_loaded()
settings = get_settings()

from app.database.session import Base  # noqa: E402
from app.models import APPLICATION_TABLES, RESERVED_TABLES  # noqa: E402
import app.models  # noqa: E402,F401  (registers every table on Base.metadata)
import app.models.knowledge  # noqa: E402,F401  (resolves knowledge-base FK targets)

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Application tables only. The knowledge base has its own migration runner.
target_metadata = Base.metadata


def include_object(obj, name, type_, reflected, compare_to) -> bool:  # noqa: ANN001, ANN201
    """Autogenerate allow-list.

    A table that is not in :data:`APPLICATION_TABLES` is invisible to Alembic, so
    autogenerate can never propose dropping or altering a knowledge-base table.
    ``RESERVED_TABLES`` is excluded even if it were listed by mistake.
    """
    if type_ == "table":
        return name in APPLICATION_TABLES and name not in RESERVED_TABLES
    return True


def _database_url() -> str:
    return os.environ.get("ALEMBIC_DATABASE_URL") or settings.build_database_url()


def run_migrations_offline() -> None:
    """Emit SQL to stdout without connecting (used to review a migration)."""
    context.configure(
        url=_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=True,
        include_object=include_object,
        include_schemas=False,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    section = config.get_section(config.config_ini_section) or {}
    section["sqlalchemy.url"] = _database_url()

    connectable = engine_from_config(
        section, prefix="sqlalchemy.", poolclass=pool.NullPool
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
            include_object=include_object,
            include_schemas=False,
            # A knowledge-base migration must run first; fail loudly rather
            # than creating a table that references a missing one.
            transaction_per_migration=True,
        )
        with context.begin_transaction():
            context.run_migrations()
    connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
