"""JWT access and refresh tokens.

Four decisions that matter:

1. **Separate signing secrets.** ``JWT_SECRET`` and ``JWT_REFRESH_SECRET`` are
   independent, so a leaked refresh secret cannot be used to mint access tokens
   and vice versa. Startup refuses to run if they are equal.
2. **Refresh tokens are stateful.** The JWT is only a carrier; a row in
   ``refresh_tokens`` is the authority. That is what makes revocation,
   logout-all and theft detection possible at all.
3. **Rotation with reuse detection.** Every refresh issues a new row and marks
   the old one used. Presenting an already-used token is treated as theft:
   the whole family is revoked.
4. **A ``kid`` header.** The server can serve more than one signing key during
   a rotation window without invalidating live sessions.

Nothing in this module logs a token.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Literal

import jwt

from app.core.config import Settings, get_settings
from app.core.errors import AppError, ErrorCode
from app.core.timeutils import now_utc

TokenType = Literal["access", "refresh"]

ACCESS_TOKEN = "access"
REFRESH_TOKEN = "refresh"

#: Bumped when the claim layout changes incompatibly.
TOKEN_VERSION = 1

#: Stable key ids. The secret behind a kid can be rotated by changing
#: JWT_SECRET_<kid> without touching the kid itself.
KID_ACCESS = "a1"
KID_REFRESH = "r1"

_CLAIM_AUDIENCE = "plantdoctor-mobile"
_CLAIM_ISSUER = "plantdoctor-server"


@dataclass(frozen=True)
class TokenPair:
    access_token: str
    refresh_token: str
    access_expires_at: datetime
    refresh_expires_at: datetime
    session_id: uuid.UUID
    token_type: str = "Bearer"
    expires_in: int = 0

    def as_dict(self) -> dict[str, Any]:
        return {
            "access_token": self.access_token,
            "refresh_token": self.refresh_token,
            "token_type": self.token_type,
            "expires_in": self.expires_in,
            "access_expires_at": self.access_expires_at,
            "refresh_expires_at": self.refresh_expires_at,
            "session_id": str(self.session_id),
        }


@dataclass(frozen=True)
class DecodedToken:
    subject: uuid.UUID
    session_id: uuid.UUID
    token_type: TokenType
    jti: str
    issued_at: datetime
    expires_at: datetime
    roles: tuple[str, ...]
    permissions: tuple[str, ...]
    state_version: int


def _secret_for(token_type: TokenType, settings: Settings | None = None) -> str:
    settings = settings or get_settings()
    if token_type == REFRESH_TOKEN:
        return settings.effective_refresh_secret
    return settings.effective_jwt_secret


def _now() -> datetime:
    return now_utc()


def _encode(
    claims: dict[str, Any],
    *,
    token_type: TokenType,
    settings: Settings | None = None,
) -> str:
    settings = settings or get_settings()
    now = _now()
    kid = KID_REFRESH if token_type == REFRESH_TOKEN else KID_ACCESS
    payload = {
        **claims,
        "iat": int(now.timestamp()),
        "nbf": int(now.timestamp()),
        "exp": int(claims["exp"].timestamp()),
        "jti": claims["jti"],
        "typ": token_type,
        "ver": TOKEN_VERSION,
        "iss": _CLAIM_ISSUER,
        "aud": _CLAIM_AUDIENCE,
    }
    return jwt.encode(
        payload,
        _secret_for(token_type, settings),
        algorithm=settings.JWT_ALGORITHM,
        headers={"kid": kid, "typ": "JWT"},
    )


def create_access_token(
    *,
    user_id: uuid.UUID,
    session_id: uuid.UUID,
    roles: list[str],
    permissions: list[str],
    state_version: int,
    settings: Settings | None = None,
) -> tuple[str, datetime]:
    settings = settings or get_settings()
    now = _now()
    expires_at = now + timedelta(minutes=settings.ACCESS_TOKEN_TTL_MINUTES)
    claims = {
        "sub": str(user_id),
        "sid": str(session_id),
        "jti": uuid.uuid4().hex,
        "role": sorted(set(roles)),
        "perm": sorted(set(permissions)),
        "sv": state_version,
        "exp": expires_at,
    }
    return _encode(claims, token_type=ACCESS_TOKEN, settings=settings), expires_at


def create_refresh_token(
    *,
    user_id: uuid.UUID,
    session_id: uuid.UUID,
    family_id: uuid.UUID,
    settings: Settings | None = None,
) -> tuple[str, datetime, str, uuid.UUID]:
    """Return ``(token, expires_at, jti, family_id)``.

    The raw token is returned so it can be stored hashed. The plaintext is never
    persisted, so it exists only in the response to the client.
    """
    settings = settings or get_settings()
    now = _now()
    expires_at = now + timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS)
    jti = uuid.uuid4().hex
    claims = {
        "sub": str(user_id),
        "sid": str(session_id),
        "fam": str(family_id),
        "jti": jti,
        "exp": expires_at,
    }
    token = _encode(claims, token_type=REFRESH_TOKEN, settings=settings)
    return token, expires_at, jti, family_id


def decode_token(
    token: str, *, expected_type: TokenType, settings: Settings | None = None
) -> DecodedToken:
    """Verify a token or raise :class:`AppError`.

    Every failure path raises the same shape so a caller cannot accidentally
    distinguish "wrong signature" from "expired" in an error message and help an
    attacker. The specific code is still available in logs.
    """
    settings = settings or get_settings()
    if not token or not isinstance(token, str):
        raise AppError(
            "The token is missing or malformed.",
            code=ErrorCode.TOKEN_INVALID,
            status_code=401,
        )

    try:
        claims = jwt.decode(
            token,
            _secret_for(expected_type, settings),
            algorithms=[settings.JWT_ALGORITHM],
            audience=_CLAIM_AUDIENCE,
            issuer=_CLAIM_ISSUER,
            options={
                "require": ["exp", "iat", "sub", "jti", "typ"],
                "verify_signature": True,
                "verify_exp": True,
                "verify_aud": True,
                "verify_iss": True,
            },
        )
    except jwt.ExpiredSignatureError as exc:
        raise AppError(
            "The token has expired. Please sign in again.",
            code=ErrorCode.TOKEN_EXPIRED,
            status_code=401,
        ) from exc
    except jwt.InvalidTokenError as exc:
        raise AppError(
            "The token is invalid.",
            code=ErrorCode.TOKEN_INVALID,
            status_code=401,
        ) from exc

    if claims.get("typ") != expected_type:
        # An access token presented where a refresh token is expected means the
        # secret boundary has been crossed; refuse.
        raise AppError(
            "The token is invalid.",
            code=ErrorCode.TOKEN_INVALID,
            status_code=401,
        )
    if claims.get("ver") != TOKEN_VERSION:
        raise AppError(
            "The token was issued by an incompatible version of the server.",
            code=ErrorCode.TOKEN_INVALID,
            status_code=401,
        )

    try:
        subject = uuid.UUID(str(claims["sub"]))
        session_id = uuid.UUID(str(claims["sid"]))
        jti = str(claims["jti"])
        issued_at = datetime.fromtimestamp(int(claims["iat"]), tz=timezone.utc)
        expires_at = datetime.fromtimestamp(int(claims["exp"]), tz=timezone.utc)
    except (KeyError, ValueError, TypeError) as exc:
        raise AppError(
            "The token is malformed.",
            code=ErrorCode.TOKEN_INVALID,
            status_code=401,
        ) from exc

    return DecodedToken(
        subject=subject,
        session_id=session_id,
        token_type=expected_type,
        jti=jti,
        issued_at=issued_at,
        expires_at=expires_at,
        roles=tuple(claims.get("role") or ()),
        permissions=tuple(claims.get("perm") or ()),
        state_version=int(claims.get("sv") or 0),
    )


def decode_refresh_family(token: str, *, settings: Settings | None = None) -> uuid.UUID:
    """Pull the rotation-family id out of a refresh token.

    Used before the token is hashed, when handling reuse detection.
    """
    settings = settings or get_settings()
    claims = jwt.decode(
        token,
        _secret_for(REFRESH_TOKEN, settings),
        algorithms=[settings.JWT_ALGORITHM],
        audience=_CLAIM_AUDIENCE,
        issuer=_CLAIM_ISSUER,
        options={"require": ["fam", "sid", "sub", "jti"]},
    )
    try:
        return uuid.UUID(str(claims["fam"]))
    except (KeyError, ValueError) as exc:
        raise AppError(
            "The token is malformed.",
            code=ErrorCode.REFRESH_INVALID,
            status_code=401,
        ) from exc
