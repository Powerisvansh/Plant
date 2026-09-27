-- 007_safety_toxicity.sql
-- Plant / pest / pathogen safety and toxicity system.
--
-- SAFETY MODEL
--   * A subject with no `toxicity_profiles` row means TOXICITY = UNKNOWN.
--     There is no default, and "unknown" is never rendered as "safe".
--   * Human, pet and livestock risk are stored separately and may differ.
--   * Every profile requires a source and a verification status.
--   * `v_subject_safety_summary` is the only read path for the app and it
--     returns UNKNOWN (never NON_TOXIC / risk NONE) when no profile exists.

CREATE TABLE toxicity_profiles (
    id                      BIGSERIAL PRIMARY KEY,
    subject_kind            subject_kind NOT NULL,
    plant_id                BIGINT REFERENCES plants(id) ON DELETE CASCADE,
    pest_id                 BIGINT REFERENCES pests(id) ON DELETE CASCADE,
    toxicity_status         toxicity_status NOT NULL DEFAULT 'UNKNOWN',
    overall_severity        severity_level NOT NULL DEFAULT 'UNKNOWN',
    compounds_summary       TEXT,
    exposure_summary        TEXT,
    symptoms_summary        TEXT,
    first_aid               TEXT,
    veterinary_note         TEXT,
    evidence_level          evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    is_home_garden_relevant BOOLEAN NOT NULL DEFAULT TRUE,
    source_id               BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    source_document_id      BIGINT REFERENCES source_documents(id) ON DELETE SET NULL,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    reviewed_by             TEXT,
    notes                   TEXT,
    conflicts_with_id       BIGINT REFERENCES toxicity_profiles(id) ON DELETE SET NULL,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT toxicity_subject_present CHECK (
        (subject_kind = 'PLANT'   AND plant_id IS NOT NULL AND pest_id IS NULL) OR
        (subject_kind = 'PEST'    AND pest_id  IS NOT NULL AND plant_id IS NULL) OR
        (subject_kind = 'PATHOGEN' AND plant_id IS NULL AND pest_id IS NULL) OR
        (subject_kind = 'UNKNOWN' AND plant_id IS NULL AND pest_id IS NULL)
    ),
    CONSTRAINT toxicity_subject_unique UNIQUE NULLS NOT DISTINCT (subject_kind, plant_id, pest_id),
    CONSTRAINT toxicity_non_toxic_needs_severity CHECK (
        toxicity_status <> 'NON_TOXIC' OR overall_severity = 'NONE'
    ),
    CONSTRAINT toxicity_verified_needs_source CHECK (
        verification_status <> 'VERIFIED' OR source_id IS NOT NULL
    )
);

CREATE INDEX idx_toxicity_plant ON toxicity_profiles (plant_id) WHERE plant_id IS NOT NULL;
CREATE INDEX idx_toxicity_pest ON toxicity_profiles (pest_id) WHERE pest_id IS NOT NULL;
CREATE INDEX idx_toxicity_status ON toxicity_profiles (toxicity_status);
CREATE TRIGGER trg_toxicity_touch BEFORE UPDATE ON toxicity_profiles
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE toxicity_parts (
    id                  BIGSERIAL PRIMARY KEY,
    profile_id          BIGINT NOT NULL REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    part                plant_part NOT NULL,
    toxicity_status     toxicity_status NOT NULL DEFAULT 'UNKNOWN',
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, part)
);

CREATE TABLE possible_toxic_compounds (
    id                  BIGSERIAL PRIMARY KEY,
    profile_id          BIGINT NOT NULL REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    compound_name       TEXT NOT NULL,
    compound_class      TEXT,
    chemical_formula    TEXT,
    mechanism           TEXT,
    evidence_level      evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, compound_name)
);

CREATE TABLE toxicity_exposure_routes (
    id                  BIGSERIAL PRIMARY KEY,
    profile_id          BIGINT NOT NULL REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    route               exposure_route NOT NULL,
    details             TEXT,
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    lethal_dose_info    TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, route)
);

CREATE TABLE toxicity_symptoms (
    id                  BIGSERIAL PRIMARY KEY,
    profile_id          BIGINT NOT NULL REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    symptom_id          BIGINT REFERENCES symptoms(id) ON DELETE SET NULL,
    symptom_text        TEXT,
    part                plant_part,
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    onset_time          TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT toxicity_symptom_present CHECK (symptom_id IS NOT NULL OR symptom_text IS NOT NULL)
);

CREATE TABLE human_safety (
    profile_id              BIGINT PRIMARY KEY REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    risk_level              risk_level NOT NULL DEFAULT 'UNKNOWN',
    risk_summary            TEXT,
    vulnerable_groups       TEXT,
    safe_handling           TEXT,
    first_aid               TEXT,
    when_to_seek_help       TEXT,
    emergency_note          TEXT,
    consumption_risk        TEXT,
    medicinal_use_warning   TEXT,
    evidence_level          evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id               BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT human_safety_verified_needs_source CHECK (
        verification_status <> 'VERIFIED' OR source_id IS NOT NULL
    )
);

CREATE TRIGGER trg_human_safety_touch BEFORE UPDATE ON human_safety
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE pet_safety (
    profile_id              BIGINT PRIMARY KEY REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    risk_level              risk_level NOT NULL DEFAULT 'UNKNOWN',
    affected_pets           TEXT[],
    risk_summary            TEXT,
    clinical_note           TEXT,
    first_aid               TEXT,
    when_to_see_vet         TEXT,
    evidence_level          evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id               BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pet_safety_verified_needs_source CHECK (
        verification_status <> 'VERIFIED' OR source_id IS NOT NULL
    )
);

CREATE TRIGGER trg_pet_safety_touch BEFORE UPDATE ON pet_safety
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE livestock_safety (
    profile_id              BIGINT PRIMARY KEY REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    risk_level              risk_level NOT NULL DEFAULT 'UNKNOWN',
    affected_livestock      TEXT[],
    risk_summary            TEXT,
    clinical_note           TEXT,
    first_aid               TEXT,
    when_to_see_vet         TEXT,
    withdrawal_period_note  TEXT,
    evidence_level          evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id               BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT livestock_safety_verified_needs_source CHECK (
        verification_status <> 'VERIFIED' OR source_id IS NOT NULL
    )
);

CREATE TRIGGER trg_livestock_safety_touch BEFORE UPDATE ON livestock_safety
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE first_aid_records (
    id                  BIGSERIAL PRIMARY KEY,
    profile_id          BIGINT NOT NULL REFERENCES toxicity_profiles(id) ON DELETE CASCADE,
    route               exposure_route NOT NULL,
    instruction         TEXT NOT NULL,
    do_not              TEXT,
    seek_care_immediately BOOLEAN NOT NULL DEFAULT FALSE,
    source_id           BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (profile_id, route, instruction)
);

CREATE TABLE safety_warnings (
    id                  BIGSERIAL PRIMARY KEY,
    scope_kind          subject_kind NOT NULL DEFAULT 'PLANT',
    plant_id            BIGINT REFERENCES plants(id) ON DELETE CASCADE,
    pest_id             BIGINT REFERENCES pests(id) ON DELETE CASCADE,
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    warning_text        TEXT NOT NULL,
    audience            TEXT NOT NULL DEFAULT 'GENERAL',
    is_mandatory        BOOLEAN NOT NULL DEFAULT FALSE,
    display_order       SMALLINT NOT NULL DEFAULT 100,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, pest_id, warning_text)
);

CREATE INDEX idx_safety_warnings_plant ON safety_warnings (plant_id) WHERE plant_id IS NOT NULL;

CREATE OR REPLACE FUNCTION fn_unknown_safety_notice() RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT 'Toxicity information was not found in the available knowledge base. '
        || 'Do not consume or use medicinally without independent verification.'
$$;

-- The single read path for the application. Absence of a profile yields UNKNOWN.
CREATE OR REPLACE VIEW v_subject_safety_summary AS
SELECT p.id                       AS plant_id,
       p.scientific_name,
       tp.id                      AS profile_id,
       COALESCE(tp.toxicity_status, 'UNKNOWN')      AS toxicity_status,
       COALESCE(tp.overall_severity, 'UNKNOWN')     AS overall_severity,
       tp.compounds_summary,
       tp.exposure_summary,
       tp.symptoms_summary,
       tp.first_aid,
       COALESCE(hs.risk_level, 'UNKNOWN')           AS human_risk_level,
       hs.risk_summary                            AS human_risk_summary,
       hs.vulnerable_groups,
       hs.safe_handling,
       hs.first_aid                                AS human_first_aid,
       hs.when_to_seek_help,
       COALESCE(ps.risk_level, 'UNKNOWN')           AS pet_risk_level,
       ps.affected_pets,
       ps.risk_summary                             AS pet_risk_summary,
       ps.clinical_note                            AS pet_clinical_note,
       ps.first_aid                                AS pet_first_aid,
       COALESCE(ls.risk_level, 'UNKNOWN')           AS livestock_risk_level,
       ls.affected_livestock,
       ls.risk_summary                             AS livestock_risk_summary,
       ls.clinical_note                            AS livestock_clinical_note,
       ls.first_aid                                AS livestock_first_aid,
       COALESCE(tp.verification_status, 'UNKNOWN')  AS verification_status,
       tp.last_verified,
       s.name                                      AS source_name,
       s.url                                       AS source_url,
       s.citation                                  AS source_citation,
       sd.title                                    AS source_document_title,
       (tp.id IS NULL)                             AS is_unknown,
       CASE WHEN tp.id IS NULL
            THEN fn_unknown_safety_notice()
            ELSE NULL END                          AS unknown_notice
  FROM plants p
  LEFT JOIN toxicity_profiles tp
         ON tp.plant_id = p.id AND tp.subject_kind = 'PLANT'
  LEFT JOIN human_safety hs     ON hs.profile_id = tp.id
  LEFT JOIN pet_safety ps       ON ps.profile_id = tp.id
  LEFT JOIN livestock_safety ls  ON ls.profile_id = tp.id
  LEFT JOIN source_documents sd ON sd.id = tp.source_document_id
  LEFT JOIN sources s           ON s.id = tp.source_id
 WHERE p.is_deleted = FALSE;
