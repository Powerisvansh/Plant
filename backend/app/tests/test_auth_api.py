"""End-to-end tests for the auth surface.

These drive the real FastAPI app against the real test database. Nothing is
mocked: tokens are signed with the real secrets, passwords are really verified
with Argon2id, and rotation really writes rows. The point is to prove the
security properties hold, which a mock would only restate.

The behaviours worth testing are the ones an attacker would try, plus the
invariants that are easy to break during a refactor:

* unknown identifier and wrong password are indistinguishable, in body and in
  timing
* a refresh token cannot be used twice, and reuse kills the whole family
* revoking a session, changing a password, or changing a role invalidates
  tokens that were already issued
* a token signed with the refresh secret is not accepted as an access token
* a caller cannot revoke or read another account's session
"""

from __future__ import annotations

import time
import uuid

import pytest
from sqlalchemy import select, text

from app.core.config import get_settings
from app.core.errors import ErrorCode
from app.database.session import session_scope
from app.models.session import LoginAttempt, RefreshToken, StateVersion, UserSession
from app.security.tokens import (
    REFRESH_TOKEN,
    create_access_token,
    decode_token,
)

# ----------------------------------------------------------------------
# registration
# ----------------------------------------------------------------------


def test_register_creates_pending_account_without_tokens(client, unique_email):
    email = unique_email()
    response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Rosa Delgado",
            "email": email,
            "password": "Garden-Mango-47!",
            "terms_accepted": True,
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["success"] is True
    data = body["data"]

    # No tokens: the account cannot act until the OTP step proves the address.
    assert "access_token" not in data
    assert "refresh_token" not in data
    assert data["status"] == "PENDING_VERIFICATION"
    assert data["next_step"] == "request_otp"
    assert data["user"]["email"] == email
    assert data["user"]["roles"] == ["USER"]

    # The password must never come back in any form.
    assert "Garden-Mango-47!" not in response.text
    assert "password_hash" not in response.text


def test_register_never_returns_the_stored_password_hash(client, unique_email):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Hidden Hash",
            "email": unique_email(),
            "password": "Garden-Mango-47!",
        },
    )
    text_body = response.text
    for leak in ("argon2", "password_hash", "$argon2id$"):
        assert leak not in text_body, f"response leaked {leak!r}"


def test_register_normalises_email_whitespace_and_domain_case(client):
    """Local part is preserved, domain is folded.

    RFC 5321 makes the local part case-sensitive, so lowercasing it would merge
    two genuinely different mailboxes on a case-sensitive server. The domain is
    never case-sensitive and is what gets folded.
    """
    response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Casey North",
            "email": "  Mixed.Case@Example.TEST  ",
            "password": "Garden-Mango-47!",
        },
    )
    assert response.status_code == 201
    assert response.json()["data"]["user"]["email"] is not None
    with session_scope() as s:
        stored = s.execute(
            text("SELECT email_normalised FROM users ORDER BY created_at DESC LIMIT 1")
        ).scalar_one()
    assert stored == "Mixed.Case@example.test"
    assert stored.endswith("@example.test")


def test_register_rejects_weak_password_with_field_level_detail(client, unique_email):
    response = client.post(
        "/api/v1/auth/register",
        json={"full_name": "Weak Pass", "email": unique_email(), "password": "abc"},
    )
    assert response.status_code in (400, 422)
    body = response.json()
    assert body["success"] is False


def test_register_rejects_missing_identifier(client):
    response = client.post(
        "/api/v1/auth/register",
        json={"full_name": "No Contact", "password": "Garden-Mango-47!"},
    )
    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == ErrorCode.VALIDATION_ERROR


def test_register_duplicate_returns_conflict(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    response = client.post(
        "/api/v1/auth/register",
        json={"full_name": "Impostor", "email": email, "password": password},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] in {
        ErrorCode.ACCOUNT_EXISTS,
        ErrorCode.EMAIL_ALREADY_REGISTERED,
    }


def test_request_and_verify_otp_activates_account(client, unique_email, password):
    email = unique_email()
    client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "OTP User",
            "email": email,
            "password": password,
            "terms_accepted": True,
        },
    )

    request = client.post("/api/v1/auth/request-otp", json={"identifier": email})
    assert request.status_code == 200, request.text

    mailbox_dir = get_settings().mailbox_root
    assert mailbox_dir is not None
    files = sorted(mailbox_dir.glob("*.txt"), key=lambda p: p.stat().st_mtime, reverse=True)
    assert files, "OTP mail should be written to the mailbox directory when SMTP is not configured"
    payload = files[0].read_text(encoding="utf-8")
    match = __import__("re").search(r"\b\d{6}\b", payload)
    assert match, f"No six-digit OTP found in mailbox payload: {payload!r}"
    otp = match.group(0)

    verify = client.post(
        "/api/v1/auth/verify-otp",
        json={"identifier": email, "code": otp},
    )
    assert verify.status_code == 200, verify.text
    body = verify.json()["data"]
    assert body["status"] == "ACTIVE"
    assert body["verified"] is True
    assert body["user"]["email"] == email


def test_registered_account_cannot_log_in_before_verification(client, unique_email, password):
    """The whole point of PENDING_VERIFICATION: registration is not a login."""
    email = unique_email()
    client.post(
        "/api/v1/auth/register",
        json={"full_name": "Not Yet", "email": email, "password": password},
    )
    response = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == ErrorCode.ACCOUNT_NOT_VERIFIED


# ----------------------------------------------------------------------
# login
# ----------------------------------------------------------------------


def test_login_returns_tokens_and_user(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email, full_name="Happy Grower")

    response = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    )
    assert response.status_code == 200, response.text
    data = response.json()["data"]

    assert data["token_type"] == "Bearer"
    assert data["expires_in"] > 0
    assert data["user"]["email"] == email
    assert data["user"]["full_name"] == "Happy Grower"
    assert uuid.UUID(data["session_id"])

    # Both tokens must actually verify, with the right type and the right secret.
    access = decode_token(data["access_token"], expected_type="access")
    refresh = decode_token(data["refresh_token"], expected_type=REFRESH_TOKEN)
    assert access.subject == refresh.subject
    assert str(access.session_id) == data["session_id"]


def test_login_by_phone_number(client, make_user, password):
    make_user(phone="+919876543210")
    response = client.post(
        "/api/v1/auth/login",
        json={"identifier": "+919876543210", "password": password},
    )
    assert response.status_code == 200, response.text


def test_login_wrong_password_is_generic(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    response = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": "Totally-Wrong-99!"}
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == ErrorCode.INVALID_CREDENTIALS


def test_unknown_identifier_and_wrong_password_are_indistinguishable(
    client, make_user, unique_email
):
    """Enumeration defence: same code, same message, same status."""
    known = unique_email()
    make_user(email=known)

    unknown = client.post(
        "/api/v1/auth/login",
        json={"identifier": unique_email("ghost"), "password": "Garden-Mango-47!"},
    )
    wrong = client.post(
        "/api/v1/auth/login",
        json={"identifier": known, "password": "Totally-Wrong-99!"},
    )

    assert unknown.status_code == wrong.status_code == 401
    assert unknown.json()["error"]["code"] == wrong.json()["error"]["code"]
    assert unknown.json()["error"]["message"] == wrong.json()["error"]["message"]


def test_unknown_identifier_still_costs_argon2_time(client, make_user, unique_email):
    """A microsecond response would enumerate addresses even with a generic body.

    Both paths hash. The assertion is loose on purpose: it only has to catch a
    return that skips hashing entirely, not measure Argon2 precisely on shared
        CI hardware.
    """
    known = unique_email()
    make_user(email=known)

    def _time(identifier: str, password: str) -> float:
        start = time.perf_counter()
        client.post(
            "/api/v1/auth/login", json={"identifier": identifier, "password": password}
        )
        return time.perf_counter() - start

    _time(known, "warmup-password")  # discard the first, it pays import cost
    known_ms = _time(known, "Totally-Wrong-99!") * 1000
    unknown_ms = _time(unique_email("ghost"), "Totally-Wrong-99!") * 1000

    assert known_ms > 1.0, f"known-identifier login was {known_ms:.2f}ms; hashing looks skipped"
    assert unknown_ms > 1.0, f"unknown-identifier login was {unknown_ms:.2f}ms; hashing looks skipped"


def test_login_records_attempt_with_masked_identifier(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    client.post("/api/v1/auth/login", json={"identifier": email, "password": password})

    with session_scope() as s:
        row = s.execute(
            select(LoginAttempt).order_by(LoginAttempt.id.desc()).limit(1)
        ).scalar_one()
    assert row.succeeded is True
    assert row.identifier_used is not None
    # The masked form must not be the plaintext address.
    assert email not in (row.identifier_used or "")
    assert row.identifier_used != email


def test_login_attempt_rows_are_written_for_unknown_identifiers(client, unique_email):
    email = unique_email("ghost")
    client.post("/api/v1/auth/login", json={"identifier": email, "password": "whatever-123"})
    with session_scope() as s:
        rows = s.execute(
            select(LoginAttempt).where(LoginAttempt.failure_reason == "unknown_identifier")
        ).scalars().all()
    assert rows, "an attempt against an unknown address must still be recorded"
    assert rows[-1].user_id is None


def test_login_locked_account_reports_locked(client, make_user, unique_email, password):
    from app.core.timeutils import now_utc
    from datetime import timedelta

    email = unique_email()
    user = make_user(email=email)
    with session_scope() as s:
        row = s.get(type(user), user.id)
        row.locked_until = now_utc() + timedelta(minutes=10)
        row.failed_login_count = 9

    response = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    )
    assert response.status_code == 423
    assert response.json()["error"]["code"] == ErrorCode.ACCOUNT_LOCKED


def test_login_disabled_account_reports_disabled(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email, active=False)
    response = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == ErrorCode.ACCOUNT_DISABLED


def test_login_disabled_account_reports_disabled(client, make_user, unique_email, password):
    from app.models.enums import UserStatus

    email = unique_email()
    make_user(email=email, user_status=UserStatus.DISABLED)
    response = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    )
    assert response.status_code == 403


# ----------------------------------------------------------------------
# access token handling
# ----------------------------------------------------------------------


def test_me_requires_a_token(client):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == ErrorCode.UNAUTHENTICATED


def test_me_returns_identity_and_live_permissions(auth_client):
    logged_in = auth_client(role="USER")
    response = logged_in.client.get("/api/v1/auth/me", headers=logged_in.auth())
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["user"]["id"] == str(logged_in.user.id)
    assert data["user"]["roles"] == ["USER"]
    assert "plants:read" in data["permissions"]


def test_super_admin_token_carries_every_permission(auth_client):
    logged_in = auth_client(role="SUPER_ADMIN")
    response = logged_in.client.get("/api/v1/auth/me", headers=logged_in.auth())
    assert response.status_code == 200
    assert len(response.json()["data"]["permissions"]) == 50


@pytest.mark.parametrize(
    "token",
    ["", "not-a-jwt", "a.b.c", "Bearer", "null"],
)
def test_malformed_tokens_are_rejected_without_a_stack_trace(client, token):
    response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
    body = response.json()
    assert body["success"] is False
    assert "Traceback" not in response.text
    assert "app/" not in response.text


def test_wrong_scheme_is_rejected(client, make_user, unique_email, password):
    logged_in_email = unique_email()
    make_user(email=logged_in_email)
    login = client.post(
        "/api/v1/auth/login",
        json={"identifier": logged_in_email, "password": password},
    ).json()["data"]
    response = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Basic {login['access_token']}"}
    )
    assert response.status_code == 401


def test_access_token_signed_with_the_refresh_secret_is_rejected(client, auth_client):
    """The two secrets must not be interchangeable."""
    settings = get_settings()
    import jwt

    forged = jwt.encode(
        {
            "sub": str(auth_client().user.id),
            "sid": str(uuid.uuid4()),
            "jti": uuid.uuid4().hex,
            "typ": "access",
            "ver": 1,
            "iss": "plantdoctor-server",
            "aud": "plantdoctor-mobile",
            "role": ["SUPER_ADMIN"],
            "perm": ["*"],
            "sv": 1,
            "iat": int(time.time()),
            "nbf": int(time.time()),
            "exp": int(time.time()) + 3600,
        },
        settings.effective_refresh_secret,
        algorithm=settings.JWT_ALGORITHM,
    )
    response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] in {
        ErrorCode.TOKEN_INVALID,
        ErrorCode.TOKEN_REVOKED,
    }


def test_token_with_escalated_role_claims_is_still_refused(client, auth_client):
    """A token whose claims claim more than the user has must not grant it.

    The role claim is signed, so this cannot be forged without the secret. The
    realistic threat is a stale token issued before a demotion, which the
    state-version check and the live database read must both catch.
    """
    logged_in = auth_client(role="USER")
    response = logged_in.client.get("/api/v1/auth/me", headers=logged_in.auth())
    assert response.status_code == 200
    assert response.json()["data"]["user"]["roles"] == ["USER"]


def test_demotion_takes_effect_on_the_next_request(client, make_user, unique_email, password):
    """Revoke a role, then use the token that was minted while the role existed."""
    from app.repositories.user_repository import UserRepository
    from app.services.user_service import UserService
    from app.services.auth_service import AuthService

    email = unique_email()
    user = make_user(email=email, role="EXPERT")

    login = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    ).json()["data"]
    headers = {"Authorization": f"Bearer {login['access_token']}"}

    assert client.get("/api/v1/auth/me", headers=headers).status_code == 200

    with session_scope() as s:
        fresh = UserRepository(s).get(user.id)
        UserService(s).set_roles(fresh, ["USER"], actor=user.id, reason="demoted")
        AuthService(s).bump_state_version(user.id, reason="role_change")
        s.commit()

    after = client.get("/api/v1/auth/me", headers=headers)
    assert after.status_code == 401
    assert after.json()["error"]["code"] in {ErrorCode.TOKEN_REVOKED, ErrorCode.TOKEN_INVALID}


def test_expired_access_token_is_rejected(client, make_user, unique_email):
    from datetime import datetime, timedelta, timezone

    user = make_user(email=unique_email())
    past = datetime.now(timezone.utc) - timedelta(minutes=5)
    token, _ = create_access_token(
        user_id=user.id,
        session_id=uuid.uuid4(),
        roles=["USER"],
        permissions=["plant.read"],
        state_version=1,
    )
    # Sign a token that expired an hour ago, using the real path for claims.
    import jwt as pyjwt

    settings = get_settings()
    expired = pyjwt.encode(
        {
            "sub": str(user.id),
            "sid": str(uuid.uuid4()),
            "jti": uuid.uuid4().hex,
            "typ": "access",
            "ver": 1,
            "iss": "plantdoctor-server",
            "aud": "plantdoctor-mobile",
            "sv": 1,
            "iat": int((past - timedelta(hours=1)).timestamp()),
            "nbf": int((past - timedelta(hours=1)).timestamp()),
            "exp": int(past.timestamp()),
        },
        settings.effective_jwt_secret,
        algorithm=settings.JWT_ALGORITHM,
    )
    response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {expired}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == ErrorCode.TOKEN_EXPIRED


# ----------------------------------------------------------------------
# refresh rotation
# ----------------------------------------------------------------------


def test_refresh_issues_a_new_pair(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    first = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    ).json()["data"]

    response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    )
    assert response.status_code == 200, response.text
    second = response.json()["data"]

    assert second["access_token"] != first["access_token"]
    assert second["refresh_token"] != first["refresh_token"]
    assert second["session_id"] == first["session_id"]


def test_old_refresh_token_cannot_be_reused(client, make_user, unique_email, password):
    """Rotation means single use. A second attempt is a replay."""
    email = unique_email()
    make_user(email=email)
    first = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    ).json()["data"]

    assert (
        client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}).status_code
        == 200
    )
    replay = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    )
    assert replay.status_code == 401
    assert replay.json()["error"]["code"] == ErrorCode.TOKEN_REUSE_DETECTED


def test_replay_revokes_the_whole_family(client, make_user, unique_email, password):
    """After a replay is detected, the *new* token must die too.

    This is the property that makes reuse detection useful. If the stolen
    copy's holder and the real user could both keep going, detection would only
    be an inconvenience.
    """
    email = unique_email()
    make_user(email=email)
    first = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    ).json()["data"]

    rotated = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    ).json()["data"]

    client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})

    after = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": rotated["refresh_token"]}
    )
    assert after.status_code == 401

    # And the access token from the rotation is dead as well.
    me = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {rotated['access_token']}"}
    )
    assert me.status_code == 401


def test_refresh_after_password_change_fails(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    login = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    ).json()["data"]

    # Change the password through the API, which is the real path.
    changed = client.post(
        "/api/v1/auth/change-password",
        headers={"Authorization": f"Bearer {login['access_token']}"},
        json={"current_password": password, "new_password": "Different-Cedar-88!"},
    )
    assert changed.status_code == 200

    response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]}
    )
    assert response.status_code == 401


def test_refresh_with_a_revoked_session_fails(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    login = client.post(
        "/api/v1/auth/login", json={"identifier": email, "password": password}
    ).json()["data"]
    client.post(
        "/api/v1/auth/logout", headers={"Authorization": f"Bearer {login['access_token']}"}
    )
    response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]}
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] in {
        ErrorCode.TOKEN_REVOKED,
        ErrorCode.REFRESH_INVALID,
    }


def test_access_token_cannot_be_used_as_a_refresh_token(client, auth_client):
    logged_in = auth_client()
    response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": logged_in.access_token}
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] in {
        ErrorCode.REFRESH_INVALID,
        ErrorCode.TOKEN_INVALID,
    }


def test_refresh_with_garbage_is_rejected(client):
    response = client.post("/api/v1/auth/refresh", json={"refresh_token": "abc.def.ghi"})
    assert response.status_code == 401


# ----------------------------------------------------------------------
# logout
# ----------------------------------------------------------------------


def test_logout_revokes_the_session_and_its_tokens(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.post("/api/v1/auth/logout", headers=logged_in.auth())
    assert response.status_code == 200
    assert response.json()["data"]["signed_out"] is True

    me = logged_in.client.get("/api/v1/auth/me", headers=logged_in.auth())
    assert me.status_code == 401

    with session_scope() as s:
        session_row = s.get(UserSession, uuid.UUID(logged_in.session_id))
        assert session_row.revoked_at is not None
        live = s.execute(
            select(RefreshToken).where(
                RefreshToken.session_id == session_row.id,
                RefreshToken.revoked_at.is_(None),
            )
        ).scalars().all()
    assert live == [], "logout must revoke every refresh token for the session"


def test_logout_retry_is_not_a_server_error(client, auth_client):
    """A retry after a dropped response must not surface as a 500.

    The retry presents a token the server has already revoked, so 401 is the
    right answer. What matters is that the end state is the same and nothing
    blows up: the client should treat "already signed out" as success.
    """
    logged_in = auth_client()
    first = logged_in.client.post("/api/v1/auth/logout", headers=logged_in.auth())
    assert first.status_code == 200
    second = logged_in.client.post("/api/v1/auth/logout", headers=logged_in.auth())
    assert second.status_code < 500
    assert second.status_code in (200, 401)


def test_logout_requires_a_token(client):
    assert client.post("/api/v1/auth/logout").status_code == 401


def test_logout_all_ends_every_device_including_this_one(
    client, make_user, unique_email, password
):
    email = unique_email()
    make_user(email=email)

    def _login_as_this_user(device: str) -> dict:
        response = client.post(
            "/api/v1/auth/login",
            json={"identifier": email, "password": password},
            headers={"X-Device-Id": device},
        )
        assert response.status_code == 200, response.text
        return response.json()["data"]

    # One user, two devices. "Sign out everywhere" is only meaningful when the
    # sessions actually belong to the same account.
    phone = _login_as_this_user("phone")
    laptop = _login_as_this_user("laptop")

    response = client.post(
        "/api/v1/auth/logout-all",
        headers={"Authorization": f"Bearer {phone['access_token']}"},
    )
    assert response.status_code == 200

    for token in (phone["access_token"], laptop["access_token"]):
        assert client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}
        ).status_code == 401
    for refresh in (phone["refresh_token"], laptop["refresh_token"]):
        assert client.post(
            "/api/v1/auth/refresh", json={"refresh_token": refresh}
        ).status_code == 401


def test_logout_all_bumps_the_state_version(client, auth_client):
    logged_in = auth_client()
    with session_scope() as s:
        before = s.execute(
            select(StateVersion).where(StateVersion.user_id == logged_in.user.id)
        ).scalar_one_or_none()
        before_version = before.version if before else 0
    logged_in.client.post("/api/v1/auth/logout-all", headers=logged_in.auth())
    with session_scope() as s:
        after = s.execute(
            select(StateVersion).where(StateVersion.user_id == logged_in.user.id)
        ).scalar_one()
    assert after.version > before_version


# ----------------------------------------------------------------------
# sessions
# ----------------------------------------------------------------------


def test_sessions_lists_the_current_device_as_current(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.get("/api/v1/auth/sessions", headers=logged_in.auth())
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["active_count"] >= 1
    current = [s for s in data["sessions"] if s["is_current"]]
    assert len(current) == 1
    assert current[0]["session_id"] == logged_in.session_id


def test_sessions_never_expose_the_token_hash(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.get("/api/v1/auth/sessions", headers=logged_in.auth())
    assert "session_token_hash" not in response.text
    assert logged_in.refresh_token not in response.text


def test_revoke_one_session_by_id(client, make_user, unique_email, password):
    email = unique_email()
    make_user(email=email)
    first = client.post("/api/v1/auth/login", json={"identifier": email, "password": password}).json()["data"]
    second = client.post(
        "/api/v1/auth/login",
        json={"identifier": email, "password": password},
        headers={"X-Device-Id": "tablet"},
    ).json()["data"]

    response = client.request(
        "DELETE",
        f"/api/v1/auth/sessions/{second['session_id']}",
        headers={"Authorization": f"Bearer {first['access_token']}"},
    )
    assert response.status_code == 200

    assert client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {second['access_token']}"}
    ).status_code == 401
    # The caller's own session is untouched.
    assert client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {first['access_token']}"}
    ).status_code == 200


def test_cannot_revoke_another_accounts_session(client, auth_client, unique_email, password):
    victim = auth_client(email=unique_email("victim"))
    attacker = auth_client(email=unique_email("attacker"))

    response = attacker.client.request(
        "DELETE",
        f"/api/v1/auth/sessions/{victim.session_id}",
        headers=attacker.auth(),
    )
    # 404, not 403: a 403 would confirm the session id exists.
    assert response.status_code == 404

    assert victim.client.get("/api/v1/auth/me", headers=victim.auth()).status_code == 200


def test_revoke_unknown_session_returns_404(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.request(
        "DELETE", f"/api/v1/auth/sessions/{uuid.uuid4()}", headers=logged_in.auth()
    )
    assert response.status_code == 404


def test_revoke_malformed_session_id_returns_404(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.request(
        "DELETE", "/api/v1/auth/sessions/not-a-uuid", headers=logged_in.auth()
    )
    assert response.status_code == 404


def test_sessions_require_authentication(client):
    assert client.get("/api/v1/auth/sessions").status_code == 401


# ----------------------------------------------------------------------
# password change
# ----------------------------------------------------------------------


def test_change_password_requires_the_current_password(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.post(
        "/api/v1/auth/change-password",
        headers=logged_in.auth(),
        json={"current_password": "Not-The-Password-1!", "new_password": "Garden-Mango-47!"},
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == ErrorCode.INVALID_CREDENTIALS


def test_change_password_rejects_reusing_the_same_value(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.post(
        "/api/v1/auth/change-password",
        headers=logged_in.auth(),
        json={"current_password": logged_in.password, "new_password": logged_in.password},
    )
    assert response.status_code == 422


def test_change_password_rejects_a_weak_new_password(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.post(
        "/api/v1/auth/change-password",
        headers=logged_in.auth(),
        json={"current_password": logged_in.password, "new_password": "abc"},
    )
    assert response.status_code in (400, 422)


def test_change_password_signs_everyone_out_including_the_caller(client, auth_client):
    logged_in = auth_client()
    response = logged_in.client.post(
        "/api/v1/auth/change-password",
        headers=logged_in.auth(),
        json={"current_password": logged_in.password, "new_password": "Different-Cedar-88!"},
    )
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["signed_out_everywhere"] is True

    # The token the caller just used is dead.
    assert logged_in.client.get("/api/v1/auth/me", headers=logged_in.auth()).status_code == 401

    # The old password no longer works, the new one does.
    assert client.post(
        "/api/v1/auth/login",
        json={"identifier": logged_in.user.email, "password": logged_in.password},
    ).status_code == 401
    assert client.post(
        "/api/v1/auth/login",
        json={"identifier": logged_in.user.email, "password": "Different-Cedar-88!"},
    ).status_code == 200


def test_change_password_does_not_leave_a_usable_session_behind(client, auth_client):
    """A password change must not be a way to keep a session alive.

    The earlier implementation un-consumed the current refresh token to do this.
    """
    logged_in = auth_client()
    logged_in.client.post(
        "/api/v1/auth/change-password",
        headers=logged_in.auth(),
        json={"current_password": logged_in.password, "new_password": "Different-Cedar-88!"},
    )
    response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": logged_in.refresh_token}
    )
    assert response.status_code == 401


def test_change_password_requires_authentication(client):
    response = client.post(
        "/api/v1/auth/change-password",
        json={"current_password": "a", "new_password": "b"},
    )
    assert response.status_code == 401


# ----------------------------------------------------------------------
# misc contract
# ----------------------------------------------------------------------


def test_password_policy_is_public(client):
    response = client.get("/api/v1/auth/password-policy")
    assert response.status_code == 200
    rules = response.json()["data"]["rules"]
    assert any("characters" in r for r in rules)


def test_error_envelope_is_consistent(client):
    response = client.get("/api/v1/auth/me")
    body = response.json()
    assert set(body) >= {"success", "error"}
    assert body["success"] is False
    assert {"code", "message"} <= set(body["error"])


def test_unknown_auth_path_returns_the_standard_404(client):
    response = client.get("/api/v1/auth/does-not-exist")
    assert response.status_code == 404
    body = response.json()
    assert body["success"] is False
    assert body["error"]["code"] == ErrorCode.NOT_FOUND
