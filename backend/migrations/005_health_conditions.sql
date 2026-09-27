-- 005_health_conditions.sql
-- Symptoms, diseases, pests, nutrient deficiencies, environmental stresses,
-- physical damage, prevention and differential-diagnosis lookalikes.

CREATE TABLE symptoms (
    id                  BIGSERIAL PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    category            TEXT NOT NULL,
    description         TEXT,
    visual_appearance   TEXT,
    onset_notes         TEXT,
    distinguishing_notes TEXT,
    default_severity    severity_level NOT NULL DEFAULT 'UNKNOWN',
    is_observable       BOOLEAN NOT NULL DEFAULT TRUE,
    requires_lab         BOOLEAN NOT NULL DEFAULT FALSE,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT symptoms_category_known CHECK (
        category IN ('COLOR','LESION','DISTORTION','GROWTH','LOSS','SURFACE_GROWTH','STRUCTURE','OTHER')
    )
);

CREATE TRIGGER trg_symptoms_touch BEFORE UPDATE ON symptoms
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE symptom_parts (
    symptom_id  BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE CASCADE,
    part        plant_part NOT NULL,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
    notes       TEXT,
    PRIMARY KEY (symptom_id, part)
);

CREATE TABLE symptom_causes (
    id                  BIGSERIAL PRIMARY KEY,
    symptom_id          BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE CASCADE,
    condition_class     condition_class NOT NULL,
    condition_ref       BIGINT,
    condition_label     TEXT NOT NULL,
    is_common_cause     BOOLEAN NOT NULL DEFAULT FALSE,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (symptom_id, condition_class, condition_ref, condition_label)
);

CREATE INDEX idx_symptom_causes_ref ON symptom_causes (condition_class, condition_ref);

CREATE TABLE symptom_plants (
    symptom_id          BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE CASCADE,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    sensitivity         TEXT,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    PRIMARY KEY (symptom_id, plant_id)
);

CREATE INDEX idx_symptom_plants_plant ON symptom_plants (plant_id);

CREATE TABLE diseases (
    id                          BIGSERIAL PRIMARY KEY,
    code                        TEXT NOT NULL UNIQUE,
    name                        TEXT NOT NULL,
    pathogen_type               TEXT NOT NULL DEFAULT 'UNKNOWN',
    pathogen_scientific_name    TEXT,
    pathogen_authority          TEXT,
    pathogen_trophic_mode       TEXT,
    description                 TEXT,
    disease_cycle               TEXT,
    favorable_conditions        TEXT,
    transmission                TEXT,
    spread_mechanism            TEXT,
    incubation_notes            TEXT,
    diagnostic_notes            TEXT,
    lab_confirmation_required   BOOLEAN NOT NULL DEFAULT TRUE,
    lab_methods                 TEXT,
    is_contagious               BOOLEAN,
    visual_characteristics      TEXT,
    affected_parts              plant_part[],
    is_abiotic                  BOOLEAN NOT NULL DEFAULT FALSE,
    verification_status         verification_status NOT NULL DEFAULT 'UNVERIFIED',
    source_id                   BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    last_verified               DATE,
    content_version             INTEGER NOT NULL DEFAULT 1,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT diseases_pathogen_type_known CHECK (
        pathogen_type IN (
            'FUNGUS','BACTERIA','VIRUS','VIROID','OOMYCETE','PROTOZOA','NEMATODE',
            'MITE','PHYSIOLOGICAL','GENETIC','PARASITIC_PLANT','UNKNOWN'
        )
    )
);

CREATE TRIGGER trg_diseases_touch BEFORE UPDATE ON diseases
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE INDEX idx_diseases_name_trgm ON diseases USING gin (name gin_trgm_ops);
CREATE INDEX idx_diseases_pathogen ON diseases (pathogen_scientific_name);
CREATE INDEX idx_diseases_class_abiotic ON diseases (is_abiotic);

CREATE TABLE disease_symptoms (
    id                  BIGSERIAL PRIMARY KEY,
    disease_id          BIGINT NOT NULL REFERENCES diseases(id) ON DELETE CASCADE,
    symptom_id          BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE RESTRICT,
    part                plant_part NOT NULL,
    frequency           TEXT NOT NULL DEFAULT 'OFTEN',
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    display_order       SMALLINT NOT NULL DEFAULT 100,
    early_stage_only    BOOLEAN NOT NULL DEFAULT FALSE,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (disease_id, symptom_id, part),
    CONSTRAINT disease_symptoms_frequency CHECK (
        frequency IN ('ALWAYS','OFTEN','OCCASIONAL','RARE')
    )
);

CREATE INDEX idx_disease_symptoms_disease ON disease_symptoms (disease_id);
CREATE INDEX idx_disease_symptoms_symptom ON disease_symptoms (symptom_id);

CREATE TABLE plant_diseases (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    disease_id          BIGINT NOT NULL REFERENCES diseases(id) ON DELETE CASCADE,
    susceptibility      TEXT NOT NULL DEFAULT 'UNKNOWN',
    resistance_status   TEXT,
    common_in_region    TEXT,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, disease_id),
    CONSTRAINT plant_diseases_susceptibility_known CHECK (
        susceptibility IN (
            'HIGH','MODERATE','LOW','RESISTANT','IMMUNE','NOT_SUSCEPTIBLE','UNKNOWN'
        )
    )
);

CREATE INDEX idx_plant_diseases_plant ON plant_diseases (plant_id);
CREATE INDEX idx_plant_diseases_disease ON plant_diseases (disease_id);

CREATE TRIGGER trg_plant_diseases_touch BEFORE UPDATE ON plant_diseases
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE pests (
    id                  BIGSERIAL PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    pest_type           TEXT NOT NULL DEFAULT 'UNKNOWN',
    scientific_name     TEXT,
    scientific_authority TEXT,
    description         TEXT,
    size_description    TEXT,
    color_description   TEXT,
    life_stages         TEXT,
    feeding_behavior    TEXT,
    feeding_damage      TEXT,
    favorable_conditions TEXT,
    overwintering       TEXT,
    damage_severity     severity_level NOT NULL DEFAULT 'UNKNOWN',
    natural_enemies     TEXT,
    visual_characteristics TEXT,
    affected_parts      plant_part[],
    is_abiotic           BOOLEAN NOT NULL DEFAULT FALSE,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pests_type_known CHECK (
        pest_type IN (
            'INSECT','MITE','NEMATODE','SNAIL','SLUG','BIRD','MAMMAL','FUNGUS_GALL',
            'UNKNOWN'
        )
    )
);

CREATE TRIGGER trg_pests_touch BEFORE UPDATE ON pests
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE INDEX idx_pests_name_trgm ON pests USING gin (name gin_trgm_ops);
CREATE INDEX idx_pests_scientific ON pests (scientific_name);

CREATE TABLE pest_symptoms (
    id                  BIGSERIAL PRIMARY KEY,
    pest_id             BIGINT NOT NULL REFERENCES pests(id) ON DELETE CASCADE,
    symptom_id          BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE RESTRICT,
    part                plant_part NOT NULL,
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (pest_id, symptom_id, part)
);

CREATE INDEX idx_pest_symptoms_pest ON pest_symptoms (pest_id);
CREATE INDEX idx_pest_symptoms_symptom ON pest_symptoms (symptom_id);

CREATE TABLE plant_pests (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    pest_id             BIGINT NOT NULL REFERENCES pests(id) ON DELETE CASCADE,
    damage_level        severity_level NOT NULL DEFAULT 'UNKNOWN',
    is_primary_pest     BOOLEAN NOT NULL DEFAULT FALSE,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, pest_id)
);

CREATE INDEX idx_plant_pests_plant ON plant_pests (plant_id);
CREATE INDEX idx_plant_pests_pest ON plant_pests (pest_id);

CREATE TRIGGER trg_plant_pests_touch BEFORE UPDATE ON plant_pests
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE nutrient_deficiencies (
    id                      BIGSERIAL PRIMARY KEY,
    code                    TEXT NOT NULL UNIQUE,
    nutrient                TEXT NOT NULL,
    element_symbol          TEXT,
    deficiency_name         TEXT NOT NULL,
    is_mobile_in_plant      BOOLEAN,
    description             TEXT,
    visual_characteristics  TEXT,
    affected_parts          plant_part[],
    onset_pattern           TEXT,
    confusion_with          TEXT,
    soil_factors            TEXT,
    environmental_factors   TEXT,
    correction_guidance     TEXT,
    correction_is_advisory  BOOLEAN NOT NULL DEFAULT TRUE,
    overcorrection_risk     TEXT,
    severity_progression    TEXT,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    evidence_level          evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id               BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_nutrients_touch BEFORE UPDATE ON nutrient_deficiencies
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE INDEX idx_nutrients_nutrient ON nutrient_deficiencies (nutrient);

CREATE TABLE nutrient_symptoms (
    id                  BIGSERIAL PRIMARY KEY,
    nutrient_deficiency_id BIGINT NOT NULL REFERENCES nutrient_deficiencies(id) ON DELETE CASCADE,
    symptom_id          BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE RESTRICT,
    part                plant_part NOT NULL,
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    onset_stage         TEXT,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (nutrient_deficiency_id, symptom_id, part)
);

CREATE INDEX idx_nutrient_symptoms_nutrient ON nutrient_symptoms (nutrient_deficiency_id);
CREATE INDEX idx_nutrient_symptoms_symptom ON nutrient_symptoms (symptom_id);

CREATE TABLE environmental_stresses (
    id                  BIGSERIAL PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    description         TEXT,
    visual_characteristics TEXT,
    affected_parts      plant_part[],
    causal_factors      TEXT,
    distinguishing_from TEXT,
    correction_guidance TEXT,
    correction_is_advisory BOOLEAN NOT NULL DEFAULT TRUE,
    is_abiotic           BOOLEAN NOT NULL DEFAULT TRUE,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    evidence_level      evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT stresses_not_biotic CHECK (is_abiotic)
);

CREATE TRIGGER trg_stresses_touch BEFORE UPDATE ON environmental_stresses
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE stress_symptoms (
    id                  BIGSERIAL PRIMARY KEY,
    environmental_stress_id BIGINT NOT NULL REFERENCES environmental_stresses(id) ON DELETE CASCADE,
    symptom_id          BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE RESTRICT,
    part                plant_part NOT NULL,
    severity            severity_level NOT NULL DEFAULT 'UNKNOWN',
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (environmental_stress_id, symptom_id, part)
);

CREATE INDEX idx_stress_symptoms_stress ON stress_symptoms (environmental_stress_id);
CREATE INDEX idx_stress_symptoms_symptom ON stress_symptoms (symptom_id);

CREATE TABLE physical_damage_types (
    id                  BIGSERIAL PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    description         TEXT,
    visual_characteristics TEXT,
    distinguishing_notes TEXT,
    likely_causes       TEXT,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE physical_damage_symptoms (
    physical_damage_type_id BIGINT NOT NULL REFERENCES physical_damage_types(id) ON DELETE CASCADE,
    symptom_id              BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE CASCADE,
    part                    plant_part NOT NULL,
    severity                severity_level NOT NULL DEFAULT 'UNKNOWN',
    notes                   TEXT,
    PRIMARY KEY (physical_damage_type_id, symptom_id, part)
);

CREATE TABLE normal_variation_types (
    id                  BIGSERIAL PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    description         TEXT,
    distinguishing_notes TEXT,
    reassurance_note    TEXT,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE prevention_methods (
    id                  BIGSERIAL PRIMARY KEY,
    code                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    category            TEXT NOT NULL,
    description         TEXT,
    detailed_steps      TEXT,
    target_condition_class condition_class,
    effectiveness_evidence TEXT,
    evidence_level      evidence_level NOT NULL DEFAULT 'UNVERIFIED',
    jurisdiction        TEXT,
    is_reversible       BOOLEAN,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT prevention_category_known CHECK (
        category IN ('CULTURAL','SANITARY','GENETIC','BIOLOGICAL','CHEMICAL','PHYSICAL','MONITORING','QUARANTINE')
    )
);

CREATE TRIGGER trg_prevention_touch BEFORE UPDATE ON prevention_methods
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE condition_prevention (
    id                  BIGSERIAL PRIMARY KEY,
    condition_class     condition_class NOT NULL,
    condition_ref       BIGINT NOT NULL,
    prevention_id       BIGINT NOT NULL REFERENCES prevention_methods(id) ON DELETE CASCADE,
    priority            SMALLINT NOT NULL DEFAULT 100,
    notes               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (condition_class, condition_ref, prevention_id),
    CONSTRAINT condition_prevention_class CHECK (
        condition_class IN ('DISEASE','PEST','NUTRIENT_DEFICIENCY','ENVIRONMENTAL_STRESS','PHYSICAL_DAMAGE')
    )
);

CREATE INDEX idx_condition_prevention_ref ON condition_prevention (condition_class, condition_ref);

CREATE TABLE condition_lookalikes (
    id                  BIGSERIAL PRIMARY KEY,
    condition_class_a   condition_class NOT NULL,
    condition_ref_a     BIGINT NOT NULL,
    condition_class_b   condition_class NOT NULL,
    condition_ref_b     BIGINT NOT NULL,
    distinguishing_notes TEXT NOT NULL,
    confusion_risk      TEXT NOT NULL DEFAULT 'MODERATE',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (condition_class_a, condition_ref_a, condition_class_b, condition_ref_b),
    CONSTRAINT lookalike_not_self CHECK (
        NOT (condition_class_a = condition_class_b AND condition_ref_a = condition_ref_b)
    )
);

CREATE INDEX idx_lookalikes_a ON condition_lookalikes (condition_class_a, condition_ref_a);
CREATE INDEX idx_lookalikes_b ON condition_lookalikes (condition_class_b, condition_ref_b);
