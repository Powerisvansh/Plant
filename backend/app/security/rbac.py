"""Role-based access control.

The four required roles are declared here as data, so the permission matrix is
readable and reviewable rather than scattered through the code.

Enforcement has two independent layers:

* **Route level** - :func:`require_permission` / :func:`require_roles`
  dependencies reject a request before a handler runs.
* **Record level** - repositories always filter by the authenticated subject, so
  a missing route check degrades to "the user cannot see other people's rows",
  never to "the user sees everything".
"""

from __future__ import annotations

from dataclasses import dataclass

# --------------------------------------------------------------------------
# Permission catalogue
# --------------------------------------------------------------------------

READ = "read"
WRITE = "write"
VERIFY = "verify"
DELETE = "delete"
RUN = "run"
EXPORT = "export"

#: resource -> (description, [actions])
PERMISSION_CATALOGUE: dict[str, tuple[str, tuple[str, ...]]] = {
    "plants": ("Plant and species knowledge base", (READ, WRITE, VERIFY, DELETE)),
    "diseases": ("Disease knowledge base", (READ, WRITE, VERIFY, DELETE)),
    "symptoms": ("Symptom and cause knowledge base", (READ, WRITE, VERIFY, DELETE)),
    "treatments": ("Treatment knowledge base", (READ, WRITE, VERIFY, DELETE)),
    "medicines": ("Registered products and active ingredients", (READ, WRITE, VERIFY, DELETE)),
    "doctors": ("Expert and doctor directory", (READ, WRITE, VERIFY, DELETE)),
    "sources": ("Provenance registry", (READ, WRITE, VERIFY)),
    "verification": ("Verification workflow", (READ, VERIFY, WRITE)),
    "users": ("User accounts", (READ, WRITE, DELETE, EXPORT)),
    "roles": ("Roles and permissions", (READ, WRITE)),
    "diagnoses": ("User diagnosis records", (READ, VERIFY, DELETE)),
    "imports": ("Knowledge import jobs", (RUN, READ)),
    "system_settings": ("Server configuration", (READ, WRITE)),
    "audit_logs": ("Audit trail", (READ, EXPORT)),
    "backups": ("Database backups", (READ, RUN, DELETE)),
    "notifications": ("User notifications", (READ, WRITE)),
}

#: Permissions that must always be individually written to audit_logs.
DANGEROUS_PERMISSIONS = frozenset(
    {
        "users:delete",
        "users:export",
        "roles:write",
        "system_settings:write",
        "plants:delete",
        "diseases:delete",
        "symptoms:delete",
        "treatments:delete",
        "medicines:delete",
        "doctors:delete",
        "backups:run",
        "backups:delete",
        "imports:run",
        "diagnoses:delete",
    }
)

PUBLIC_PERMISSIONS: tuple[str, ...] = (
    "plants:read",
    "diseases:read",
    "symptoms:read",
    "treatments:read",
    "medicines:read",
    "doctors:read",
    "sources:read",
)


def all_permission_codes() -> list[str]:
    codes: list[str] = []
    for resource, (_, actions) in PERMISSION_CATALOGUE.items():
        codes.extend(f"{resource}:{action}" for action in actions)
    return sorted(codes)


# --------------------------------------------------------------------------
# Role definitions
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class RoleDefinition:
    name: str
    description: str
    priority: int
    permissions: frozenset[str]


READ_ONLY_KNOWLEDGE = frozenset(PUBLIC_PERMISSIONS)

EXPERT_PERMISSIONS = READ_ONLY_KNOWLEDGE | frozenset(
    {
        "verification:read",
        "verification:verify",
        "diagnoses:read",
        "diagnoses:verify",
        "plants:write",
        "diseases:write",
        "symptoms:write",
        "treatments:write",
        "medicines:write",
        "doctors:write",
        "sources:write",
    }
)

ADMIN_PERMISSIONS = EXPERT_PERMISSIONS | frozenset(
    {
        "users:read",
        "users:write",
        "users:export",
        "verification:write",
        "plants:delete",
        "diseases:delete",
        "symptoms:delete",
        "treatments:delete",
        "medicines:delete",
        "doctors:delete",
        "verification:read",
        "imports:read",
        "system_settings:read",
        "audit_logs:read",
        "backups:read",
        "diagnoses:read",
        "diagnoses:delete",
    }
)

#: A super admin holds *every* code in the catalogue, derived rather than
#: listed. Spelling the 50 codes out by hand meant new permissions silently
#: failed to reach the super admin, which is exactly the bug a role definition
#: must not be able to have.
SUPER_ADMIN_PERMISSIONS = frozenset(all_permission_codes())

ROLE_DEFINITIONS: tuple[RoleDefinition, ...] = (
    RoleDefinition(
        name="USER",
        description=(
            "A registered, verified member of the public. Read access to verified "
            "knowledge only. Own plants, diagnoses and profile are governed by "
            "ownership, not by permission."
        ),
        priority=10,
        permissions=READ_ONLY_KNOWLEDGE,
    ),
    RoleDefinition(
        name="EXPERT",
        description=(
            "A verified agricultural expert, doctor or extension officer. May draft "
            "knowledge records and verify them, and may review diagnosis reports. "
            "Cannot manage users or change server settings."
        ),
        priority=20,
        permissions=EXPERT_PERMISSIONS,
    ),
    RoleDefinition(
        name="ADMIN",
        description=(
            "Day-to-day operations: manage users, knowledge, verification and "
            "sources, run imports, read audit logs. Cannot change roles, delete "
            "accounts, edit server settings, or run and delete backups."
        ),
        priority=30,
        permissions=ADMIN_PERMISSIONS,
    ),
    RoleDefinition(
        name="SUPER_ADMIN",
        description=(
            "Full control, including role assignment, account deletion, server "
            "settings, backup management and audit export. Every action is audited."
        ),
        priority=100,
        permissions=SUPER_ADMIN_PERMISSIONS,
    ),
)

ROLE_BY_NAME: dict[str, RoleDefinition] = {r.name: r for r in ROLE_DEFINITIONS}

STAFF_ROLES = frozenset({"EXPERT", "ADMIN", "SUPER_ADMIN"})
ADMIN_ROLES = frozenset({"ADMIN", "SUPER_ADMIN"})

assert ROLE_BY_NAME["USER"].permissions <= EXPERT_PERMISSIONS
assert EXPERT_PERMISSIONS <= ADMIN_PERMISSIONS
assert ADMIN_PERMISSIONS <= SUPER_ADMIN_PERMISSIONS, "role escalation must be monotone"
