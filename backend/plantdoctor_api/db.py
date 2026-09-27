"""PostgreSQL connection handling with a small pooled access layer."""

from __future__ import annotations

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .config import get_settings

logging.getLogger("plantdoctor").addHandler(logging.NullHandler())

log = logging.getLogger(__name__)

_pool: ConnectionPool | None = None


def init_pool(min_size: int = 1, max_size: int = 8) -> ConnectionPool:
    global _pool
    if _pool is None:
        settings = get_settings()
        _pool = ConnectionPool(
            conninfo=settings.dsn,
            min_size=min_size,
            max_size=max_size,
            kwargs={"row_factory": dict_row},
            open=True,
            name="plantdoctor",
        )
        _pool.wait(timeout=15)
        log.info("PostgreSQL pool opened (min=%s max=%s)", min_size, max_size)
    return _pool


def get_pool() -> ConnectionPool:
    return _pool if _pool is not None else init_pool()


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


@contextmanager
def connection() -> Iterator[psycopg.Connection]:
    with get_pool().connection() as conn:
        yield conn


@contextmanager
def transaction() -> Iterator[psycopg.Cursor]:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            yield cur


def query_all(sql: str, params: tuple[Any, ...] | dict[str, Any] | None = None) -> list[dict[str, Any]]:
    with transaction() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def query_one(sql: str, params: tuple[Any, ...] | dict[str, Any] | None = None) -> dict[str, Any] | None:
    with transaction() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def query_scalar(sql: str, params: tuple[Any, ...] | dict[str, Any] | None = None) -> Any:
    row = query_one(sql, params)
    if row is None:
        return None
    return next(iter(row.values()))


def execute(sql: str, params: tuple[Any, ...] | dict[str, Any] | None = None) -> int:
    with transaction() as cur:
        cur.execute(sql, params)
        return cur.rowcount
