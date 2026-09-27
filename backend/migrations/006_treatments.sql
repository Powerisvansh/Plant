-- 006_treatments.sql
-- Treatment and plant-protection-product information.
--
-- SAFETY MODEL
--   * A dose is NOT universal. A dose is only valid for an exact
--     (product, formulation, concentration, jurisdiction, crop, growth stage,
--     label document) combination.
--   * `treatment_dosages` therefore carries jurisdiction, product, formulation,
--     concentration, growth stage, label document and verification status.
--   * Rows may only be created by a gated importer that supplies a label
--     document. Nothing in this schema may be populated from model memory.
--   * `v_treatment_dosage_verified` exposes ONLY VERIFIED doses; the API never
--     reads `treatment_dosages` directly.

CREATE TABLE active_ingredients (
    id                      BIGSERIAL PRIMARY KEY,
    key                     TEXT NOT NULL UNIQUE,
    common_name             TEXT NOT NULL,
    chemical_name           TEXT,
    cas_number              TEXT,
    pesticide_class         TEXT,
    mode_of_action          TEXT,
    target_groups           TEXT[],
    formulation_classes     TEXT[],
    human_toxicity_notes    TEXT,
    environmental_warnings  TEXT,
    is_banned_in            TEXT[],
    source_id               BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_ai_touch BEFORE UPDATE ON active_ingredients
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE treatment_products (
    id                      BIGSERIAL PRIMARY KEY,
    key                     TEXT NOT NULL UNIQUE,
    product_name            TEXT NOT NULL,
    product_type            TEXT NOT NULL,
    formulation             TEXT,
    formulation_code        TEXT,
    concentration_value     NUMERIC(14,6),
    concentration_unit      TEXT,
    manufacturer            TEXT,
    registration_number     TEXT,
    jurisdiction            TEXT NOT NULL,
    registration_status     TEXT NOT NULL DEFAULT 'UNKNOWN',
    label_url               TEXT,
    label_sha256            TEXT CHECK (label_sha256 IS NULL OR label_sha256 ~ '^[0-9a-f]{64}$'),
    label_date              DATE,
    label_source_id         BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    hazard_statements       TEXT,
    signal_word             TEXT,
    source_id               BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT products_type_known CHECK (
        product_type IN (
            'FUNGICIDE','BACTERICIDE','VIRICIDE','INSECTICIDE','ACARICIDE','NEMATICIDE',
            'HERBICIDE','BIOFUNGICIDE','BIOINSECTICIDE','BIOCONTROL','FUNGICIDE_BIOLOGICAL',
            'SOIL_AMENDMENT','PLANT_GROWTH_REGULATOR','OTHER'
        )
    ),
    CONSTRAINT products_registration_known CHECK (
        registration_status IN ('REGISTERED','REGISTERED_RESTRICTED','NOT_REGISTERED','EXPIRED','UNKNOWN')
    ),
    CONSTRAINT products_jurisdiction_required CHECK (length(btrim(jurisdiction)) > 0)
);

CREATE INDEX idx_products_jurisdiction ON treatment_products (jurisdiction);
CREATE INDEX idx_products_registration ON treatment_products (registration_number);
CREATE TRIGGER trg_products_touch BEFORE UPDATE ON treatment_products
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE product_active_ingredients (
    product_id             BIGINT NOT NULL REFERENCES treatment_products(id) ON DELETE CASCADE,
    active_ingredient_id   BIGINT NOT NULL REFERENCES active_ingredients(id) ON DELETE RESTRICT,
    concentration_value    NUMERIC(14,6),
    concentration_unit     TEXT,
    is_primary             BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (product_id, active_ingredient_id)
);

CREATE TABLE treatments (
    id                      BIGSERIAL PRIMARY KEY,
    code                    TEXT NOT NULL UNIQUE,
    name                    TEXT NOT NULL,
    treatment_type          TEXT NOT NULL,
    summary                 TEXT,
    is_prescriptive         BOOLEAN NOT NULL DEFAULT FALSE,
    requires_label          BOOLEAN NOT NULL DEFAULT TRUE,
    requires_professional   BOOLEAN NOT NULL DEFAULT FALSE,
    is_regulated            BOOLEAN NOT NULL DEFAULT TRUE,
    jurisdiction            TEXT,
    restriction_notes       TEXT,
    efficacy_evidence       TEXT,
    evidence_level          evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id               BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT treatments_type_known CHECK (
        treatment_type IN (
            'CHEMICAL','BIOLOGICAL','CULTURAL','PHYSICAL','MECHANICAL','EXCLUSION','QUARANTINE','OTHER'
        )
    )
);

CREATE TRIGGER trg_treatments_touch BEFORE UPDATE ON treatments
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE INDEX idx_treatments_type ON treatments (treatment_type);

CREATE TABLE treatment_targets (
    id                  BIGSERIAL PRIMARY KEY,
    treatment_id        BIGINT NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    target_kind         target_kind NOT NULL,
    target_ref          BIGINT NOT NULL,
    target_label        TEXT NOT NULL,
    efficacy_rating     TEXT,
    efficacy_evidence   TEXT,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (treatment_id, target_kind, target_ref)
);

CREATE INDEX idx_treatment_targets_ref ON treatment_targets (target_kind, target_ref);

CREATE TABLE treatment_plant_scope (
    treatment_id        BIGINT NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    growth_stage        TEXT,
    is_label_crop       BOOLEAN NOT NULL DEFAULT FALSE,
    notes               TEXT,
    PRIMARY KEY (treatment_id, plant_id)
);

CREATE INDEX idx_treatment_scope_plant ON treatment_plant_scope (plant_id);

-- The critical table. One row == one label-derived dose statement.
CREATE TABLE treatment_dosages (
    id                      BIGSERIAL PRIMARY KEY,
    treatment_id            BIGINT NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    product_id              BIGINT NOT NULL REFERENCES treatment_products(id) ON DELETE RESTRICT,
    jurisdiction            TEXT NOT NULL,
    crop_label_text         TEXT,
    plant_id                BIGINT REFERENCES plants(id) ON DELETE SET NULL,
    growth_stage            TEXT,
    dose_value              NUMERIC(16,6) NOT NULL,
    dose_min_value          NUMERIC(16,6),
    dose_max_value          NUMERIC(16,6),
    dose_unit               TEXT NOT NULL,
    dose_basis              TEXT NOT NULL DEFAULT 'PER_AREA',
    water_volume_value      NUMERIC(16,6),
    water_volume_unit       TEXT,
    application_method      TEXT NOT NULL,
    application_count_max   SMALLINT CHECK (application_count_max IS NULL OR application_count_max >= 1),
    application_interval_days NUMERIC(6,2) CHECK (application_interval_days IS NULL OR application_interval_days > 0),
    pre_harvest_interval_days NUMERIC(6,2) CHECK (pre_harvest_interval_days IS NULL OR pre_harvest_interval_days >= 0),
    reentry_interval_hours  NUMERIC(8,2) CHECK (reentry_interval_hours IS NULL OR reentry_interval_hours >= 0),
    formulation_concentration_text TEXT,
    target_part             plant_part,
    label_source_document_id BIGINT REFERENCES source_documents(id) ON DELETE RESTRICT,
    label_page_reference    TEXT,
    label_url               TEXT,
    label_sha256            TEXT,
    effective_from          DATE,
    effective_to            DATE,
    is_label_derived        BOOLEAN NOT NULL DEFAULT TRUE,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT dosages_dose_unit_known CHECK (
        dose_unit IN (
            'MG_L','G_L','ML_L','KG_HA','G_HA','ML_HA','G_100L','MG_100L','ML_100L',
            'KG_100L','G_TREE','L_TREE','ML_PLANT','PER_PLANT','G_M2','MG_M2',
            'G_ACRE','LB_ACRE','QT_ACRE','LB_1000FT2','PER_1000FT2','TAB_PER_PLANT','UNITS_UNKNOWN'
        )
    ),
    CONSTRAINT dosages_dose_positive CHECK (dose_value > 0),
    CONSTRAINT dosages_range_order CHECK (
        dose_min_value IS NULL OR dose_max_value IS NULL
        OR (dose_min_value > 0 AND dose_max_value > 0 AND dose_min_value <= dose_max_value)
    ),
    CONSTRAINT dosages_label_required CHECK (is_label_derived = FALSE OR label_source_document_id IS NOT NULL),
    CONSTRAINT dosages_verified_needs_document CHECK (
        verification_status <> 'VERIFIED' OR label_source_document_id IS NOT NULL
    ),
    CONSTRAINT dosages_effective_order CHECK (
        effective_from IS NULL OR effective_to IS NULL OR effective_from <= effective_to
    )
);

CREATE INDEX idx_dosages_treatment ON treatment_dosages (treatment_id);
CREATE INDEX idx_dosages_product ON treatment_dosages (product_id);
CREATE INDEX idx_dosages_plant ON treatment_dosages (plant_id) WHERE plant_id IS NOT NULL;
CREATE INDEX idx_dosages_jurisdiction ON treatment_dosages (jurisdiction);
CREATE INDEX idx_dosages_verified ON treatment_dosages (verification_status)
    WHERE verification_status = 'VERIFIED';
CREATE TRIGGER trg_dosages_touch BEFORE UPDATE ON treatment_dosages
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE dosage_plausibility_rules (
    id                  BIGSERIAL PRIMARY KEY,
    key                 TEXT NOT NULL UNIQUE,
    description         TEXT NOT NULL,
    active_ingredient_id BIGINT REFERENCES active_ingredients(id) ON DELETE CASCADE,
    dose_unit           TEXT,
    min_dose            NUMERIC(16,6),
    max_dose            NUMERIC(16,6),
    max_water_volume    NUMERIC(16,6),
    severity            severity_level NOT NULL DEFAULT 'MODERATE',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE dosage_plausibility_findings (
    id              BIGSERIAL PRIMARY KEY,
    dosage_id       BIGINT NOT NULL REFERENCES treatment_dosages(id) ON DELETE CASCADE,
    rule_id         BIGINT REFERENCES dosage_plausibility_rules(id) ON DELETE SET NULL,
    rule_key        TEXT,
    severity        severity_level NOT NULL,
    message         TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_dosage_findings_dosage ON dosage_plausibility_findings (dosage_id);

CREATE TABLE treatment_instructions (
    id              BIGSERIAL PRIMARY KEY,
    treatment_id    BIGINT NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    step_order      SMALLINT NOT NULL,
    instruction     TEXT NOT NULL,
    cautions        TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (treatment_id, step_order)
);

CREATE TABLE treatment_protective_equipment (
    id              BIGSERIAL PRIMARY KEY,
    treatment_id    BIGINT NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    item            TEXT NOT NULL,
    is_required     BOOLEAN NOT NULL DEFAULT TRUE,
    standard        TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (treatment_id, item)
);

CREATE TABLE treatment_safety (
    id                      BIGSERIAL PRIMARY KEY,
    treatment_id            BIGINT NOT NULL UNIQUE REFERENCES treatments(id) ON DELETE CASCADE,
    protective_equipment_summary TEXT,
    reentry_statement       TEXT,
    pre_harvest_statement   TEXT,
    environmental_statement TEXT,
    storage_disposal        TEXT,
    first_aid               TEXT,
    emergency_contact_note  TEXT,
    hazard_statements       TEXT,
    signal_word             TEXT,
    source_id               BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE treatment_restrictions (
    id              BIGSERIAL PRIMARY KEY,
    treatment_id    BIGINT NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    restriction_type TEXT NOT NULL,
    description     TEXT NOT NULL,
    jurisdiction    TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (treatment_id, restriction_type, jurisdiction),
    CONSTRAINT restriction_type_known CHECK (
        restriction_type IN (
            'PROHIBITED','MAX_APPLICATIONS','PHI_REQUIRED','REENTRY_INTERVAL',
            'CROP_NOT_ON_LABEL','LOCATION_RESTRICTED','WATER_RESTRICTED',
            'POLLINATOR_RESTRICTED','HOME_GARDEN_RESTRICTED','ADJUVANT_REQUIRED','OTHER'
        )
    )
);

CREATE TABLE treatment_prohibitions (
    id              BIGSERIAL PRIMARY KEY,
    jurisdiction    TEXT NOT NULL,
    scope_kind      target_kind NOT NULL,
    scope_ref       BIGINT,
    active_ingredient_id BIGINT REFERENCES active_ingredients(id) ON DELETE CASCADE,
    reason          TEXT NOT NULL,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    effective_from  DATE,
    effective_to    DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_treatment_prohibitions_scope ON treatment_prohibitions (jurisdiction, scope_kind, scope_ref);

-- Only VERIFIED, label-backed doses are ever exposed to the application.
CREATE OR REPLACE VIEW v_treatment_dosage_verified AS
SELECT d.id                AS dosage_id,
       d.treatment_id,
       t.code              AS treatment_code,
       t.name              AS treatment_name,
       t.treatment_type,
       p.id                AS product_id,
       p.product_name,
       p.product_type,
       p.formulation,
       p.formulation_code,
       p.registration_number,
       d.jurisdiction,
       d.crop_label_text,
       d.plant_id,
       d.growth_stage,
       d.dose_value,
       d.dose_min_value,
       d.dose_max_value,
       d.dose_unit,
       d.dose_basis,
       d.water_volume_value,
       d.water_volume_unit,
       d.application_method,
       d.application_count_max,
       d.application_interval_days,
       d.pre_harvest_interval_days,
       d.reentry_interval_hours,
       d.target_part,
       d.label_page_reference,
       d.label_url,
       d.label_sha256,
       d.last_verified,
       s.id                AS label_source_id,
       s.name              AS label_source_name,
       s.url               AS label_source_url,
       sd.id               AS label_document_id,
       sd.title            AS label_document_title,
       sd.local_path       AS label_document_path
  FROM treatment_dosages d
  JOIN treatments t          ON t.id = d.treatment_id
  JOIN treatment_products p  ON p.id = d.product_id
  LEFT JOIN source_documents sd ON sd.id = d.label_source_document_id
  LEFT JOIN sources s        ON s.id = sd.source_id
 WHERE d.verification_status = 'VERIFIED'
   AND t.verification_status IN ('VERIFIED', 'PARTIALLY_VERIFIED')
   AND d.label_source_document_id IS NOT NULL;
