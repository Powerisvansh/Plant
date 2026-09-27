# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# PlantDoctor API image.
#
# Multi-stage so the runtime layer carries no compiler toolchain.
# The image runs as a non-root user and reads all configuration from the
# environment; no secret is baked in at any layer.
#
# BUILD CONTEXT IS THE REPOSITORY ROOT, not backend/:
#
#     docker build -f backend/Dockerfile -t plantdoctor-api .
#
# The operational scripts live in <root>/scripts, next to <root>/backend, so a
# backend-only context could not COPY them. backend/docker-compose.yml sets the
# context accordingly.
# ---------------------------------------------------------------------------

FROM python:3.12-slim-bookworm AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY backend/requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install -r requirements.txt


FROM python:3.12-slim-bookworm AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    PLANTDOCTOR_DATA_ROOT=/data/plantdoctor \
    UPLOAD_DIRECTORY=/data/plantdoctor/uploads \
    BACKUP_DIRECTORY=/data/plantdoctor/backups \
    MAILBOX_DIRECTORY=/data/plantdoctor/mail

# postgresql-client provides pg_dump/pg_restore for the backup CLI.
RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client curl tini \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 1000 plantdoctor \
 && useradd --system --uid 1000 --gid plantdoctor --home-dir /app plantdoctor

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY --chown=plantdoctor:plantdoctor backend/alembic.ini ./
COPY --chown=plantdoctor:plantdoctor backend/alembic ./alembic
COPY --chown=plantdoctor:plantdoctor backend/app ./app
COPY --chown=plantdoctor:plantdoctor backend/plantdoctor_api ./plantdoctor_api
COPY --chown=plantdoctor:plantdoctor backend/migrations ./migrations
COPY --chown=plantdoctor:plantdoctor backend/tests ./tests
COPY --chown=plantdoctor:plantdoctor backend/.env.example ./
COPY --chown=plantdoctor:plantdoctor scripts ./scripts

# Writable data root. Mount a volume over this path in production so uploads
# and backups survive image rebuilds.
RUN mkdir -p /data/plantdoctor/{uploads,plant-images,diagnosis-images,backups,logs,mail} \
 && chown -R plantdoctor:plantdoctor /data/plantdoctor

USER plantdoctor
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/health || exit 1

# tini reaps zombies and forwards SIGTERM so shutdown is graceful.
ENTRYPOINT ["/usr/bin/tini", "--"]
# 0.0.0.0 so the phone on the LAN can reach the published port.
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*", \
     "--workers", "2", "--log-level", "info"]
