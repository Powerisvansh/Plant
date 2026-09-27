"""Enumerations.

Every enum is a **native PostgreSQL type**, matching the style already used by
the knowledge-base migrations in ``backend/migrations``. The database therefore
rejects an invalid status even if a future code path forgets to validate it.

Values are stored by *name* (not ordinal), so reordering a Python enum can never
silently corrupt existing rows.
"""

from __future__ import annotations

import enum


class StrEnum(str, enum.Enum):
    """A string enum that serialises as its value."""

    def __str__(self) -> str:  # pragma: no cover - trivial
        return str(self.value)


class UserStatus(StrEnum):
    PENDING_VERIFICATION = "PENDING_VERIFICATION"
    ACTIVE = "ACTIVE"
    DISABLED = "DISABLED"
    DELETED = "DELETED"


class VerificationChannel(StrEnum):
    EMAIL = "EMAIL"
    SMS = "SMS"


class OtpPurpose(StrEnum):
    EMAIL_VERIFICATION = "EMAIL_VERIFICATION"
    PHONE_VERIFICATION = "PHONE_VERIFICATION"
    PASSWORD_RESET = "PASSWORD_RESET"
    LOGIN_CHALLENGE = "LOGIN_CHALLENGE"
    EMAIL_CHANGE = "EMAIL_CHANGE"


class RecordStatus(StrEnum):
    """Verification workflow for every knowledge record."""

    DRAFT = "DRAFT"
    REVIEW = "REVIEW"
    VERIFIED = "VERIFIED"
    REJECTED = "REJECTED"


class TokenType(StrEnum):
    ACCESS = "ACCESS"
    REFRESH = "REFRESH"


class SessionRevokeReason(StrEnum):
    LOGOUT = "LOGOUT"
    LOGOUT_ALL = "LOGOUT_ALL"
    ROTATED = "ROTATED"
    REUSE_DETECTED = "REUSE_DETECTED"
    PASSWORD_CHANGED = "PASSWORD_CHANGED"
    ADMIN_REVOKED = "ADMIN_REVOKED"
    EXPIRED = "EXPIRED"
    USER_DISABLED = "USER_DISABLED"
    ACCOUNT_DELETED = "ACCOUNT_DELETED"


class ClientPlatform(StrEnum):
    ANDROID = "ANDROID"
    IOS = "IOS"
    WEB = "WEB"
    CLI = "CLI"
    UNKNOWN = "UNKNOWN"


class FileKind(StrEnum):
    USER_AVATAR = "USER_AVATAR"
    SAVED_PLANT_PHOTO = "SAVED_PLANT_PHOTO"
    DIAGNOSIS_IMAGE = "DIAGNOSIS_IMAGE"
    PLANT_REFERENCE_IMAGE = "PLANT_REFERENCE_IMAGE"
    EXPERT_PROFILE_IMAGE = "EXPERT_PROFILE_IMAGE"
    IMPORT_DATASET = "IMPORT_DATASET"


class DiagnosisStatus(StrEnum):
    PENDING = "PENDING"
    ANALYZING = "ANALYZING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    REJECTED = "REJECTED"


class ResultKind(StrEnum):
    PLANT_IDENTIFICATION = "PLANT_IDENTIFICATION"
    HEALTH_ASSESSMENT = "HEALTH_ASSESSMENT"
    DISEASE_CANDIDATE = "DISEASE_CANDIDATE"
    PEST_CANDIDATE = "PEST_CANDIDATE"
    NUTRIENT_CANDIDATE = "NUTRIENT_CANDIDATE"
    DATA_QUALITY_WARNING = "DATA_QUALITY_WARNING"


class EvidenceSource(StrEnum):
    """Where a piece of information in a diagnosis came from.

    ``AI_INFERRED`` and ``USER_REPORTED`` are *not* verified knowledge. The API
    keeps them in a separate object from ``VERIFIED_KNOWLEDGE`` so a client
    cannot present a model guess as a confirmed finding.
    """

    AI_INFERRED = "AI_INFERRED"
    USER_REPORTED = "USER_REPORTED"
    VERIFIED_KNOWLEDGE = "VERIFIED_KNOWLEDGE"


class HealthGrade(StrEnum):
    EXCELLENT = "EXCELLENT"
    GOOD = "GOOD"
    NEEDS_ATTENTION = "NEEDS_ATTENTION"
    CONCERNING = "CONCERNING"
    POOR = "POOR"
    UNKNOWN = "UNKNOWN"


class BackupStatus(StrEnum):
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    DELETED = "DELETED"


class BackupKind(StrEnum):
    FULL = "FULL"
    SCHEMA_ONLY = "SCHEMA_ONLY"
    DATA_ONLY = "DATA_ONLY"
    PRE_MIGRATION = "PRE_MIGRATION"
    MANUAL = "MANUAL"


class SettingValueType(StrEnum):
    STRING = "STRING"
    INTEGER = "INTEGER"
    FLOAT = "FLOAT"
    BOOLEAN = "BOOLEAN"
    JSON = "JSON"
    SECRET = "SECRET"
