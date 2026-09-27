"""PHASE 2 smoke test: schema, migration and RBAC invariants.

Run with:  .venv/bin/python -m app.tests.smoke_phase2

This is a real verification, not a mock. It talks to the live PostgreSQL
database, asserts the Alembic revision is applied, and proves the RBAC
catalogue is internally consistent and seeded into the database.
"""

from __future__ import annotations

import sys

from sqlalchemy import inspect, select, text

from app.database.session import session_scope
from app.models import APPLICATION_TABLES, Base
from app.models.identity import Permission, Role, RolePermission, UserRole
from app.security.rbac import (
    ADMIN_ROLES,
    DANGEROUS_PERMISSIONS,
    ROLE_BY_NAME,
    ROLE_DEFINITIONS,
    all_permission_codes,
)
from app.security.passwords import (
    hash_password,
    needs_rehash,
    password_strength_score,
    validate_password_strength,
    verify_password,
)
from app.services.audit_service import AuditService, redact
from app.services.role_service import seed_roles_and_permissions

FAILURES: list[str] = []


def check(label: str, condition: bool, extra: str = "") -> None:
    mark = "PASS" if condition else "FAIL"
    print(f"[{mark}] {label}{(' -- ' + extra) if extra else ''}")
    if not condition:
        FAILURES.append(label)


def check_schema() -> None:
    print("\n-- database schema --")

    # Enum-typed columns are mapped as String, so a value read back is a plain
    # str. It is never identical to the StrEnum member, which makes
    # ``user.status is UserStatus.X`` silently False for every row - a branch
    # that looks like it runs and never does. ``==`` works in both directions
    # because the enum subclasses str, so the rule is simply "never use is".
    import re
    from pathlib import Path

    app_dir = Path(__file__).resolve().parents[1]
    enum_attr = re.compile(r"\b\w+(?:\.\w+)*\s+is\s+(?:not\s+)?UserStatus\.\w+")
    offenders: list[str] = []
    for path in sorted(app_dir.rglob("*.py")):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith(("#", "*")):
                continue
            if enum_attr.search(line):
                offenders.append(f"{path.name}:{lineno}")
    check(
        "no 'is' comparison against a UserStatus member",
        not offenders,
        str(offenders),
    )

    # Two indexes in one table cannot share a name. SQLAlchemy resolves the
    # collision silently by keeping the first, so a composite index can vanish
    # from the migration without a single warning. This has already happened
    # twice (diagnosis_results, database_backups); the check stops it a third.
    for table_name, table in sorted(Base.metadata.tables.items()):
        names = [ix.name for ix in table.indexes]
        duplicates = {n for n in names if names.count(n) > 1}
        check(
            f"{table_name}: no duplicate index names",
            not duplicates,
            str(sorted(duplicates)),
        )
        # A plain UNIQUE index over a nullable column does not enforce what it
        # looks like it enforces: NULL <> NULL in SQL, so a second NULL row is
        # accepted. Any such index has to be partial to mean anything.
        weak_unique = [
            ix.name
            for ix in table.indexes
            if ix.unique
            and any(c.nullable for c in ix.columns)
            and ix.dialect_options.get("postgresql", {}).get("where") is None
        ]
        check(
            f"{table_name}: unique index over a nullable column is partial",
            not weak_unique,
            str(weak_unique),
        )

    with session_scope() as session:
        inspector = inspect(session.connection())

        tables = set(inspector.get_table_names())
        app_tables = set(APPLICATION_TABLES)
        knowledge_tables = set(Base.metadata.tables) - app_tables

        check(
            f"all {len(app_tables)} application tables exist",
            app_tables <= tables,
            f"missing={sorted(app_tables - tables)}",
        )
        check(
            "knowledge tables present but not application-owned",
            knowledge_tables <= tables and not (knowledge_tables & app_tables),
            f"kb={len(knowledge_tables)}",
        )

        revision = session.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar()
        from alembic.config import Config
        from alembic.script import ScriptDirectory

        head = ScriptDirectory.from_config(Config("alembic.ini")).get_current_head()
        check(
            f"alembic_version is at head ({head})",
            revision == head,
            f"db={revision} head={head}",
        )

        # The knowledge base must be untouched by the app migration.
        kb_tables = {
            "plants",
            "diseases",
            "symptoms",
            "pests",
            "treatments",
            "treatment_products",
            "sources",
            "active_ingredients",
        }
        check(
            "knowledge tables all present",
            kb_tables <= tables,
            f"missing={sorted(kb_tables - tables)}",
        )

        plant_count = session.execute(text("SELECT count(*) FROM plants")).scalar()
        check("knowledge rows intact (41 plants)", plant_count == 41, f"got {plant_count}")

        # BigInt mixin must really produce BIGINT.
        audit_id_type = session.execute(
            text(
                "SELECT data_type FROM information_schema.columns "
                "WHERE table_name='audit_logs' AND column_name='id'"
            )
        ).scalar()
        check("audit_logs.id is bigint", audit_id_type == "bigint", str(audit_id_type))

        # Real FKs into the knowledge base, with the correct ON DELETE action.
        result_fks = {
            fk["referred_table"]: fk
            for fk in inspector.get_foreign_keys("diagnosis_results")
        }
        check(
            "diagnosis_results -> diseases is a real FK",
            "diseases" in result_fks,
            str(sorted(result_fks)),
        )
        check(
            "  candidate FK is ON DELETE SET NULL",
            result_fks.get("diseases", {}).get("options", {}).get("ondelete") == "SET NULL",
            str(result_fks.get("diseases", {}).get("options")),
        )
        check(
            "  diagnoses FK is ON DELETE CASCADE",
            result_fks.get("diagnoses", {}).get("options", {}).get("ondelete") == "CASCADE",
        )
        check(
            "  all candidate FKs target BIGINT knowledge ids",
            all(
                fk["referred_columns"] == ["id"] for fk in result_fks.values()
            ),
        )

        indexes = {ix["name"] for ix in inspector.get_indexes("diagnosis_results")}
        check(
            "composite result index present",
            "ix_diagnosis_results_diag_kind_rank" in indexes,
            str(sorted(indexes)),
        )


def check_rbac_catalogue() -> None:
    print("\n-- RBAC catalogue --")
    codes = set(all_permission_codes())
    check("permission catalogue is non-empty", len(codes) >= 40, f"{len(codes)} codes")
    check(
        "every code is resource:action",
        all(":" in c and c.split(":")[0] and c.split(":")[1] for c in codes),
    )

    for name in ("USER", "EXPERT", "ADMIN", "SUPER_ADMIN"):
        check(f"role {name} defined", name in ROLE_BY_NAME)

    user = ROLE_BY_NAME["USER"]
    expert = ROLE_BY_NAME["EXPERT"]
    admin = ROLE_BY_NAME["ADMIN"]
    super_admin = ROLE_BY_NAME["SUPER_ADMIN"]

    check(
        "USER only reads knowledge",
        all(c.endswith(":read") for c in user.permissions),
        str(sorted(user.permissions)),
    )
    check("EXPERT cannot manage users", not any(c.startswith("users:") for c in expert.permissions))
    check("EXPERT cannot write settings", "system_settings:write" not in expert.permissions)
    check("ADMIN cannot assign roles", "roles:write" not in admin.permissions)
    check("ADMIN cannot delete accounts", "users:delete" not in admin.permissions)
    check(
        "ADMIN cannot run or delete backups",
        not ({"backups:run", "backups:delete"} & admin.permissions),
    )
    check("SUPER_ADMIN holds every code", super_admin.permissions >= codes)

    check(
        "privilege is monotone USER<=EXPERT<=ADMIN<=SUPER_ADMIN",
        user.permissions <= expert.permissions <= admin.permissions <= super_admin.permissions,
    )
    check(
        "permissions never escalate via ADMIN_ROLES alone",
        set(ADMIN_ROLES) == {"ADMIN", "SUPER_ADMIN"},
        str(sorted(ADMIN_ROLES)),
    )
    check(
        "dangerous set is a subset of the catalogue",
        DANGEROUS_PERMISSIONS <= codes,
        f"unknown={sorted(DANGEROUS_PERMISSIONS - codes)}",
    )
    check(
        "all dangerous permissions belong to admin or above",
        all(
            ROLE_BY_NAME[r].permissions & DANGEROUS_PERMISSIONS
            for r in ("ADMIN", "SUPER_ADMIN")
        ),
    )


def check_seed_is_applied() -> None:
    print("\n-- role seed in database --")
    with session_scope() as session:
        roles = {r.name: r for r in session.execute(select(Role)).scalars()}
        check("4 system roles in database", set(roles) == set(ROLE_BY_NAME), str(sorted(roles)))
        check("all roles are system roles", all(r.is_system for r in roles.values()))
        check(
            "SUPER_ADMIN has the highest priority",
            roles["SUPER_ADMIN"].priority > roles["ADMIN"].priority,
        )

        perms = {p.code: p for p in session.execute(select(Permission)).scalars()}
        check("50 permissions seeded", len(perms) == 50, f"got {len(perms)}")

        links = {
            (link.role_id, link.permission_id)
            for link in session.execute(select(RolePermission)).scalars()
        }
        expected_links = {
            (roles[d.name].id, perms[c].id)
            for d in ROLE_DEFINITIONS
            for c in d.permissions
        }
        check(
            "role_permission links match the catalogue exactly",
            links == expected_links,
            f"extra={len(links - expected_links)} missing={len(expected_links - links)}",
        )

        granted = {
            code
            for code, perm in perms.items()
            if any(
                link.permission_id == perm.id and roles["SUPER_ADMIN"].id == link.role_id
                for link in session.execute(
                    select(RolePermission).where(
                        RolePermission.role_id == roles["SUPER_ADMIN"].id
                    )
                ).scalars()
            )
        }
        check("SUPER_ADMIN holds all 50 permissions", len(granted) == 50, f"got {len(granted)}")

    # Idempotency: a second run must change nothing.
    with session_scope() as session:
        report = seed_roles_and_permissions(session)
    zero = report.as_dict()
    check(
        "re-running seed-roles is a no-op",
        all(value == 0 for value in zero.values()),
        str(zero),
    )


def check_passwords() -> None:
    print("\n-- Argon2id password handling --")
    encoded = hash_password("correct horse battery staple 42")
    check("hash is an Argon2id PHC string", encoded.startswith("$argon2id$"), encoded[:24])
    check("plaintext is not in the hash", "correct horse" not in encoded)
    check("correct password verifies", verify_password("correct horse battery staple 42", encoded))
    check("wrong password does not verify", not verify_password("wrong horse", encoded))
    check("empty hash never verifies", not verify_password("anything", ""))
    check("malformed hash never verifies", not verify_password("x", "not-a-hash"))
    check("current parameters need no rehash", not needs_rehash(encoded))
    check("weak parameters are flagged for rehash", needs_rehash("$argon2id$v=19$m=8,t=1,p=1$" + "$" * 43))

    from app.core.errors import AppError

    for bad, label in [
        ("short1", "too short"),
        ("password123", "common password"),
        ("qwertyuiop12", "keyboard sequence"),
        ("aaaaaaaaaaaa1", "repeated character"),
    ]:
        try:
            validate_password_strength(bad)
            check(f"policy rejects {label}", False, repr(bad))
        except AppError:
            check(f"policy rejects {label}", True)

    try:
        validate_password_strength(
            "my email is 2008@x.com", email="2008@x.com"
        )
        check("policy rejects a password containing the email", False)
    except AppError:
        check("policy rejects a password containing the email", True)

    validate_password_strength("Tr0ubador!and3 more")
    check("policy accepts a strong password", True)

    score = password_strength_score("password123")
    check("common password scores 0/4", score["score"] == 0, str(score))


def check_audit_redaction() -> None:
    print("\n-- audit redaction --")
    payload = {
        "password": "hunter2",
        "user": {"email": "a@b.c", "refresh_token": "rt_abc"},
        "items": [{"otp_code": "123456"}, {"name": "ok"}],
    }
    safe = redact(payload)
    check("top-level secret redacted", safe["password"] == "[REDACTED]")
    check("nested secret redacted", safe["user"]["refresh_token"] == "[REDACTED]")
    check("list item secret redacted", safe["items"][0]["otp_code"] == "[REDACTED]")
    check("non-secret preserved", safe["user"]["email"] == "a@b.c")
    check("plaintext never survives", "hunter2" not in str(safe))

    with session_scope() as session:
        entry = AuditService.record(
            session,
            action="test.action",
            resource_type="test",
            changes=payload,
            is_dangerous=False,
        )
        check("dangerous action auto-flagged by name", not entry.is_dangerous)
        entry2 = AuditService.record(
            session,
            action="users:delete",
            resource_type="user",
            changes=None,
        )
        check("permission-coded action is flagged dangerous", entry2.is_dangerous)

    with session_scope() as session:
        found = AuditService.query(session, action="test.action")
        check("audit row is queryable", len(found) >= 1, f"got {len(found)}")
        check(
            "every stored change set is redacted",
            all("hunter2" not in str(row.changes) for row in found),
        )
        check(
            "audit rows are newest-first",
            [row.occurred_at for row in found]
            == sorted((row.occurred_at for row in found), reverse=True),
        )

    with session_scope() as session:
        dangerous = AuditService.query(session, is_dangerous=True)
        check(
            "denied/dangerous rows are flagged and queryable",
            len(dangerous) >= 1
            and all(row.is_dangerous for row in dangerous),
            f"got {len(dangerous)}",
        )


def main() -> int:
    check_schema()
    check_rbac_catalogue()
    check_seed_is_applied()
    check_passwords()
    check_audit_redaction()

    print()
    if FAILURES:
        print(f"PHASE 2 SMOKE: {len(FAILURES)} FAILURE(S):")
        for failure in FAILURES:
            print(f"  - {failure}")
        return 1
    print("PHASE 2 SMOKE: ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
