"""Timezone-aware time helpers.

Every timestamp in the application is timezone-aware UTC. Naive datetimes are
never compared with aware ones, which is the usual source of "can't compare
offset-naive and offset-aware datetimes" outages.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta


def now_utc() -> datetime:
    return datetime.now(UTC)


def as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)


def in_seconds(seconds: float) -> datetime:
    return now_utc() + timedelta(seconds=seconds)


def in_days(days: float) -> datetime:
    return now_utc() + timedelta(days=days)


def is_expired(value: datetime | None) -> bool:
    if value is None:
        return False
    return (as_utc(value) or now_utc()) <= now_utc()


def seconds_until(value: datetime | None) -> int:
    if value is None:
        return 0
    delta = (as_utc(value) or now_utc()) - now_utc()
    return max(0, int(delta.total_seconds()))


__all__ = ["UTC", "as_utc", "in_days", "in_seconds", "is_expired", "now_utc", "seconds_until"]
