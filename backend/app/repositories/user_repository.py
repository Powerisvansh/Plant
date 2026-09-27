"""All database access for users, profiles and roles.

Repositories return ORM objects; they never format HTTP responses. Every query
that touches a user is explicit about soft-deleted rows, because a deleted
account must stop authenticating but must not vanish from the audit trail.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import datetime

from sqlalchemy import Select, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.models.identity import Role, User, UserProfile, UserRole
from app.models.session import UserSession


class UserRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    # -- reads ----------------------------------------------------------
    def _base_query(self, *, include_deleted: bool = False) -> Select:
        stmt = select(User).options(
            selectinload(User.roles).selectinload(UserRole.role),
            selectinload(User.profile),
        )
        if not include_deleted:
            stmt = stmt.where(User.deleted_at.is_(None))
        return stmt

    def get(self, user_id: uuid.UUID, *, include_deleted: bool = False) -> User | None:
        return self.session.execute(
            self._base_query(include_deleted=include_deleted).where(User.id == user_id)
        ).scalar_one_or_none()

    def get_by_email(
        self, email_normalised: str, *, include_deleted: bool = False
    ) -> User | None:
        if not email_normalised:
            return None
        return self.session.execute(
            self._base_query(include_deleted=include_deleted).where(
                User.email_normalised == email_normalised
            )
        ).scalar_one_or_none()

    def get_by_phone(
        self, phone_e164: str, *, include_deleted: bool = False
    ) -> User | None:
        if not phone_e164:
            return None
        return self.session.execute(
            self._base_query(include_deleted=include_deleted).where(
                User.phone_e164 == phone_e164
            )
        ).scalar_one_or_none()

    def get_by_identifier(
        self, *, email_normalised: str | None, phone_e164: str | None
    ) -> User | None:
        """Look a user up by whichever identifier was supplied.

        Both are checked because a user may have registered with a phone and
        later added an email; either one must reach the same account.
        """
        if not email_normalised and not phone_e164:
            return None
        clauses = []
        if email_normalised:
            clauses.append(User.email_normalised == email_normalised)
        if phone_e164:
            clauses.append(User.phone_e164 == phone_e164)
        return self.session.execute(
            self._base_query().where(or_(*clauses)).limit(1)
        ).scalar_one_or_none()

    def email_taken(self, email_normalised: str, *, exclude_user_id: uuid.UUID | None = None) -> bool:
        stmt = select(func.count()).select_from(User).where(
            User.email_normalised == email_normalised,
            User.deleted_at.is_(None),
        )
        if exclude_user_id:
            stmt = stmt.where(User.id != exclude_user_id)
        return bool(self.session.execute(stmt).scalar_one())

    def phone_taken(self, phone_e164: str, *, exclude_user_id: uuid.UUID | None = None) -> bool:
        stmt = select(func.count()).select_from(User).where(
            User.phone_e164 == phone_e164,
            User.deleted_at.is_(None),
        )
        if exclude_user_id:
            stmt = stmt.where(User.id != exclude_user_id)
        return bool(self.session.execute(stmt).scalar_one())

    def list_users(
        self,
        *,
        search: str | None = None,
        status: str | None = None,
        is_active: bool | None = None,
        include_deleted: bool = False,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[Sequence[User], int]:
        stmt = self._base_query(include_deleted=include_deleted)
        count_stmt = select(func.count()).select_from(User)
        if not include_deleted:
            stmt = stmt.where(User.deleted_at.is_(None))
            count_stmt = count_stmt.where(User.deleted_at.is_(None))
        if search:
            pattern = f"%{search.strip().lower()}%"
            clause = or_(
                func.lower(User.full_name).like(pattern),
                func.lower(User.email_normalised).like(pattern),
                User.phone_e164.like(f"%{search.strip()}%"),
            )
            stmt = stmt.where(clause)
            count_stmt = count_stmt.where(clause)
        if status:
            stmt = stmt.where(User.status == status)
            count_stmt = count_stmt.where(User.status == status)
        if is_active is not None:
            stmt = stmt.where(User.is_active.is_(is_active))
            count_stmt = count_stmt.where(User.is_active.is_(is_active))

        total = int(self.session.execute(count_stmt).scalar_one())
        rows = self.session.execute(
            stmt.order_by(User.created_at.desc()).limit(limit).offset(offset)
        ).scalars().all()
        return rows, total

    def count_by_status(self) -> dict[str, int]:
        rows = self.session.execute(
            select(User.status, func.count()).group_by(User.status)
        ).all()
        return {str(status): int(count) for status, count in rows}

    # -- writes ---------------------------------------------------------
    def add(self, user: User) -> User:
        self.session.add(user)
        return user

    def add_profile(self, profile: UserProfile) -> UserProfile:
        self.session.add(profile)
        return profile

    def assign_role(
        self,
        user: User,
        role: Role,
        *,
        assigned_by: uuid.UUID | None = None,
    ) -> UserRole:
        """Grant a role. Idempotent: a repeat grant returns the existing link."""
        existing = self.session.execute(
            select(UserRole).where(UserRole.user_id == user.id, UserRole.role_id == role.id)
        ).scalar_one_or_none()
        if existing is not None:
            return existing
        link = UserRole(user_id=user.id, role_id=role.id, assigned_by=assigned_by)
        self.session.add(link)
        return link

    def remove_role(self, user: User, role: Role) -> bool:
        link = self.session.execute(
            select(UserRole).where(UserRole.user_id == user.id, UserRole.role_id == role.id)
        ).scalar_one_or_none()
        if link is None:
            return False
        self.session.delete(link)
        return True

    def roles(self) -> Sequence[Role]:
        return self.session.execute(
            select(Role).order_by(Role.priority.desc())
        ).scalars().all()

    def get_role(self, name: str) -> Role | None:
        return self.session.execute(
            select(Role).where(Role.name == name.upper())
        ).scalar_one_or_none()

    def role_names(self, user: User) -> set[str]:
        return {ur.role.name for ur in user.roles if ur.role is not None}


class SessionRepository:
    """Server-side session records, the authority on whether a token is live."""

    def __init__(self, session: Session) -> None:
        self.session = session

    def add(self, record: UserSession) -> UserSession:
        self.session.add(record)
        return record

    def get(self, session_id: uuid.UUID) -> UserSession | None:
        return self.session.execute(
            select(UserSession)
            .options(selectinload(UserSession.user).selectinload(User.roles))
            .where(UserSession.id == session_id)
        ).scalar_one_or_none()

    def list_for_user(
        self, user: User, *, include_revoked: bool = False
    ) -> Sequence[UserSession]:
        stmt = select(UserSession).where(UserSession.user_id == user.id)
        if not include_revoked:
            stmt = stmt.where(UserSession.revoked_at.is_(None))
        return self.session.execute(
            stmt.order_by(UserSession.last_seen_at.desc().nulls_last(), UserSession.created_at.desc())
        ).scalars().all()

    def active_count(self, user_id: uuid.UUID) -> int:
        from app.models.session import SessionRevokeReason  # noqa: F401

        return int(
            self.session.execute(
                select(func.count())
                .select_from(UserSession)
                .where(
                    UserSession.user_id == user_id,
                    UserSession.revoked_at.is_(None),
                    UserSession.expires_at > func.now(),
                )
            ).scalar_one()
        )

    def revoke_all(
        self,
        user_id: uuid.UUID,
        *,
        reason: str,
        except_session_id: uuid.UUID | None = None,
        revoked_at: datetime | None = None,
    ) -> int:
        from app.core.timeutils import now_utc

        revoked_at = revoked_at or now_utc()
        stmt = (
            select(UserSession)
            .where(
                UserSession.user_id == user_id,
                UserSession.revoked_at.is_(None),
            )
            .with_for_update()
        )
        if except_session_id is not None:
            stmt = stmt.where(UserSession.id != except_session_id)
        rows = self.session.execute(stmt).scalars().all()
        for row in rows:
            row.revoked_at = revoked_at
            row.revoked_reason = reason
        return len(rows)
