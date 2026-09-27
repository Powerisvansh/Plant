"""Append-only audit trail.

Every sensitive action is written here. Design rules:

* :meth:`AuditService.record` stages the row inside the caller's transaction, so
  a privileged change cannot commit without the record that explains it.
* :meth:`AuditService.record_standalone` writes in its own transaction. Use it
  for events that must survive a rollback of the main work - a failed login, a
  rejected privileged request. If it shared the request's session, the rollback
  would erase the very record explaining the rollback.
* Nothing sensitive is stored. Passwords, tokens, OTPs, file bytes and request
  bodies never reach this table; see :data:`REDACTED_KEYS`.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from datetime import datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.logging_config import get_logger
from app.database.session import get_session_factory
from app.models.governance import AuditLog
from app.security.rbac import DANGEROUS_PERMISSIONS

logger = get_logger(__name__)

#: Keys whose value is replaced, at any nesting depth.
REDACTED_KEYS = frozenset(
    {
        "access_token",
        "api_key",
        "authorization",
        "body",
        "code",
        "cookie",
        "credentials",
        "current_password",
        "file_content",
        "id_token",
        "image",
        "new_password",
        "otp",
        "otp_code",
        "otp_digest",
        "password",
        "password_hash",
        "private_key",
        "refresh_token",
        "secret",
        "set_cookie",
        "token",
    }
)

REDACTED = "[REDACTED]"

#: 4 KiB keeps audit_logs useful without turning it into a second copy of the
#: users table.
MAX_CHANGES_BYTES = 4096
MAX_USER_AGENT_CHARS = 400
MAX_REASON_CHARS = 500


def redact(payload: Any, *, _depth: int = 0) -> Any:
    """Recursively replace secret-looking values."""
    if _depth > 6:
        return "..."
    if isinstance(payload, dict):
        return {
            key: (REDACTED if isinstance(key, str) and key.lower() in REDACTED_KEYS else redact(value, _depth=_depth + 1))
            for key, value in payload.items()
        }
    if isinstance(payload, (list, tuple)):
        return [redact(item, _depth=_depth + 1) for item in payload]
    if payload is None or isinstance(payload, (str, int, float, bool)):
        return payload
    if isinstance(payload, (uuid.UUID, datetime)):
        return payload.isoformat() if isinstance(payload, datetime) else str(payload)
    return str(payload)


def _fit_changes(changes: dict[str, Any] | None) -> dict[str, Any] | None:
    """Redact, then bound the size.

    On overflow the *keys* are kept and the values dropped: the shape of a
    change is the useful part, the payload is not.
    """
    if changes is None:
        return None
    safe = redact(changes)
    encoded = json.dumps(safe, default=str, sort_keys=True)
    if len(encoded.encode("utf-8")) <= MAX_CHANGES_BYTES:
        return safe
    return {
        "_truncated": True,
        "_bytes": len(encoded.encode("utf-8")),
        "keys": sorted(str(key) for key in safe),
    }


class AuditService:
    """Stateless writer for ``audit_logs``."""

    @staticmethod
    def record(
        session: Session,
        *,
        action: str,
        resource_type: str,
        actor_user_id: uuid.UUID | None = None,
        actor_email: str | None = None,
        actor_roles: Sequence[str] | None = None,
        resource_id: str | int | None = None,
        http_method: str | None = None,
        route: str | None = None,
        status_code: int | None = None,
        changes: dict[str, Any] | None = None,
        reason: str | None = None,
        is_dangerous: bool = False,
        ip_address: str | None = None,
        user_agent: str | None = None,
        request_id: str | None = None,
    ) -> AuditLog:
        """Stage an audit row in the caller's transaction."""
        entry = AuditLog(
            actor_user_id=actor_user_id,
            actor_email=(actor_email or "")[:320] or None,
            actor_roles=list(actor_roles) if actor_roles else None,
            action=action[:80],
            resource_type=resource_type[:60],
            resource_id=str(resource_id)[:80] if resource_id is not None else None,
            http_method=http_method[:10] if http_method else None,
            route=route[:200] if route else None,
            status_code=status_code,
            changes=_fit_changes(changes),
            reason=reason[:MAX_REASON_CHARS] if reason else None,
            is_dangerous=is_dangerous or action in DANGEROUS_PERMISSIONS,
            ip_address=ip_address,
            user_agent=user_agent[:MAX_USER_AGENT_CHARS] if user_agent else None,
            request_id=request_id[:64] if request_id else None,
        )
        session.add(entry)
        return entry

    @staticmethod
    def record_standalone(**kwargs: Any) -> AuditLog | None:
        """Write an audit row in its own transaction.

        Never raises. A logging failure must not turn a security-relevant path
        into a 500, but it is logged loudly.
        """
        try:
            session = get_session_factory()()
            try:
                entry = AuditService.record(session, **kwargs)
                session.commit()
                return entry
            finally:
                session.close()
        except Exception:  # pragma: no cover - defensive
            logger.exception(
                "audit_write_failed",
                extra={"audit_action": kwargs.get("action")},
            )
            return None

    @staticmethod
    def record_failure(
        *,
        action: str,
        resource_type: str,
        status_code: int = 403,
        **kwargs: Any,
    ) -> AuditLog | None:
        """Record a *denied* attempt. A rejected privileged call is evidence."""
        return AuditService.record_standalone(
            action=action,
            resource_type=resource_type,
            status_code=status_code,
            is_dangerous=True,
            changes={"outcome": "denied"},
            **kwargs,
        )

    @staticmethod
    def query(
        session: Session,
        *,
        actor_user_id: uuid.UUID | None = None,
        action: str | None = None,
        resource_type: str | None = None,
        resource_id: str | None = None,
        is_dangerous: bool | None = None,
        since: datetime | None = None,
        until: datetime | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> Sequence[AuditLog]:
        stmt = select(AuditLog)
        if actor_user_id is not None:
            stmt = stmt.where(AuditLog.actor_user_id == actor_user_id)
        if action:
            stmt = stmt.where(AuditLog.action == action)
        if resource_type:
            stmt = stmt.where(AuditLog.resource_type == resource_type)
        if resource_id:
            stmt = stmt.where(AuditLog.resource_id == resource_id)
        if is_dangerous is not None:
            stmt = stmt.where(AuditLog.is_dangerous.is_(is_dangerous))
        if since is not None:
            stmt = stmt.where(AuditLog.occurred_at >= since)
        if until is not None:
            stmt = stmt.where(AuditLog.occurred_at <= until)
        return (
            session.execute(
                stmt.order_by(AuditLog.occurred_at.desc(), AuditLog.id.desc())
                .limit(limit)
                .offset(offset)
            )
            .scalars()
            .all()
        )


@contextmanager
def audited(session: Session, action: str, **kwargs: Any) -> Iterator[AuditLog]:
    """Stage an audit row that commits together with the caller's work."""
    entry = AuditService.record(session, action=action, **kwargs)
    yield entry
