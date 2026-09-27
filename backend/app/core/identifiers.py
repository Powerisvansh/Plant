"""Normalisation of the two identifiers a user can sign in with.

The database stores ``email_normalised`` and ``phone_e164`` behind *partial*
unique indexes, so normalisation is not cosmetic: it is what makes the
uniqueness constraint meaningful.

Getting this wrong is how duplicate accounts appear, so the rules are
deliberately strict and never guess.
"""

from __future__ import annotations

import re
import unicodedata

from app.core.errors import AppError, ErrorCode

#: Domains that are literally invalid, caught before a confirmation mail is
#: sent to an address that can never receive one.
_INVALID_EMAIL_DOMAINS = frozenset(
    {
        "example.com",
        "example.org",
        "example.net",
        "example.invalid",
        "localhost",
        "test",
        "invalid",
    }
)

_EMAIL_RE = re.compile(
    r"^(?P<local>[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+)"
    r"@"
    r"(?P<domain>[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*)$"
)

MAX_EMAIL_LENGTH = 320
MAX_PHONE_DIGITS = 15  # E.164 ceiling
MIN_PHONE_DIGITS = 7


class InvalidEmailError(AppError):
    status_code = 422
    code = ErrorCode.VALIDATION_ERROR
    message = "That email address is not valid."


class InvalidPhoneError(AppError):
    status_code = 422
    code = ErrorCode.VALIDATION_ERROR
    message = "That phone number is not valid. Use international format, e.g. +919876543210."


def normalise_email(email: str | None) -> str | None:
    """Lowercase the domain, keep the local part, and validate.

    The local part is *not* lowercased. RFC 5321 makes it case-sensitive, and
    silently folding ``A.user@`` into ``a.user@`` can merge two genuinely
    different mailboxes on a case-sensitive server. Gmail-style providers are
    the common case, so the domain - which is never case-sensitive - is what
    gets folded.
    """
    if email is None:
        return None
    candidate = unicodedata.normalize("NFKC", email).strip().strip("<>")
    if not candidate:
        return None
    if len(candidate) > MAX_EMAIL_LENGTH:
        raise InvalidEmailError("That email address is too long.")

    match = _EMAIL_RE.match(candidate)
    if not match:
        raise InvalidEmailError()

    domain = match.group("domain").lower()
    if "." not in domain:
        # "user@localhost" reaches a mail server, not a mailbox. A domain must
        # have at least one dot, so a typo like "gmail" is caught here.
        raise InvalidEmailError("That email address is missing a domain, e.g. @gmail.com.")
    if domain in _INVALID_EMAIL_DOMAINS:
        raise InvalidEmailError(
            "That email domain cannot receive mail. Use a real address."
        )
    if len(match.group("local")) > 64:
        raise InvalidEmailError("The part of the address before @ is too long.")

    return f"{match.group('local')}@{domain}"


def _parse_phone(raw: str) -> tuple[str, str]:
    """Return ``(e164, display)`` or raise.

    Accepted input: ``+919876543210``, ``+91 98765 43210``, ``09876543210`` with
    an explicit default country code. Without a ``+`` the number is ambiguous -
    is ``9876543210`` Indian, or nine digits of something else? - so a default
    country code must be configured, and guessing is not an option.
    """
    from app.core.config import get_settings

    settings = get_settings()
    raw = unicodedata.normalize("NFKD", raw).strip()
    if not raw:
        raise InvalidPhoneError()

    display = raw
    has_plus = raw.startswith("+")
    # Keep digits only; drop spaces, dashes, dots and brackets.
    digits = re.sub(r"[^0-9]", "", raw)

    if not has_plus:
        default_cc = (settings.DEFAULT_PHONE_COUNTRY_CODE or "").strip().lstrip("0")
        if not default_cc:
            raise InvalidPhoneError(
                "Phone numbers must be in international format, e.g. +919876543210."
            )
        digits = f"{default_cc}{digits}"

    if not (MIN_PHONE_DIGITS <= len(digits) <= MAX_PHONE_DIGITS):
        raise InvalidPhoneError("That phone number has an implausible number of digits.")
    if digits.startswith("0"):
        raise InvalidPhoneError("A phone number cannot start with 0.")

    return f"+{digits}", display


def normalise_phone(phone: str | None) -> tuple[str | None, str | None]:
    """Return ``(phone_e164, phone_display)``."""
    if phone is None or not str(phone).strip():
        return None, None
    e164, display = _parse_phone(str(phone))
    return e164, display


def mask_email(email: str | None) -> str | None:
    """``user@example.com`` -> ``u***r@example.com``.

    Used in audit rows and admin listings. Enough to recognise an account,
    not enough to be useful if the log leaks.
    """
    if not email or "@" not in email:
        return None
    local, _, domain = email.partition("@")
    if len(local) <= 2:
        masked = local[0] + "*"
    else:
        masked = f"{local[0]}{'*' * (len(local) - 2)}{local[-1]}"
    return f"{masked}@{domain}"


def mask_phone(phone: str | None) -> str | None:
    """``+919876543210`` -> ``+9198*****210``."""
    if not phone or len(phone) < 6:
        return None
    return f"{phone[:5]}{'*' * (len(phone) - 8)}{phone[-3:]}"
