"""Structured logging.

Emits one JSON object per line in production (greppable by ``request_id``) and a
readable human format in development. A redaction filter is installed on the
root logger so a stray ``%(password)s`` in any library can never leak a secret
into the log file.
"""

from __future__ import annotations

import json
import logging
import logging.config
import sys
import time
import uuid
from contextvars import ContextVar
from typing import Any

request_id_var: ContextVar[str | None] = ContextVar("request_id", default=None)
user_id_var: ContextVar[str | None] = ContextVar("user_id", default=None)

#: Log-record keys whose values are replaced with a redaction marker.
SENSITIVE_KEYS = frozenset(
    {
        "password",
        "new_password",
        "current_password",
        "password_hash",
        "hashed_password",
        "otp",
        "otp_code",
        "otp_hash",
        "code",
        "token",
        "access_token",
        "refresh_token",
        "id_token",
        "authorization",
        "secret",
        "jwt_secret",
        "jwt_refresh_secret",
        "api_key",
        "smtp_password",
        "db_password",
        "database_url",
        "dsn",
        "session_key",
        "cookie",
        "set-cookie",
        "x-api-key",
    }
)

REDACTED = "***REDACTED***"


class RedactionFilter(logging.Filter):
    """Blank out sensitive values on the way to any handler."""

    def filter(self, record: logging.LogRecord) -> bool:
        for key in SENSITIVE_KEYS:
            if key in record.__dict__:
                record.__dict__[key] = REDACTED
        if record.args and isinstance(record.args, dict):
            record.args = {k: (REDACTED if k in SENSITIVE_KEYS else v) for k, v in record.args.items()}
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created))
            + f".{int(record.msecs):03d}Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        request_id = request_id_var.get()
        if request_id:
            payload["request_id"] = request_id
        user_id = user_id_var.get()
        if user_id:
            payload["user_id"] = user_id
        for key, value in record.__dict__.items():
            if key in _STANDARD_ATTRS or key.startswith("_"):
                continue
            if key in SENSITIVE_KEYS:
                payload[key] = REDACTED
                continue
            if isinstance(value, (str, int, float, bool, list, dict, type(None))):
                payload[key] = value
            else:
                payload[key] = repr(value)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False, default=str)


_STANDARD_ATTRS = frozenset(
    {
        "args", "asctime", "created", "exc_info", "exc_text", "filename", "funcName",
        "levelname", "levelno", "lineno", "module", "msecs", "msg", "name", "pathname",
        "process", "processName", "relativeCreated", "stack_info", "thread",
        "threadName", "taskName",
    }
)


class TextFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        prefix = f"{record.levelname:<7} {record.name:<28}"
        request_id = request_id_var.get()
        if request_id:
            prefix += f" [{request_id[:8]}]"
        base = f"{prefix} {record.getMessage()}"
        if record.exc_info:
            base += "\n" + self.formatException(record.exc_info)
        return base


def new_request_id() -> str:
    return uuid.uuid4().hex


def setup_logging(
    level: str = "INFO",
    *,
    fmt: str = "json",
    log_file: str = "",
) -> None:
    """Idempotently configure the root logger."""
    handler: logging.Handler
    if log_file:
        handler = logging.FileHandler(log_file, encoding="utf-8")
    else:
        handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter() if fmt == "json" else TextFormatter())
    handler.addFilter(RedactionFilter())

    root = logging.getLogger()
    for existing in list(root.handlers):
        root.removeHandler(existing)
    root.addHandler(handler)
    root.setLevel(getattr(logging, level.upper(), logging.INFO))

    # Third-party libraries are noisy at DEBUG and may echo request payloads.
    for noisy in ("uvicorn.access", "sqlalchemy.engine", "httpx", "httpcore", "botocore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)
