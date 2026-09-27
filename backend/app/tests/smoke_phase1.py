"""PHASE 1 smoke test: the server boots and every foundation endpoint answers.

Run with:  .venv/bin/python -m app.tests.smoke_phase1
"""

from __future__ import annotations

import sys

from fastapi.testclient import TestClient

from app.main import app

FAILURES: list[str] = []


def check(label: str, condition: bool, extra: str = "") -> None:
    mark = "PASS" if condition else "FAIL"
    print(f"[{mark}] {label}{(' -- ' + extra) if extra else ''}")
    if not condition:
        FAILURES.append(label)


def main() -> int:
    with TestClient(app) as client:
        r = client.get("/health")
        check("GET /health -> 200", r.status_code == 200, r.text[:160])
        check("  reports version", r.json().get("version") == "1.0.0")

        r = client.get("/health/database")
        body = r.json()
        check("GET /health/database -> 200", r.status_code == 200, r.text[:200])
        check(
            "  knowledge schema present",
            body.get("checks", {}).get("knowledge_schema") == "present",
        )
        check(
            "  app schema present (Alembic applied)",
            body.get("checks", {}).get("app_schema") == "present",
            str(body.get("checks", {}).get("app_schema")),
        )
        check(
            "  app revision reported",
            bool(body.get("checks", {}).get("app_revision")),
            str(body.get("checks", {}).get("app_revision")),
        )
        check(
            "  all 18 knowledge migrations applied",
            body.get("checks", {}).get("knowledge_migrations_applied") == 18,
            str(body.get("checks", {}).get("knowledge_migrations_applied")),
        )

        r = client.get("/health/redis")
        check("GET /health/redis -> 200", r.status_code == 200, r.text[:160])

        r = client.get("/api/v1/health")
        check("GET /api/v1/health -> 200", r.status_code == 200, r.text[:160])

        r = client.get("/openapi.json")
        check("GET /openapi.json -> 200", r.status_code == 200)
        check("  title correct", r.json().get("info", {}).get("title") == "PlantDoctor Server")

        r = client.get("/docs")
        check("GET /docs -> 200 (Swagger UI)", r.status_code == 200)

        r = client.get("/redoc")
        check("GET /redoc -> 200 (ReDoc)", r.status_code == 200)

        r = client.get("/nope-does-not-exist")
        body = r.json()
        check("unknown path -> 404 envelope", r.status_code == 404, r.text[:160])
        check(
            "  error envelope shape",
            body.get("success") is False
            and "code" in body.get("error", {})
            and "message" in body.get("error", {}),
        )
        check("  no stack trace leaked", "Traceback" not in r.text)

        # Security headers
        r = client.get("/health")
        for header, expected in (
            ("x-content-type-options", "nosniff"),
            ("x-frame-options", "DENY"),
            ("referrer-policy", "no-referrer"),
        ):
            check(f"header {header}={expected}", r.headers.get(header) == expected)
        check("X-Request-ID echoed", bool(r.headers.get("x-request-id")))

        # Legacy knowledge-base app is still mounted and functional.
        r = client.get("/legacy/health")
        check("GET /legacy/health -> 200 (legacy app intact)", r.status_code == 200, r.text[:160])
        r = client.get("/legacy/plants")
        check("GET /legacy/plants -> 200 (legacy KB intact)", r.status_code == 200)
        r = client.get("/legacy/sources")
        check("GET /legacy/sources -> 200 (source registry)", r.status_code == 200)

    print()
    if FAILURES:
        print(f"PHASE 1 SMOKE: {len(FAILURES)} FAILURE(S): {FAILURES}")
        return 1
    print("PHASE 1 SMOKE: ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
