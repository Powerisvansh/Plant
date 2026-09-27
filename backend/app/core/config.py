"""Application configuration.

Every value is read from the environment (optionally seeded from a single env
file). Nothing sensitive is ever given a default: a missing secret is a hard
startup error, never a silent fallback to a guessable value.
"""

from __future__ import annotations

import secrets
from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Plausible secret values must never be accepted, even in a dev profile.
_REFUSED_SECRETS = frozenset(
    {
        "changeme",
        "change-me",
        "secret",
        "password",
        "devsecret",
        "insecure",
        "please-change",
        "12345678",
    }
)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=None,  # handled explicitly by EnvFile so legacy names also work
        extra="ignore",
        case_sensitive=True,
    )

    # --- Application ---------------------------------------------------
    PROJECT_NAME: str = "PlantDoctor Server"
    VERSION: str = "1.0.0"
    API_V1_PREFIX: str = "/api/v1"
    ENVIRONMENT: str = "development"
    DEBUG: bool = False
    TRUSTED_HOSTS: list[str] = Field(default_factory=lambda: ["*"])

    # --- Database ------------------------------------------------------
    DATABASE_URL: str = ""
    TEST_DATABASE_URL: str = ""
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 10
    DB_POOL_TIMEOUT: int = 30
    DB_ECHO: bool = False
    DB_CONNECT_RETRIES: int = 10
    DB_CONNECT_RETRY_DELAY: float = 1.0

    # Legacy knowledge-base connection (plantdoctor_api), still used by the
    # mounted compatibility router and by the CLI import tooling.
    PLANTDOCTOR_ENV_FILE: str = "/plantdoctor-data/.env"
    PLANTDOCTOR_DB_NAME: str = ""
    PLANTDOCTOR_DB_TEST_NAME: str = ""
    PLANTDOCTOR_DB_USER: str = ""
    PLANTDOCTOR_DB_PASSWORD: str = ""
    PLANTDOCTOR_DB_HOST: str = "127.0.0.1"
    PLANTDOCTOR_DB_PORT: int = 5432
    PLANTDOCTOR_DATA_ROOT: str = "/plantdoctor-data"

    # --- JWT -----------------------------------------------------------
    JWT_SECRET: str = ""
    JWT_REFRESH_SECRET: str = ""
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_TTL_MINUTES: int = 15
    REFRESH_TOKEN_TTL_DAYS: int = 30
    ISSUER: str = "plantdoctor"
    AUDIENCE: str = "plantdoctor-mobile"

    # --- Password hashing (Argon2id) -----------------------------------
    ARGON2_TIME_COST: int = 3
    ARGON2_MEMORY_COST_KIB: int = 65536
    ARGON2_PARALLELISM: int = 2
    ARGON2_HASH_LEN: int = 32
    PASSWORD_MIN_LENGTH: int = 10
    PASSWORD_MAX_LENGTH: int = 128

    # --- OTP -----------------------------------------------------------
    OTP_LENGTH: int = 6
    OTP_TTL_SECONDS: int = 300
    OTP_MAX_VERIFY_ATTEMPTS: int = 5
    OTP_MAX_RESENDS: int = 5
    OTP_RESEND_COOLDOWN_SECONDS: int = 60
    OTP_HASH_PEPPER: str = ""

    # --- Phone numbers -------------------------------------------------
    #: Digits prefix used when a user submits a phone number without "+".
    #: Left empty on purpose: a bare national number is ambiguous, and silently
    #: guessing a country code creates duplicate accounts. Set it to e.g. "91"
    #: to accept "9876543210" as Indian.
    DEFAULT_PHONE_COUNTRY_CODE: str = ""

    # --- Email (SMTP) --------------------------------------------------
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM_EMAIL: str = ""
    SMTP_FROM_NAME: str = "PlantDoctor"
    SMTP_USE_TLS: bool = True
    SMTP_USE_SSL: bool = False
    SMTP_TIMEOUT_SECONDS: int = 15
    # When SMTP is not configured, OTPs are written to an on-disk mailbox
    # directory instead of being emailed. Development only.
    MAILBOX_DIRECTORY: str = ""

    # --- SMS (future) --------------------------------------------------
    SMS_PROVIDER: str = ""
    SMS_API_KEY: str = ""
    SMS_SENDER_ID: str = "PLANTDOC"

    # --- CORS ----------------------------------------------------------
    CORS_ORIGINS: list[str] = Field(default_factory=list)

    # --- Storage -------------------------------------------------------
    UPLOAD_DIRECTORY: str = ""
    MAX_UPLOAD_BYTES: int = 12 * 1024 * 1024
    ALLOWED_IMAGE_MIME_TYPES: list[str] = Field(
        default_factory=lambda: ["image/jpeg", "image/png", "image/webp"]
    )
    MIN_IMAGE_DIMENSION: int = 64
    MAX_IMAGE_DIMENSION: int = 8000
    MAX_IMAGE_PIXELS: int = 40_000_000
    # Images are served through the API so that authorisation can be applied.
    IMAGE_RESPONSE_CACHE_SECONDS: int = 3600

    # --- Backups -------------------------------------------------------
    BACKUP_DIRECTORY: str = ""
    BACKUP_RETENTION_COUNT: int = 14

    # --- Rate limiting -------------------------------------------------
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_BACKEND: str = "memory"  # memory | redis
    REDIS_URL: str = ""
    RATE_LIMIT_LOGIN_PER_MINUTE: int = 5
    RATE_LIMIT_OTP_PER_HOUR: int = 10
    RATE_LIMIT_API_PER_MINUTE: int = 240
    RATE_LIMIT_UPLOAD_PER_HOUR: int = 40

    # --- Brute-force protection ----------------------------------------
    LOGIN_MAX_FAILED_ATTEMPTS: int = 5
    LOGIN_LOCKOUT_MINUTES: int = 15

    # --- Logging -------------------------------------------------------
    LOG_LEVEL: str = "INFO"
    LOG_FORMAT: str = "json"  # json | text
    LOG_FILE: str = ""

    # --- Feature flags -------------------------------------------------
    ENABLE_LEGACY_KNOWLEDGE_ROUTES: bool = True
    SERVE_STATIC_UPLOADS: bool = True

    # -- validators -----------------------------------------------------
    @field_validator("CORS_ORIGINS", "TRUSTED_HOSTS", "ALLOWED_IMAGE_MIME_TYPES", mode="before")
    @classmethod
    def _split_csv(cls, value: object) -> object:
        if isinstance(value, str):
            stripped = value.strip()
            if not stripped:
                return []
            if stripped.startswith("["):
                return value
            return [item.strip() for item in stripped.split(",") if item.strip()]
        return value

    @field_validator("ENVIRONMENT")
    @classmethod
    def _normalise_environment(cls, value: str) -> str:
        allowed = {"development", "staging", "production", "test"}
        normalised = value.strip().lower()
        if normalised not in allowed:
            raise ValueError(f"ENVIRONMENT must be one of {sorted(allowed)}, got {value!r}")
        return normalised

    # -- derived --------------------------------------------------------
    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

    @property
    def jwt_access_secret(self) -> str:
        return self.JWT_SECRET

    @property
    def jwt_refresh_secret(self) -> str:
        # A distinct refresh secret means a stolen access token cannot be used
        # to mint refresh tokens and vice versa.
        return self.JWT_REFRESH_SECRET or self.JWT_SECRET

    @property
    def uploads_root(self) -> Path:
        return Path(self.UPLOAD_DIRECTORY or Path(self.PLANTDOCTOR_DATA_ROOT) / "uploads")

    @property
    def backups_root(self) -> Path:
        return Path(self.BACKUP_DIRECTORY or Path(self.PLANTDOCTOR_DATA_ROOT) / "backups")

    @property
    def mailbox_root(self) -> Path | None:
        if self.MAILBOX_DIRECTORY:
            return Path(self.MAILBOX_DIRECTORY)
        if self.SMTP_HOST:
            return None
        return Path(self.PLANTDOCTOR_DATA_ROOT) / "mail"

    @property
    def smtp_configured(self) -> bool:
        return bool(self.SMTP_HOST and self.SMTP_FROM_EMAIL)

    @property
    def effective_redis_url(self) -> str:
        return self.REDIS_URL

    @property
    def effective_jwt_secret(self) -> str:
        """Secret for access tokens."""
        return self.JWT_SECRET

    @property
    def effective_refresh_secret(self) -> str:
        """Secret for refresh tokens.

        Falls back to the access secret only so a development machine without
        both set still boots; ``assert_secrets_present`` then fails, so this
        fallback can never reach production.
        """
        return self.JWT_REFRESH_SECRET or self.JWT_SECRET

    def assert_secrets_present(self) -> None:
        """Fail fast when a secret is missing or is a known placeholder."""
        problems: list[str] = []
        if not self.JWT_SECRET:
            problems.append("JWT_SECRET")
        elif len(self.JWT_SECRET) < 32:
            problems.append("JWT_SECRET must be at least 32 characters")
        elif self.JWT_SECRET.strip().lower() in _REFUSED_SECRETS:
            problems.append("JWT_SECRET is a placeholder value; generate a real secret")
        if not self.OTP_HASH_PEPPER:
            problems.append("OTP_HASH_PEPPER")
        elif len(self.OTP_HASH_PEPPER) < 32:
            problems.append("OTP_HASH_PEPPER must be at least 32 characters")
        if not self.JWT_REFRESH_SECRET:
            problems.append("JWT_REFRESH_SECRET")
        elif self.JWT_REFRESH_SECRET == self.JWT_SECRET:
            problems.append("JWT_REFRESH_SECRET must differ from JWT_SECRET")
        if not self.DATABASE_URL and not (
            self.PLANTDOCTOR_DB_USER and self.PLANTDOCTOR_DB_PASSWORD
        ):
            problems.append("DATABASE_URL (or PLANTDOCTOR_DB_USER + PLANTDOCTOR_DB_PASSWORD)")
        if problems:
            raise RuntimeError(
                "Refusing to start with unsafe or missing configuration: "
                + ", ".join(problems)
                + ". Copy .env.example to .env and generate secrets with "
                "'python -m app.cli generate-secrets'."
            )
        if self.is_production:
            prod_problems: list[str] = []
            if self.DEBUG:
                prod_problems.append("DEBUG must be false in production")
            if self.CORS_ORIGINS and "*" in self.CORS_ORIGINS:
                prod_problems.append("CORS_ORIGINS must not contain '*' in production")
            if not self.CORS_ORIGINS:
                prod_problems.append("CORS_ORIGINS must be set in production")
            if prod_problems:
                raise RuntimeError(
                    "Refusing to start in production with: " + ", ".join(prod_problems)
                )

    def build_database_url(self, *, test: bool = False) -> str:
        if test and self.TEST_DATABASE_URL:
            return self.TEST_DATABASE_URL
        if self.DATABASE_URL:
            return self.DATABASE_URL
        return (
            f"postgresql+psycopg://{self.PLANTDOCTOR_DB_USER}:{self.PLANTDOCTOR_DB_PASSWORD}"
            f"@{self.PLANTDOCTOR_DB_HOST}:{self.PLANTDOCTOR_DB_PORT}/{self.PLANTDOCTOR_DB_NAME}"
        )


def generate_secret(nbytes: int = 48) -> str:
    return secrets.token_urlsafe(nbytes)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    # Import locally to avoid a circular import at module load time.
    from app.core.env import ensure_env_loaded

    ensure_env_loaded()
    return Settings()
