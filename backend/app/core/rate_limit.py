"""Rate limiting.

A fixed-window counter per (rule, identity) pair. Two interchangeable
backends:

* ``memory``  - default, dependency free, per-process. Correct for the
  single-process desktop server.
* ``redis``   - shared, survives restarts and works across multiple workers.
  Enabled by setting ``REDIS_URL``; the server degrades to memory with a
  warning rather than failing when Redis is unreachable.

Identity is the authenticated user id when a token is present, otherwise the
client IP. A logged-in user is never throttled by someone else's traffic on
the same NAT address, which matters because every phone on a home Wi-Fi shares
one public address.
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any, Protocol

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.config import Settings
from app.core.errors import ErrorCode, RateLimitedError, error_payload
from app.core.logging_config import get_logger

log = get_logger("plantdoctor.ratelimit")


@dataclass(frozen=True)
class Rule:
    """One limit: at most ``limit`` requests per ``window_seconds``."""

    name: str
    limit: int
    window_seconds: int
    #: Only count requests whose path starts with one of these prefixes.
    paths: tuple[str, ...] = ()

    def applies_to(self, path: str) -> bool:
        return not self.paths or any(path.startswith(p) for p in self.paths)


class RateLimitBackend(Protocol):
    def hit(self, key: str, *, limit: int, window_seconds: int) -> tuple[int, int]:
        """Record a request. Returns ``(count, retry_after_seconds)``."""

    def reset(self, key: str) -> None: ...

    def healthy(self) -> bool: ...


class MemoryRateLimitBackend:
    """In-process sliding window. Thread safe."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._windows: dict[str, deque[float]] = defaultdict(deque)
        self._last_sweep = time.monotonic()

    def hit(self, key: str, *, limit: int, window_seconds: int) -> tuple[int, int]:
        now = time.monotonic()
        with self._lock:
            self._sweep(now)
            window = self._windows[key]
            while window and now - window[0] >= window_seconds:
                window.popleft()
            if len(window) >= limit:
                retry_after = max(1, int(window_seconds - (now - window[0])) + 1)
                return len(window), retry_after
            window.append(now)
            return len(window), 0

    def _sweep(self, now: float) -> None:
        # Amortised cleanup so a long-running process cannot grow unbounded.
        if now - self._last_sweep < 60:
            return
        self._last_sweep = now
        stale = [k for k, v in self._windows.items() if not v or now - v[-1] > 3600]
        for key in stale:
            del self._windows[key]

    def reset(self, key: str) -> None:
        with self._lock:
            self._windows.pop(key, None)

    def healthy(self) -> bool:
        return True


class RedisRateLimitBackend:
    """Shared counter. Uses INCR + EXPIRE, which is atomic enough for a limit."""

    def __init__(self, url: str) -> None:
        import redis  # imported lazily so redis stays optional

        self._client = redis.Redis.from_url(url, socket_timeout=2, socket_connect_timeout=2)

    def hit(self, key: str, *, limit: int, window_seconds: int) -> tuple[int, int]:
        pipe = self._client.pipeline()
        pipe.incr(key)
        pipe.ttl(key)
        count, ttl = pipe.execute()
        if ttl is None or ttl < 0:
            self._client.expire(key, window_seconds)
            ttl = window_seconds
        if int(count) > limit:
            return int(count), max(1, int(ttl))
        return int(count), 0

    def reset(self, key: str) -> None:
        self._client.delete(key)

    def healthy(self) -> bool:
        try:
            return bool(self._client.ping())
        except Exception:
            return False


_backend: RateLimitBackend | None = None
_backend_kind = "memory"


def get_backend(settings: Settings | None = None) -> tuple[RateLimitBackend, str]:
    global _backend, _backend_kind
    if _backend is not None:
        return _backend, _backend_kind
    settings = settings or _settings()
    if settings.RATE_LIMIT_BACKEND == "redis" or settings.effective_redis_url:
        try:
            _backend = RedisRateLimitBackend(settings.effective_redis_url)
            _backend.healthy()
            _backend_kind = "redis"
            log.info("rate_limit_backend=redis")
            return _backend, _backend_kind
        except Exception as exc:  # pragma: no cover - optional dependency path
            log.warning(
                "redis_unavailable_falling_back_to_memory backend=%s", type(exc).__name__
            )
    _backend = MemoryRateLimitBackend()
    _backend_kind = "memory"
    return _backend, _backend_kind


def _settings() -> Settings:
    from app.core.config import get_settings

    return get_settings()


def default_rules(settings: Settings) -> list[Rule]:
    return [
        Rule("login", settings.RATE_LIMIT_LOGIN_PER_MINUTE, 60, ("/api/v1/auth/login",)),
        Rule(
            "otp_request",
            settings.RATE_LIMIT_OTP_PER_HOUR,
            3600,
            (
                "/api/v1/auth/request-otp",
                "/api/v1/auth/resend-otp",
                "/api/v1/auth/forgot-password",
            ),
        ),
        Rule(
            "otp_verify",
            settings.RATE_LIMIT_OTP_PER_HOUR,
            3600,
            ("/api/v1/auth/verify-otp",),
        ),
        Rule("upload", settings.RATE_LIMIT_UPLOAD_PER_HOUR, 3600, ("/api/v1/diagnosis",)),
        Rule("api", settings.RATE_LIMIT_API_PER_MINUTE, 60),
    ]


def identity_for(request: Request) -> str:
    """Prefer the authenticated subject; fall back to the client address."""
    user_id = getattr(request.state, "auth_user_id", None)
    if user_id:
        return f"user:{user_id}"
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return f"ip:{forwarded.split(',')[0].strip()}"
    client = request.client
    return f"ip:{client.host}" if client else "ip:unknown"


def check(rules: list[Rule], key: str, path: str) -> None:
    """Raise RateLimitedError when any rule matching ``path`` is exhausted."""
    backend, _ = get_backend()
    for rule in rules:
        if not rule.applies_to(path):
            continue
        count, retry_after = backend.hit(
            f"{rule.name}:{key}", limit=rule.limit, window_seconds=rule.window_seconds
        )
        if retry_after:
            log.warning(
                "rate_limit_exceeded rule=%s identity=%s retry_after=%s", rule.name, key, retry_after
            )
            from app.core.errors import RateLimitedError

            raise RateLimitedError(
                f"Too many {rule.name.replace('_', ' ')} requests. "
                f"Please wait {retry_after} seconds and try again.",
                retry_after=retry_after,
                details={"rule": rule.name, "limit": rule.limit, "window_seconds": rule.window_seconds},
            )


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Global limiter applied to every request.

    It sits outside the route handlers, so the identity is the client address
    for anonymous calls. Authenticated routes additionally enforce per-account
    limits at the service layer (see ``app/services/auth_service.py``), which is
    the layer that can see the verified subject.
    """

    def __init__(self, app, *, settings: Settings) -> None:
        super().__init__(app)
        self.settings = settings
        self.rules = default_rules(settings)

    async def dispatch(
        self, request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        if not self.settings.RATE_LIMIT_ENABLED or request.method == "OPTIONS":
            return await call_next(request)
        try:
            check(self.rules, identity_for(request), request.url.path)
        except RateLimitedError as exc:
            return JSONResponse(
                status_code=429,
                content=error_payload(
                    exc.code,
                    exc.message,
                    request_id=getattr(request.state, "request_id", None),
                    details=exc.details or {},
                ),
                headers=exc.headers or None,
            )
        return await call_next(request)


def reset_identity(key: str) -> None:
    """Clear counters after a successful login/OTP verification."""
    backend, _ = get_backend()
    backend.reset(f"login:{key}")
    backend.reset(f"otp_verify:{key}")


def backend_status() -> dict[str, Any]:
    backend, kind = get_backend()
    return {"backend": kind, "healthy": backend.healthy()}
