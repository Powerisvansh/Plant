"""Role and permission seeding.

Idempotent. Safe to run on every deploy: existing rows are updated to match the
catalogue, never deleted. A permission that disappears from
:mod:`app.security.rbac` is revoked rather than left orphaned, so a permission
removed in code really stops working.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.logging_config import get_logger
from app.models.identity import Permission, Role, RolePermission
from app.security.rbac import (
    DANGEROUS_PERMISSIONS,
    PERMISSION_CATALOGUE,
    ROLE_DEFINITIONS,
    all_permission_codes,
)

logger = get_logger(__name__)


@dataclass
class SeedReport:
    permissions_created: int = 0
    permissions_updated: int = 0
    roles_created: int = 0
    roles_updated: int = 0
    links_created: int = 0
    links_deleted: int = 0

    def as_dict(self) -> dict[str, int]:
        return {
            "permissions_created": self.permissions_created,
            "permissions_updated": self.permissions_updated,
            "roles_created": self.roles_created,
            "roles_updated": self.roles_updated,
            "role_permission_links_created": self.links_created,
            "role_permission_links_revoked": self.links_deleted,
        }


def _permission_description(code: str) -> str:
    resource, _, action = code.partition(":")
    _, actions = PERMISSION_CATALOGUE[resource]
    noun = PERMISSION_CATALOGUE[resource][0].lower()
    verb = {
        "read": "View",
        "write": "Create and edit",
        "verify": "Verify",
        "delete": "Permanently delete",
        "run": "Start",
        "export": "Export",
    }[action]
    assert actions  # keeps the catalogue honest
    return f"{verb} {noun} ({resource}.{action})"


def seed_roles_and_permissions(session: Session) -> SeedReport:
    """Create or reconcile roles, permissions and their links."""
    report = SeedReport()

    # --- permissions -----------------------------------------------------
    existing: dict[str, Permission] = {
        code: perm
        for perm in session.execute(select(Permission)).scalars()
        for code in [perm.code]
    }

    catalogue = all_permission_codes()
    by_code: dict[str, Permission] = {}
    for code in catalogue:
        description = _permission_description(code)
        dangerous = code in DANGEROUS_PERMISSIONS
        perm = existing.get(code)
        if perm is None:
            perm = Permission(
                code=code,
                description=description,
                resource=code.partition(":")[0],
                action=code.partition(":")[2],
                is_dangerous=dangerous,
            )
            session.add(perm)
            report.permissions_created += 1
        else:
            if perm.description != description or perm.is_dangerous != dangerous:
                perm.description = description
                perm.is_dangerous = dangerous
                report.permissions_updated += 1
        by_code[code] = perm

    # Revoke permissions that no longer exist in the catalogue.
    for code, perm in existing.items():
        if code not in by_code:
            session.execute(
                RolePermission.__table__.delete().where(
                    RolePermission.__table__.c.permission_id == perm.id
                )
            )
            session.delete(perm)
            logger.warning("revoked_permission_removed_from_catalogue", extra={"code": code})

    session.flush()

    # --- roles -----------------------------------------------------------
    roles: dict[str, Role] = {
        role.name: role for role in session.execute(select(Role)).scalars()
    }

    for definition in ROLE_DEFINITIONS:
        role = roles.get(definition.name)
        if role is None:
            role = Role(
                name=definition.name,
                description=definition.description,
                priority=definition.priority,
                is_system=True,
            )
            session.add(role)
            report.roles_created += 1
        else:
            changed = (
                role.description != definition.description
                or role.priority != definition.priority
            )
            role.description = definition.description
            role.priority = definition.priority
            # System roles are never user-deletable.
            role.is_system = True
            if changed:
                report.roles_updated += 1
        roles[definition.name] = role

    session.flush()

    # --- links -----------------------------------------------------------
    for definition in ROLE_DEFINITIONS:
        role = roles[definition.name]
        current = {
            link.permission_id: link
            for link in session.execute(
                select(RolePermission).where(RolePermission.role_id == role.id)
            ).scalars()
        }
        wanted_ids = {by_code[code].id for code in definition.permissions}

        for permission_id in current:
            if permission_id not in wanted_ids:
                session.delete(current[permission_id])
                report.links_deleted += 1

        for permission_id in wanted_ids:
            if permission_id not in current:
                session.add(RolePermission(role_id=role.id, permission_id=permission_id))
                report.links_created += 1

    return report
