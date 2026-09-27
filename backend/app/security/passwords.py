"""Password hashing and password strength policy.

Argon2id is the default. It is the winner of the Password Hashing Competition,
is memory-hard, and is the only algorithm in :mod:`argon2` that is both
side-channel and GPU resistant.

Parameters live in configuration so a stronger desktop can raise the memory cost
without a code change. The encoded hash records the parameters it was created
with, so raising them later does not invalidate existing passwords.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import unicodedata

from argon2 import PasswordHasher, Type
from argon2.exceptions import (
    HashingError,
    InvalidHashError,
    VerificationError,
    VerifyMismatchError,
)

from app.core.config import Settings, get_settings
from app.core.errors import AppError, ErrorCode

# Deliberately not enforced: upper/lower/digit/symbol classes. NIST SP 800-63B
# and the OWASP password guidance both treat composition rules as a weak
# proxy that pushes users toward predictable substitutions. Length, a breach
# blocklist and no composition rules is the stronger policy.
_COMMON_PASSWORDS = frozenset(
    {
        "password",
        "password1",
        "password123",
        "passw0rd",
        "12345678",
        "123456789",
        "1234567890",
        "qwertyuiop",
        "qwerty123",
        "iloveyou",
        "letmein123",
        "admin12345",
        "welcome123",
        "monkey1234",
        "sunshine123",
        "princess123",
        "football123",
        "baseball123",
        "trustno123",
        "dragon12345",
        "sunshine1",
        "plantdoctor",
        "plantdoctor1",
        "plantdoctor123",
    }
)

#: Sequences a human types without thinking.
_SEQUENCES = re.compile(r"(0123|1234|2345|3456|4567|5678|6789|abcd|qwer|asdf|zxcv)", re.I)
_REPEATS = re.compile(r"(.)\1{3,}")


class PasswordPolicyError(AppError):
    status_code = 422
    code = ErrorCode.WEAK_PASSWORD
    message = "The password does not meet the minimum requirements."


def _hasher(settings: Settings | None = None) -> PasswordHasher:
    settings = settings or get_settings()
    return PasswordHasher(
        time_cost=settings.ARGON2_TIME_COST,
        memory_cost=settings.ARGON2_MEMORY_COST_KIB,
        parallelism=settings.ARGON2_PARALLELISM,
        hash_len=settings.ARGON2_HASH_LEN,
        salt_len=16,
        type=Type.ID,
    )


def hash_password(password: str, *, settings: Settings | None = None) -> str:
    """Return an Argon2id PHC string. The plaintext is never stored."""
    hasher = _hasher(settings)
    try:
        return hasher.hash(password)
    except HashingError as exc:  # pragma: no cover - resource exhaustion
        raise AppError(
            "Password hashing failed. The server may be short of memory.",
            code=ErrorCode.INTERNAL_ERROR,
            status_code=500,
        ) from exc


def verify_password(password: str, encoded_hash: str) -> bool:
    """Constant-time verification. Returns False for any malformed hash."""
    if not encoded_hash:
        return False
    try:
        return bool(_hasher().verify(encoded_hash, password))
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def needs_rehash(encoded_hash: str, *, settings: Settings | None = None) -> bool:
    """True when a stored hash uses weaker parameters than the current policy.

    Called on a successful login so cost parameters can be raised over time
    without forcing every user to change their password.
    """
    settings = settings or get_settings()
    try:
        return _hasher(settings).check_needs_rehash(encoded_hash)
    except InvalidHashError:
        return True


def validate_password_strength(
    password: str,
    *,
    email: str | None = None,
    full_name: str | None = None,
    settings: Settings | None = None,
) -> None:
    """Raise :class:`PasswordPolicyError` unless the password is acceptable."""
    settings = settings or get_settings()
    problems: list[str] = []

    if len(password) < settings.PASSWORD_MIN_LENGTH:
        problems.append(f"at least {settings.PASSWORD_MIN_LENGTH} characters")
    if len(password) > settings.PASSWORD_MAX_LENGTH:
        problems.append(f"at most {settings.PASSWORD_MAX_LENGTH} characters")
    if password.lower() in _COMMON_PASSWORDS:
        problems.append("it is one of the most commonly guessed passwords")
    if _SEQUENCES.search(password):
        problems.append("it contains a keyboard or alphabet sequence")
    if _REPEATS.search(password):
        problems.append("it repeats the same character four or more times")
    if len(set(password)) < 5:
        problems.append("it uses fewer than five distinct characters")

    lowered = password.lower()
    # Do not let the password contain the identity it protects.
    if email:
        local = email.split("@", 1)[0].lower()
        if local and len(local) >= 3 and local in lowered:
            problems.append("it must not contain your email address")
    if full_name:
        for token in unicodedata.normalize("NFKD", full_name).lower().split():
            if len(token) >= 4 and token in lowered:
                problems.append("it must not contain your name")
                break

    if problems:
        raise PasswordPolicyError(
            "The password is too weak. It must have " + "; ".join(problems) + ".",
            details={"requirements": problems},
        )


def password_strength_score(password: str) -> dict[str, object]:
    """A rough 0-4 strength estimate for the client UI. Not a security control."""
    unique = len(set(password))
    has_lower = bool(re.search(r"[a-z]", password))
    has_upper = bool(re.search(r"[A-Z]", password))
    has_digit = bool(re.search(r"\d", password))
    has_symbol = bool(re.search(r"[^A-Za-z0-9]", password))

    if password.lower() in _COMMON_PASSWORDS:
        score = 0
    else:
        score = 0
        score += 1 if len(password) >= 10 else 0
        score += 1 if len(password) >= 14 else 0
        score += 1 if unique >= 8 else 0
        score += 1 if sum([has_lower, has_upper, has_digit, has_symbol]) >= 3 else 0

    return {
        "score": score,
        "max_score": 4,
        "length": len(password),
        "unique_characters": unique,
        "has_lower": has_lower,
        "has_upper": has_upper,
        "has_digit": has_digit,
        "has_symbol": has_symbol,
    }


# ---------------------------------------------------------------------------
# Keyed digests, used for refresh tokens, OTP codes and target lookups
# ---------------------------------------------------------------------------


def keyed_digest(value: str, pepper: str) -> str:
    """HMAC-SHA-256 hex digest.

    Used instead of a plain hash for low-entropy secrets such as a 6-digit OTP,
    where a plain hash is trivially brute-forced. For high-entropy values
    (refresh tokens) a plain SHA-256 is already safe and is cheaper.
    """
    return hmac.new(
        pepper.encode("utf-8"), value.encode("utf-8"), hashlib.sha256
    ).hexdigest()


def sha256_digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def constant_time_equals(left: str, right: str) -> bool:
    return hmac.compare_digest(left, right)


def secure_random_urlsafe(nbytes: int = 32) -> str:
    return secrets.token_urlsafe(nbytes)
