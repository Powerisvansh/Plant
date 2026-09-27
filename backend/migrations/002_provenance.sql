-- 002_provenance.sql
-- Source, provenance and verification system.
-- Every factual record in this database must be traceable to a row in `sources`
-- and, where a document backs it, to a row in `source_documents`.

CREATE TABLE sources (
    id                      BIGSERIAL PRIMARY KEY,
    key                     TEXT NOT NULL UNIQUE,
    name                    TEXT NOT NULL,
    url                     TEXT,
    source_type             source_type NOT NULL,
    organization            TEXT,
    authors                 TEXT,
    license                 license_type NOT NULL DEFAULT 'UNKNOWN',
    license_url             TEXT,
    attribution_required    BOOLEAN NOT NULL DEFAULT FALSE,
    attribution_template    TEXT,
    terms_url               TEXT,
    redistribution_allowed  BOOLEAN,
    commercial_use_allowed  BOOLEAN,
    citation                TEXT,
    date_accessed           DATE,
    last_verified           DATE,
    api_endpoint            TEXT,
    approval_status         approval_status NOT NULL DEFAULT 'PENDING_REVIEW',
    is_citable_in_app       BOOLEAN NOT NULL DEFAULT FALSE,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE source_documents (
    id              BIGSERIAL PRIMARY KEY,
    source_id       BIGINT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    authors         TEXT,
    publication     TEXT,
    publisher       TEXT,
    year            INTEGER CHECK (year IS NULL OR (year BETWEEN 1000 AND 3000)),
    volume          TEXT,
    pages           TEXT,
    doi             TEXT,
    isbn            TEXT,
    edition         TEXT,
    url             TEXT,
    local_path      TEXT,
    sha256          TEXT CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
    retrieved_at    DATE,
    page_reference  TEXT,
    language        TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_id, title, doi)
);

CREATE TABLE data_provenance (
    id                  BIGSERIAL PRIMARY KEY,
    table_name          TEXT NOT NULL,
    record_id           BIGINT NOT NULL,
    field_name          TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    source_document_id  BIGINT REFERENCES source_documents(id) ON DELETE SET NULL,
    extracted_value     TEXT,
    extraction_method   TEXT,
    page_reference      TEXT,
    confidence          NUMERIC(4,3) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    recorded_by         TEXT NOT NULL DEFAULT current_user,
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    superseded_at       TIMESTAMPTZ,
    superseded_by       BIGINT REFERENCES data_provenance(id) ON DELETE SET NULL,
    notes               TEXT
);

CREATE INDEX idx_provenance_record ON data_provenance (table_name, record_id);
CREATE INDEX idx_provenance_source ON data_provenance (source_id);
CREATE INDEX idx_provenance_status ON data_provenance (verification_status);
CREATE UNIQUE INDEX uq_provenance_field_active
    ON data_provenance (table_name, record_id, COALESCE(field_name, ''))
    WHERE superseded_at IS NULL;

CREATE TABLE verification_records (
    id                  BIGSERIAL PRIMARY KEY,
    table_name          TEXT NOT NULL,
    record_id           BIGINT NOT NULL,
    verification_status verification_status NOT NULL,
    verified_by         TEXT NOT NULL DEFAULT current_user,
    verified_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    method              TEXT,
    evidence            TEXT,
    notes               TEXT,
    supersedes_id       BIGINT REFERENCES verification_records(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_verification_record ON verification_records (table_name, record_id, verified_at DESC);

CREATE TABLE record_conflicts (
    id              BIGSERIAL PRIMARY KEY,
    table_name      TEXT NOT NULL,
    record_id       BIGINT NOT NULL,
    field_name      TEXT NOT NULL,
    value_a         TEXT,
    value_b         TEXT,
    source_id_a     BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    source_id_b     BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    status          record_conflict_status NOT NULL DEFAULT 'OPEN',
    resolution_note TEXT,
    resolved_by     TEXT,
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_conflicts_record ON record_conflicts (table_name, record_id, status);
CREATE UNIQUE INDEX uq_conflicts_open_field
    ON record_conflicts (table_name, record_id, field_name)
    WHERE status = 'OPEN';

CREATE OR REPLACE FUNCTION fn_touch_updated_at() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION fn_invalidate_conflict() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status <> 'OPEN' AND (OLD.status IS DISTINCT FROM NEW.status) THEN
        UPDATE record_conflicts
           SET resolved_at = COALESCE(resolved_at, now()),
               resolved_by  = COALESCE(resolved_by, current_user)
         WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_conflicts_resolved
    BEFORE UPDATE ON record_conflicts
    FOR EACH ROW EXECUTE FUNCTION fn_invalidate_conflict();
