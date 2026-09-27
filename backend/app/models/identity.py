"""Identity: roles, permissions, users, profiles.

Passwords are stored only as an Argon2id hash. The plaintext never reaches
this layer, and ``password_hash`` is excluded from every serialisation schema.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import (
    SoftDeleteMixin,
    TimestampMixin,
    UUIDPrimaryKeyMixin,
    new_uuid,
)
from app.models.enums import UserStatus


class Role(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """SUPER_ADMIN, ADMIN, EXPERT, USER.

    ``is_system`` rows cannot be deleted or renamed; only their permission set
    can be adjusted. This is what makes the four required roles trustworthy.
    """

    __tablename__ = "roles"

    name: Mapped[str] = mapped_column(String(32), unique=True, nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    is_system: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default=text("true"))
    priority: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0"),
        doc="Higher wins when several roles are held.",
    )

    permissions: Mapped[list["RolePermission"]] = relationship(
        back_populates="role", cascade="all, delete-orphan", lazy="selectin"
    )
    users: Mapped[list["UserRole"]] = relationship(
        back_populates="role", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:  # pragma: no cover
        return f"<Role {self.name}>"


class Permission(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """``resource:action``, e.g. ``plants:write``. Checked by RBAC guards."""

    __tablename__ = "permissions"

    code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    resource: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    action: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    is_dangerous: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false"),
        doc="Dangerous permissions are logged individually in audit_logs.",
    )

    roles: Mapped[list["RolePermission"]] = relationship(
        back_populates="permission", cascade="all, delete-orphan"
    )

    __table_args__ = (
        UniqueConstraint("resource", "action", name="uq_permissions_resource_action"),
    )


class RolePermission(UUIDPrimaryKeyMixin, Base):
    __tablename__ = "role_permissions"

    role_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("roles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    permission_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("permissions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    role: Mapped[Role] = relationship(back_populates="permissions")
    permission: Mapped[Permission] = relationship(back_populates="roles", lazy="selectin")

    __table_args__ = (
        UniqueConstraint("role_id", "permission_id", name="uq_role_permission"),
    )


class User(UUIDPrimaryKeyMixin, TimestampMixin, SoftDeleteMixin, Base):
    """An account.

    ``email_normalised`` and ``phone_e164`` carry a unique index that is
    *partial* (``WHERE deleted_at IS NULL``), so an account deleted for privacy
    no longer blocks the same address from registering again.
    """

    __tablename__ = "users"

    full_name: Mapped[str] = mapped_column(String(160), nullable=False)
    email: Mapped[str | None] = mapped_column(String(320))
    email_normalised: Mapped[str | None] = mapped_column(String(320))
    phone_e164: Mapped[str | None] = mapped_column(String(20))
    phone_display: Mapped[str | None] = mapped_column(String(32))

    password_hash: Mapped[str] = mapped_column(
        String(255), nullable=False, doc="Argon2id PHC string. Never serialised."
    )
    password_changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    status: Mapped[UserStatus] = mapped_column(
        String(24), nullable=False, default=UserStatus.PENDING_VERIFICATION, index=True
    )
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    phone_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true"), index=True
    )
    is_staff: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false"), index=True
    )
    is_superuser: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default=text("false")
    )

    # Brute-force protection. Counters reset on a successful login.
    failed_login_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default=text("0")
    )
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_ip: Mapped[str | None] = mapped_column(String(45))

    terms_accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    data_export_requested_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    profile: Mapped["UserProfile | None"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    roles: Mapped[list["UserRole"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        lazy="selectin",
        # user_roles.assigned_by is also a users foreign key; without this the
        # join is ambiguous.
        foreign_keys="UserRole.user_id",
    )

    __table_args__ = (
        Index(
            "uq_users_email_normalised_active",
            "email_normalised",
            unique=True,
            postgresql_where=text("deleted_at IS NULL AND email_normalised IS NOT NULL"),
        ),
        Index(
            "uq_users_phone_e164_active",
            "phone_e164",
            unique=True,
            postgresql_where=text("deleted_at IS NULL AND phone_e164 IS NOT NULL"),
        ),
        Index("ix_users_status_email", "status", "email_normalised"),
    )

    # -- helpers --------------------------------------------------------
    @property
    def is_verified(self) -> bool:
        return self.email_verified_at is not None or self.phone_verified_at is not None

    @property
    def is_locked(self) -> bool:
        from app.core.timeutils import now_utc

        return self.locked_until is not None and self.locked_until > now_utc()

    @property
    def role_names(self) -> set[str]:
        return {ur.role.name for ur in self.roles if ur.role is not None}

    def has_role(self, *names: str) -> bool:
        wanted = {n.upper() for n in names}
        return bool(self.role_names & wanted)

    def __repr__(self) -> str:  # pragma: no cover
        return f"<User {self.email_normalised or self.phone_e164 or self.id}>"


class UserRole(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "user_roles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("roles.id", ondelete="CASCADE"), nullable=False, index=True
    )
    assigned_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    #: ``user_roles`` references ``users`` twice (the holder and the granting
    #: admin), so each relationship must name its own column.
    user: Mapped[User] = relationship(back_populates="roles", foreign_keys=[user_id])
    granted_by: Mapped[User | None] = relationship(foreign_keys=[assigned_by])
    role: Mapped[Role] = relationship(back_populates="users", lazy="selectin")

    __table_args__ = (UniqueConstraint("user_id", "role_id", name="uq_user_role"),)


class UserProfile(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Optional presentation data. Kept apart from ``users`` so the auth tables
    stay small and a profile can be deleted without touching credentials."""

    __tablename__ = "user_profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    display_name: Mapped[str | None] = mapped_column(String(120))
    bio: Mapped[str | None] = mapped_column(String(500))
    avatar_file_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("stored_files.id", ondelete="SET NULL"), nullable=True
    )
    locale: Mapped[str] = mapped_column(
        String(12), nullable=False, default="en-IN", server_default=text("'en-IN'")
    )
    timezone: Mapped[str] = mapped_column(
        String(64), nullable=False, default="Asia/Kolkata", server_default=text("'Asia/Kolkata'")
    )
    country_code: Mapped[str | None] = mapped_column(String(2))
    region: Mapped[str | None] = mapped_column(String(120))
    city: Mapped[str | None] = mapped_column(String(120))
    experience_level: Mapped[str | None] = mapped_column(String(40))

    preferences: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default=text("'{}'::jsonb")
    )
    notification_preferences: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default=text("'{}'::jsonb")
    )

    user: Mapped[User] = relationship(back_populates="profile")

    def as_preferences(self) -> dict:
        return self.preferences or {}


def new_user_id() -> uuid.UUID:
    return new_uuid()
