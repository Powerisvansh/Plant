# =============================================================================
# PlantDoctor desktop server - operational commands.
#
#   make help          list every target
#   make install       create the virtualenv and install dependencies
#   make start         run the API on 0.0.0.0:8000
#
# Everything runs against the native PostgreSQL cluster by default.
# `make docker-up` switches to the container stack.
# =============================================================================

SHELL       := /bin/bash
VENV        := .venv
PY          := $(VENV)/bin/python
PIP         := $(VENV)/bin/pip
HOST        ?= 0.0.0.0
PORT        ?= 8000
WORKERS     ?= 2
ENV_FILE    ?= /plantdoctor-data/.env
# The operational scripts live at the repository root, beside backend/, not
# inside it. Every script resolves its own paths from __file__, so cwd does not
# matter, but the Makefile is run from backend/ and must say where they are.
SCRIPTS     := ../scripts

.DEFAULT_GOAL := help
.PHONY: help install freeze start dev test test-cov lint migrate migrate-kb \
        seed-roles create-admin seed-sources import-plants import-diseases \
        validate backup backup-list restore verify-shell smoke docker-up \
        docker-down docker-logs psql clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	 | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- environment ------------------------------------------------------------
$(VENV):
	python3 -m venv $(VENV)
	$(PIP) install --quiet --upgrade pip

install: $(VENV) ## Create the venv and install server dependencies
	$(PIP) install -r requirements.txt

freeze: ## Write a fully pinned lock file for reproducible rebuilds
	$(PIP) freeze > requirements.lock.txt
	@echo "wrote requirements.lock.txt"

env: ## Create /plantdoctor-data/.env with freshly generated secrets
	@test -f $(ENV_FILE) || (mkdir -p $$(dirname $(ENV_FILE)); \
	  cp .env.example $(ENV_FILE); \
	  echo "$(ENV_FILE) created from .env.example - now run: make env-secrets")
	@echo "env file: $(ENV_FILE)"

env-secrets: ## Generate and write strong random secrets into $(ENV_FILE)
	$(PY) -m app.cli generate-secrets --env-file $(ENV_FILE)

# --- run --------------------------------------------------------------------
start: ## Run the API (production-ish: multiple workers, no reload)
	$(VENV)/bin/uvicorn app.main:app --host $(HOST) --port $(PORT) \
	  --workers $(WORKERS) --proxy-headers --forwarded-allow-ips '*'

dev: ## Run the API with autoreload for local development
	$(VENV)/bin/uvicorn app.main:app --host $(HOST) --port $(PORT) --reload

# --- database ---------------------------------------------------------------
psql: ## Open a psql shell on the PlantDoctor database
	@set -a; . $(ENV_FILE); set +a; \
	  PGPASSWORD="$$PLANTDOCTOR_DB_PASSWORD" psql -h $${PLANTDOCTOR_DB_HOST:-127.0.0.1} \
	    -p $${PLANTDOCTOR_DB_PORT:-5432} -U $${PLANTDOCTOR_DB_USER} -d $${PLANTDOCTOR_DB_NAME}

migrate-kb: ## Apply the knowledge-base SQL migrations (backend/migrations/*.sql)
	$(PY) $(SCRIPTS)/migrate.py status
	$(PY) $(SCRIPTS)/migrate.py up

migrate: ## Apply Alembic migrations for the application schema
	$(VENV)/bin/alembic upgrade head
	$(VENV)/bin/alembic current

migrate-down: ## Roll the application schema back one revision
	$(VENV)/bin/alembic downgrade -1

seed-roles: ## Insert the default roles and permissions
	$(PY) -m app.cli seed-roles

create-admin: ## Interactively create the first super administrator
	$(PY) -m app.cli create-admin

seed-sources: ## Load the source registry (data/sources.json)
	$(PY) $(SCRIPTS)/seed_sources.py

import-plants: ## Import plant taxonomy from the licensed source
	$(PY) $(SCRIPTS)/import_plants.py

import-diseases: ## Import diseases from a JSON import file
	$(PY) -m app.cli import-diseases

validate: ## Run the knowledge-base data quality report
	$(PY) $(SCRIPTS)/validate_database.py

# --- quality ----------------------------------------------------------------
test: ## Run the whole pytest suite against the throwaway test database
	$(PY) -m pytest tests app/tests -q

test-cov: ## Run the suite with a coverage report
	$(PY) -m pytest tests app/tests -q --cov=app --cov-report=term-missing \
	  --cov-report=html:htmlcov

lint: ## Static checks
	$(PY) -m compileall -q app $(SCRIPTS)
	@command -v ruff >/dev/null && ruff check app || echo "ruff not installed; skipped"

smoke: ## End-to-end foundation smoke test
	$(PY) -W ignore -m app.tests.smoke_phase1

smoke-schema: ## End-to-end schema + RBAC smoke test (needs a migrated database)
	$(PY) -W ignore -m app.tests.smoke_phase2

verify: ## Everything: compile, schema drift, tests, both smoke suites
	$(MAKE) lint
	$(VENV)/bin/alembic check
	$(MAKE) test
	$(MAKE) smoke
	$(MAKE) smoke-schema

# --- backups ----------------------------------------------------------------
backup: ## Create a timestamped, checksummed database backup
	$(PY) -m app.cli backup

backup-list: ## List available backups and verify their checksums
	$(PY) -m app.cli backup --list

restore: ## Restore from a backup. Usage: make restore FILE=<name>
	@test -n "$(FILE)" || (echo "usage: make restore FILE=plantdoctor_20260927_1200.dump.zst"; exit 1)
	$(PY) -m app.cli restore $(FILE)

# --- containers -------------------------------------------------------------
docker-up: ## Start the full container stack (postgres + api + nginx)
	docker compose up -d --build
	docker compose ps

docker-down: ## Stop the container stack (volumes are preserved)
	docker compose down

docker-logs: ## Tail container logs
	docker compose logs -f --tail=200 api

# --- housekeeping -----------------------------------------------------------
clean: ## Remove caches and byte-code, never data
	find . -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
	rm -rf .pytest_cache htmlcov .coverage
	@echo "caches removed; no data was touched"
