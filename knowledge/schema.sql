-- PlantDoctor AI — bundled offline knowledge base (SQLite).
--
-- This schema is the single source of truth for the shipped application
-- database. It is created by knowledge/scripts/build_sqlite.py and validated
-- by knowledge/scripts/validate_plants.py.
--
-- Design rules (from the project specification):
--   * Every fact carries provenance: a `sources` row plus `data_provenance`.
--   * "Unknown" is a first-class value. A NULL or 'UNKNOWN' never means "safe".
--   * No invented dosage: a dose is only stored when a label reference exists.
--   * Taxonomy comes from GBIF Backbone (CC BY 4.0); agronomy only from curated,
--     cited files.
--
-- SQLite version required: 3.35+ (FTS5, generated columns).

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- 0. Build metadata / versioning
-- ---------------------------------------------------------------------------

CREATE TABLE meta (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL
);

-- Keys: database_version, schema_version, data_release, build_date,
--       source_release_versions (JSON)

-- ---------------------------------------------------------------------------
-- 1. Sources and provenance
-- ---------------------------------------------------------------------------

CREATE TABLE sources (
    id                  INTEGER PRIMARY KEY,
    source_key          TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    kind                TEXT NOT NULL,   -- taxonomy|agronomy|disease|pest|toxicity|image|treatment
    organization        TEXT,
    url                 TEXT,
    license             TEXT NOT NULL,
    license_url         TEXT,
    attribution         TEXT,
    attribution_required INTEGER NOT NULL DEFAULT 0,
    version             TEXT,
    retrieved_at        TEXT,
    notes               TEXT
);

CREATE TABLE source_records (
    id              INTEGER PRIMARY KEY,
    source_id       INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    external_id     TEXT,
    external_url    TEXT,
    record_kind     TEXT NOT NULL,
    payload_sha256  TEXT,
    retrieved_at    TEXT,
    notes           TEXT,
    UNIQUE (source_id, external_id, record_kind)
);

CREATE TABLE data_provenance (
    id                  INTEGER PRIMARY KEY,
    table_name          TEXT NOT NULL,
    record_id           INTEGER NOT NULL,
    field_name          TEXT NOT NULL,
    source_id           INTEGER NOT NULL REFERENCES sources(id),
    source_record_id    INTEGER REFERENCES source_records(id),
    extracted_value     TEXT,
    extraction_method   TEXT,
    confidence          TEXT NOT NULL DEFAULT 'UNKNOWN',
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    notes               TEXT,
    created_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX ix_provenance_record ON data_provenance (table_name, record_id);

CREATE TABLE verification_records (
    id                  INTEGER PRIMARY KEY,
    table_name          TEXT NOT NULL,
    record_id           INTEGER NOT NULL,
    verified_by         TEXT,
    verification_status TEXT NOT NULL,
    checked_at          TEXT,
    method              TEXT,
    notes               TEXT,
    source_id           INTEGER REFERENCES sources(id)
);

CREATE INDEX ix_verification_record
    ON verification_records (table_name, record_id);

-- ---------------------------------------------------------------------------
-- 2. Plants
-- ---------------------------------------------------------------------------

CREATE TABLE plants (
    id                      INTEGER PRIMARY KEY,
    slug                    TEXT NOT NULL UNIQUE,
    common_name             TEXT,
    scientific_name         TEXT NOT NULL,
    canonical_name          TEXT NOT NULL,
    genus                   TEXT,
    species                 TEXT,
    family                  TEXT,
    order_name              TEXT,
    class_name              TEXT,
    phylum                  TEXT,
    kingdom                 TEXT,
    authorship              TEXT,
    taxonomic_status        TEXT,
    is_accepted             INTEGER NOT NULL DEFAULT 1,
    external_taxon_source   TEXT,
    external_taxon_key      TEXT,
    description             TEXT,
    identification_features TEXT,
    growth_habit            TEXT,
    plant_height            TEXT,
    toxicity_status         TEXT NOT NULL DEFAULT 'UNKNOWN',
    verification_status     TEXT NOT NULL DEFAULT 'TAXONOMY_ONLY',
    last_verified           TEXT,
    source_id               INTEGER REFERENCES sources(id),
    created_at              TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at              TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX ix_plants_family ON plants (family);
CREATE INDEX ix_plants_genus  ON plants (genus);
CREATE INDEX ix_plants_taxon  ON plants (external_taxon_key);
CREATE INDEX ix_plants_common ON plants (common_name);

CREATE TABLE plant_names (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    name_type   TEXT NOT NULL,
    language    TEXT,
    region      TEXT,
    is_primary  INTEGER NOT NULL DEFAULT 0,
    source_id   INTEGER REFERENCES sources(id)
);

CREATE INDEX ix_plant_names_name ON plant_names (name);

CREATE TABLE plant_synonyms (
    id                  INTEGER PRIMARY KEY,
    plant_id            INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    scientific_name     TEXT NOT NULL,
    authorship          TEXT,
    taxonomic_status    TEXT,
    external_taxon_key  TEXT,
    source_id           INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, scientific_name)
);

CREATE TABLE plant_taxonomy (
    id                  INTEGER PRIMARY KEY,
    plant_id            INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    rank                TEXT NOT NULL,
    name                TEXT NOT NULL,
    external_taxon_key  TEXT,
    source_id           INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, rank)
);

-- ---------------------------------------------------------------------------
-- Name resolution
--
-- Identification models, regional extension material and ordinary users all
-- name the same plant differently ("Tomato", "tamatar", "टमाटर",
-- "Solanum lycopersicum", "Lycopersicon esculentum"). Rather than duplicating
-- a plant row per spelling, every accepted spelling is stored here against the
-- one plant it belongs to, together with a normalised form used for lookup.
-- ---------------------------------------------------------------------------

CREATE TABLE plant_aliases (
    id               INTEGER PRIMARY KEY,
    plant_id         INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    alias            TEXT NOT NULL,
    normalized_alias TEXT NOT NULL,
    alias_type       TEXT NOT NULL,
    language         TEXT,
    is_primary       INTEGER NOT NULL DEFAULT 0,
    source_id        INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, normalized_alias, alias_type)
);

CREATE INDEX ix_plant_aliases_norm ON plant_aliases (normalized_alias);
CREATE INDEX ix_plant_aliases_plant ON plant_aliases (plant_id);
CREATE INDEX ix_plant_aliases_type ON plant_aliases (alias_type);

-- Coarse plant-use grouping (food crop, vegetable, fruit, herb, ornamental,
-- rooftop/container garden...). Many-to-many: amaranth is a leafy vegetable,
-- a grain amaranth and a rooftop green, all at once.
CREATE TABLE plant_categories (
    id           INTEGER PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    label        TEXT NOT NULL,
    description  TEXT,
    sort_order   INTEGER NOT NULL DEFAULT 100
);

CREATE TABLE plant_category_map (
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    category_id INTEGER NOT NULL REFERENCES plant_categories(id) ON DELETE CASCADE,
    is_primary  INTEGER NOT NULL DEFAULT 0,
    source_id   INTEGER REFERENCES sources(id),
    PRIMARY KEY (plant_id, category_id)
);

CREATE INDEX ix_plant_category_cat ON plant_category_map (category_id, is_primary);

-- Curated agronomic / horticultural traits. Kept separate from
-- plant_characteristics, which holds GBIF-derived measured facts.
CREATE TABLE plant_traits (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    trait       TEXT NOT NULL,
    value       TEXT NOT NULL,
    unit        TEXT,
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, trait)
);

CREATE INDEX ix_plant_traits_trait ON plant_traits (trait);

-- Agricultural crop attributes: which part is harvested, sowing and harvest
-- windows, crop duration, and whether the species is a rainfed/rabi/kharif
-- crop in South Asian practice.
CREATE TABLE plant_crops (
    plant_id           INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    crop_role          TEXT,
    edible_part        TEXT,
    life_cycle         TEXT,
    sowing_season      TEXT,
    harvest_period     TEXT,
    growth_duration    TEXT,
    cultivation_system TEXT,
    seed_rate          TEXT,
    source_id          INTEGER REFERENCES sources(id)
);

-- Rooftop / terrace / container siting, derived from plant_rooftop so a
-- single query can answer "show me everything that grows on a balcony".
CREATE TABLE plant_rooftop_info (
    id                     INTEGER PRIMARY KEY,
    plant_id               INTEGER NOT NULL UNIQUE REFERENCES plants(id) ON DELETE CASCADE,
    rooftop_suitable       INTEGER NOT NULL DEFAULT 0,
    container_suitable     INTEGER NOT NULL DEFAULT 0,
    indoor_suitable        INTEGER NOT NULL DEFAULT 0,
    min_pot_size           TEXT,
    min_container_litres   INTEGER,
    sunlight_requirement   TEXT,
    water_requirement      TEXT,
    soil_type              TEXT,
    temperature_range      TEXT,
    growing_season         TEXT,
    rooftop_role           TEXT,
    exposure               TEXT,
    heat_tolerance         TEXT,
    drought_tolerance      TEXT,
    wind_exposure          TEXT,
    root_depth_cm          INTEGER,
    drainage               TEXT,
    watering_band          TEXT,
    establishment_watering TEXT,
    pruning_requirement    TEXT,
    special_hazards        TEXT,
    notes                  TEXT,
    verification_status    TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id              INTEGER REFERENCES sources(id)
);

CREATE INDEX ix_plant_rooftop_info_suitable
    ON plant_rooftop_info (rooftop_suitable, container_suitable);

-- Nutrient deficiency and environmental-stress applicability per plant.
CREATE TABLE plant_deficiencies (
    plant_id      INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    nutrient_id   INTEGER NOT NULL REFERENCES nutrient_deficiencies(id) ON DELETE CASCADE,
    likelihood    TEXT,
    notes         TEXT,
    source_id     INTEGER REFERENCES sources(id),
    PRIMARY KEY (plant_id, nutrient_id)
);

CREATE TABLE plant_environmental_stresses (
    plant_id  INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    stress_id INTEGER NOT NULL REFERENCES environmental_stresses(id) ON DELETE CASCADE,
    notes     TEXT,
    source_id INTEGER REFERENCES sources(id),
    PRIMARY KEY (plant_id, stress_id)
);

CREATE TABLE plant_parts (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    part        TEXT NOT NULL,
    description TEXT,
    edible      INTEGER,
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, part)
);

CREATE TABLE plant_characteristics (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    trait       TEXT NOT NULL,
    value       TEXT NOT NULL,
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, trait)
);

CREATE TABLE plant_appearance (
    plant_id            INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    leaf_features       TEXT,
    flower_features     TEXT,
    fruit_features      TEXT,
    stem_features       TEXT,
    root_features       TEXT,
    seed_features       TEXT,
    leaf_shape          TEXT,
    leaf_arrangement    TEXT,
    flower_color        TEXT,
    fruit_description   TEXT,
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE plant_growth (
    plant_id                INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    growth_habit            TEXT,
    plant_height            TEXT,
    climate                 TEXT,
    temperature_range       TEXT,
    soil_type               TEXT,
    soil_ph                 TEXT,
    water_requirement       TEXT,
    sunlight_requirement    TEXT,
    humidity                TEXT,
    growing_season          TEXT,
    sowing_season           TEXT,
    flowering_season        TEXT,
    fruiting_season         TEXT,
    harvest_period          TEXT,
    growth_duration         TEXT,
    propagation             TEXT,
    cultivation_information TEXT,
    source_id               INTEGER REFERENCES sources(id)
);

-- Rooftop / terrace siting data, from knowledge/data/curated/rooftop_greenery.json.
-- One row per species. This table holds horticultural siting facts only; it
-- never introduces a taxon, so plant_id is a foreign key and an unresolvable
-- name is a build failure rather than a new plant.
--
-- watering_band and the frequency language in establishment_watering are
-- deliberately qualitative. No column stores a measured volume, dilution or
-- spray recipe: the project does not publish application rates.
CREATE TABLE plant_rooftop (
    plant_id                INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    rooftop_role            TEXT,
    exposure                TEXT,
    heat_tolerance          TEXT,
    drought_tolerance       TEXT,
    wind_exposure           TEXT,
    min_container_litres    INTEGER,
    root_depth_cm           INTEGER,
    drainage                TEXT,
    watering_band           TEXT,
    establishment_watering  TEXT,
    pruning_requirement     TEXT,
    self_sown               TEXT,
    special_hazards         TEXT,
    notes                   TEXT,
    verification_status     TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id               INTEGER REFERENCES sources(id)
);

CREATE TABLE plant_distribution (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    region      TEXT NOT NULL,
    kind        TEXT NOT NULL DEFAULT 'native',
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, region, kind)
);

CREATE TABLE plant_uses (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    use_kind    TEXT NOT NULL,
    detail      TEXT,
    verified    INTEGER NOT NULL DEFAULT 0,
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, use_kind, detail)
);

CREATE TABLE plant_images (
    id              INTEGER PRIMARY KEY,
    plant_id        INTEGER REFERENCES plants(id) ON DELETE SET NULL,
    dataset         TEXT NOT NULL,
    image_path      TEXT,
    original_url    TEXT,
    plant_part      TEXT,
    condition       TEXT,
    disease_id      INTEGER,
    license         TEXT NOT NULL,
    copyright_status TEXT,
    attribution     TEXT,
    width           INTEGER,
    height          INTEGER,
    quality         TEXT,
    annotation      TEXT,
    verification    TEXT NOT NULL DEFAULT 'UNVERIFIED',
    split           TEXT,
    source_id       INTEGER REFERENCES sources(id),
    UNIQUE (dataset, image_path)
);

CREATE INDEX ix_plant_images_plant ON plant_images (plant_id);

-- ---------------------------------------------------------------------------
-- 3. Health conditions: diseases, pests, deficiencies, stress
-- ---------------------------------------------------------------------------

CREATE TABLE diseases (
    id                  INTEGER PRIMARY KEY,
    slug                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    pathogen_name       TEXT,
    pathogen_kind       TEXT,     -- fungus | bacterium | virus | oomycete | nematode | unknown
    description         TEXT,
    symptoms            TEXT,
    visual_symptoms     TEXT,
    early_symptoms      TEXT,
    advanced_symptoms   TEXT,
    favorable_conditions TEXT,
    transmission        TEXT,
    prevention          TEXT,
    management          TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       TEXT,
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE plant_diseases (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    disease_id  INTEGER NOT NULL REFERENCES diseases(id) ON DELETE CASCADE,
    severity    TEXT,
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, disease_id)
);

CREATE TABLE disease_symptoms (
    id          INTEGER PRIMARY KEY,
    disease_id  INTEGER NOT NULL REFERENCES diseases(id) ON DELETE CASCADE,
    symptom     TEXT NOT NULL,
    plant_part  TEXT,
    stage       TEXT,       -- early | advanced | any
    source_id   INTEGER REFERENCES sources(id)
);

CREATE UNIQUE INDEX ux_disease_symptoms
    ON disease_symptoms (disease_id, symptom, COALESCE(stage, ''));

CREATE TABLE disease_images (
    id              INTEGER PRIMARY KEY,
    disease_id      INTEGER NOT NULL REFERENCES diseases(id) ON DELETE CASCADE,
    dataset         TEXT NOT NULL,
    image_path      TEXT,
    original_url    TEXT,
    license         TEXT NOT NULL,
    attribution     TEXT,
    crop            TEXT,
    split           TEXT,
    source_id       INTEGER REFERENCES sources(id),
    UNIQUE (dataset, image_path)
);

CREATE TABLE pests (
    id                  INTEGER PRIMARY KEY,
    slug                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    scientific_name     TEXT,
    appearance          TEXT,
    feeding_behavior    TEXT,
    damage_symptoms     TEXT,
    life_stages         TEXT,
    prevention          TEXT,
    management          TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       TEXT,
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE plant_pests (
    id          INTEGER PRIMARY KEY,
    plant_id    INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    pest_id     INTEGER NOT NULL REFERENCES pests(id) ON DELETE CASCADE,
    severity    TEXT,
    source_id   INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, pest_id)
);

CREATE TABLE pest_symptoms (
    id          INTEGER PRIMARY KEY,
    pest_id     INTEGER NOT NULL REFERENCES pests(id) ON DELETE CASCADE,
    symptom     TEXT NOT NULL,
    plant_part  TEXT,
    source_id   INTEGER REFERENCES sources(id)
);

CREATE UNIQUE INDEX ux_pest_symptoms
    ON pest_symptoms (pest_id, symptom, COALESCE(plant_part, ''));

CREATE TABLE pest_images (
    id              INTEGER PRIMARY KEY,
    pest_id         INTEGER NOT NULL REFERENCES pests(id) ON DELETE CASCADE,
    dataset         TEXT NOT NULL,
    image_path      TEXT,
    original_url    TEXT,
    license         TEXT NOT NULL,
    attribution     TEXT,
    source_id       INTEGER REFERENCES sources(id),
    UNIQUE (dataset, image_path)
);

CREATE TABLE nutrient_deficiencies (
    id                  INTEGER PRIMARY KEY,
    slug                TEXT NOT NULL UNIQUE,
    nutrient            TEXT NOT NULL,      -- Nitrogen, Iron, ...
    symbol              TEXT,               -- N, Fe ...
    description         TEXT,
    visual_signs        TEXT,
    affected_parts      TEXT,
    similar_conditions  TEXT,
    soil_factors        TEXT,
    correction_guidance TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE plant_nutrient_deficiencies (
    id              INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    deficiency_id   INTEGER NOT NULL REFERENCES nutrient_deficiencies(id) ON DELETE CASCADE,
    source_id       INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, deficiency_id)
);

CREATE TABLE environmental_stresses (
    id                  INTEGER PRIMARY KEY,
    slug                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    description         TEXT,
    visual_signs        TEXT,
    similar_conditions  TEXT,
    correction_guidance TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE stress_symptoms (
    id          INTEGER PRIMARY KEY,
    stress_id   INTEGER NOT NULL REFERENCES environmental_stresses(id) ON DELETE CASCADE,
    symptom     TEXT NOT NULL,
    plant_part  TEXT,
    source_id   INTEGER REFERENCES sources(id)
);

-- ---------------------------------------------------------------------------
-- 4. Treatments (safety critical: a dose requires a label reference)
-- ---------------------------------------------------------------------------

CREATE TABLE active_ingredients (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    kind        TEXT,       -- fungicide | insecticide | herbicide | biological | nutrient
    description TEXT,
    source_id   INTEGER REFERENCES sources(id)
);

CREATE TABLE treatment_products (
    id                      INTEGER PRIMARY KEY,
    name                    TEXT NOT NULL,
    active_ingredient_id    INTEGER REFERENCES active_ingredients(id) ON DELETE SET NULL,
    formulation             TEXT,
    concentration           TEXT,
    product_kind            TEXT,
    jurisdiction            TEXT,
    registration_number     TEXT,
    source_id               INTEGER REFERENCES sources(id)
);


CREATE TABLE treatments (
    id                  INTEGER PRIMARY KEY,
    slug                TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    treatment_type      TEXT NOT NULL,   -- CULTURAL | MECHANICAL | BIOLOGICAL | CHEMICAL | PREVENTIVE
    description         TEXT,
    application_method  TEXT,
    frequency           TEXT,
    timing              TEXT,
    recommended_dosage  TEXT,            -- NULL unless label-verified
    dosage_unit         TEXT,
    water_volume        TEXT,
    pre_harvest_interval TEXT,
    waiting_period      TEXT,
    safety_precautions  TEXT,
    protective_equipment TEXT,
    label_page_reference TEXT,
    label_url           TEXT,
    label_sha256        TEXT,
    last_verified       TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE treatment_targets (
    id              INTEGER PRIMARY KEY,
    treatment_id    INTEGER NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    disease_id      INTEGER REFERENCES diseases(id) ON DELETE CASCADE,
    pest_id         INTEGER REFERENCES pests(id) ON DELETE CASCADE,
    deficiency_id   INTEGER REFERENCES nutrient_deficiencies(id) ON DELETE CASCADE,
    stress_id       INTEGER REFERENCES environmental_stresses(id) ON DELETE CASCADE,
    source_id       INTEGER REFERENCES sources(id),
    CHECK (
        (disease_id IS NOT NULL) OR (pest_id IS NOT NULL) OR
        (deficiency_id IS NOT NULL) OR (stress_id IS NOT NULL)
    )
);

CREATE TABLE treatment_plant_scope (
    id              INTEGER PRIMARY KEY,
    treatment_id    INTEGER NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    plant_id        INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    crop_name       TEXT,
    source_id       INTEGER REFERENCES sources(id),
    UNIQUE (treatment_id, plant_id)
);

CREATE TABLE treatment_product_links (
    id          INTEGER PRIMARY KEY,
    treatment_id INTEGER NOT NULL REFERENCES treatments(id) ON DELETE CASCADE,
    product_id  INTEGER NOT NULL REFERENCES treatment_products(id) ON DELETE CASCADE,
    UNIQUE (treatment_id, product_id)
);

CREATE TABLE prevention_methods (
    id              INTEGER PRIMARY KEY,
    slug            TEXT NOT NULL UNIQUE,
    method          TEXT NOT NULL,
    description     TEXT,
    applies_to      TEXT,       -- disease | pest | general
    disease_id      INTEGER REFERENCES diseases(id) ON DELETE CASCADE,
    pest_id         INTEGER REFERENCES pests(id) ON DELETE CASCADE,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id       INTEGER REFERENCES sources(id)
);

-- ---------------------------------------------------------------------------
-- 5. Safety / toxicity  (UNKNOWN != SAFE)
-- ---------------------------------------------------------------------------

CREATE TABLE toxicity_profiles (
    id                  INTEGER PRIMARY KEY,
    plant_id            INTEGER NOT NULL UNIQUE REFERENCES plants(id) ON DELETE CASCADE,
    toxicity_status     TEXT NOT NULL DEFAULT 'UNKNOWN',
    toxic_compounds     TEXT,
    exposure_routes     TEXT,
    symptoms            TEXT,
    severity            TEXT,
    safety_warning      TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       TEXT,
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE toxicity_parts (
    id              INTEGER PRIMARY KEY,
    plant_id        INTEGER NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    part            TEXT NOT NULL,
    toxicity_status TEXT NOT NULL DEFAULT 'UNKNOWN',
    notes           TEXT,
    source_id       INTEGER REFERENCES sources(id),
    UNIQUE (plant_id, part)
);

CREATE TABLE human_safety (
    plant_id            INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    risk_level          TEXT NOT NULL DEFAULT 'UNKNOWN',
    details             TEXT,
    first_aid           TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE pet_safety (
    plant_id            INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    risk_level          TEXT NOT NULL DEFAULT 'UNKNOWN',
    species_affected    TEXT,
    details             TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id)
);

CREATE TABLE livestock_safety (
    plant_id            INTEGER PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    risk_level          TEXT NOT NULL DEFAULT 'UNKNOWN',
    species_affected    TEXT,
    details             TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id)
);

-- ---------------------------------------------------------------------------
-- 6. Model registry (metrics are only ever real measurements)
-- ---------------------------------------------------------------------------

CREATE TABLE model_versions (
    id              INTEGER PRIMARY KEY,
    model_key       TEXT NOT NULL UNIQUE,
    name            TEXT NOT NULL,
    version         TEXT NOT NULL,
    task            TEXT NOT NULL,   -- species | crop_disease | quality
    architecture    TEXT,
    input_size      TEXT,
    output_classes  INTEGER,
    trained_on      TEXT,
    train_images    INTEGER,
    test_images     INTEGER,
    accuracy        REAL,
    top5_accuracy   REAL,
    macro_f1        REAL,
    macro_precision REAL,
    macro_recall    REAL,
    unknown_rejection_rate REAL,
    avg_inference_ms REAL,
    evaluated_at    TEXT,
    notes           TEXT
);

CREATE TABLE model_metrics (
    id              INTEGER PRIMARY KEY,
    model_id        INTEGER NOT NULL REFERENCES model_versions(id) ON DELETE CASCADE,
    class_name      TEXT NOT NULL,
    precision_value REAL,
    recall_value    REAL,
    f1_value        REAL,
    support         INTEGER
);

-- Deferred unique indexes (SQLite cannot express COALESCE(...) inside a
-- table-level UNIQUE constraint).
CREATE UNIQUE INDEX ux_plant_names
    ON plant_names (plant_id, name, name_type, COALESCE(language, ''));
CREATE UNIQUE INDEX ux_plant_uses
    ON plant_uses (plant_id, use_kind, COALESCE(detail, ''));
CREATE UNIQUE INDEX ux_treatment_products
    ON treatment_products (name, COALESCE(concentration, ''), COALESCE(jurisdiction, ''));
CREATE UNIQUE INDEX ux_prevention_methods_scope
    ON prevention_methods (COALESCE(disease_id, -1), COALESCE(pest_id, -1), method);

-- ---------------------------------------------------------------------------
-- 7. Full-text search (offline search by name / family / symptom / condition)
-- ---------------------------------------------------------------------------

CREATE VIRTUAL TABLE plants_fts USING fts5 (
    plant_id UNINDEXED,
    names,          -- common + local + scientific + synonyms + family + genus
    family,
    tokenize = 'unicode61 remove_diacritics 2'
);

CREATE VIRTUAL TABLE conditions_fts USING fts5 (
    condition_kind UNINDEXED,   -- disease | pest | deficiency | stress
    condition_id UNINDEXED,
    name,
    keywords,       -- symptoms, host crops, pathogen
    tokenize = 'unicode61 remove_diacritics 2'
);

-- ---------------------------------------------------------------------------
-- 8. Read models used by the app
-- ---------------------------------------------------------------------------

CREATE VIEW v_plant_profile AS
SELECT
    p.id,
    p.slug,
    p.common_name,
    p.scientific_name,
    p.canonical_name,
    p.family,
    p.genus,
    p.order_name,
    p.kingdom,
    p.description,
    p.identification_features,
    p.toxicity_status,
    p.verification_status,
    p.last_verified,
    s.name       AS source_name,
    s.url        AS source_url,
    s.license    AS source_license
FROM plants p
LEFT JOIN sources s ON s.id = p.source_id;

CREATE VIEW v_plant_condition_summary AS
SELECT p.id AS plant_id,
       p.common_name,
       (SELECT COUNT(*) FROM plant_diseases pd WHERE pd.plant_id = p.id) AS disease_count,
       (SELECT COUNT(*) FROM plant_pests pp WHERE pp.plant_id = p.id) AS pest_count,
       (SELECT COUNT(*) FROM plant_nutrient_deficiencies pn WHERE pn.plant_id = p.id) AS deficiency_count,
       (SELECT COUNT(*) FROM plant_images pi WHERE pi.plant_id = p.id) AS image_count
FROM plants p;

-- Dosage is deliberately only visible when a label reference exists.
CREATE VIEW v_treatment_dosage_verified AS
SELECT t.id,
       t.slug,
       t.name,
       t.treatment_type,
       t.recommended_dosage,
       t.dosage_unit,
       t.water_volume,
       t.application_method,
       t.frequency,
       t.timing,
       t.pre_harvest_interval,
       t.safety_precautions,
       t.protective_equipment,
       t.label_page_reference,
       t.label_url,
       t.last_verified
FROM treatments t
WHERE t.recommended_dosage IS NOT NULL
  AND t.label_page_reference IS NOT NULL
  AND t.label_url IS NOT NULL
  AND t.last_verified IS NOT NULL;

CREATE VIEW v_unknown_toxicity AS
SELECT p.id AS plant_id, p.common_name, p.scientific_name, p.toxicity_status
FROM plants p
WHERE p.toxicity_status = 'UNKNOWN';

-- ---------------------------------------------------------------------------
-- 9. Health screening categories (mirrors the app's contract)
-- ---------------------------------------------------------------------------
CREATE TABLE health_categories (
    code        TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    description TEXT
);

INSERT INTO health_categories (code, label, description) VALUES
    ('HEALTHY', 'Appears healthy', 'No visible damage pattern reached the screening threshold.'),
    ('POSSIBLE_DISEASE', 'Possible disease', 'Visible pattern consistent with a known disease symptom.'),
    ('POSSIBLE_PEST', 'Possible pest damage', 'Visible pattern consistent with pest feeding damage.'),
    ('POSSIBLE_NUTRIENT_DEFICIENCY', 'Possible nutrient deficiency', 'Visible pattern consistent with a nutrient shortage.'),
    ('POSSIBLE_ENVIRONMENTAL_STRESS', 'Possible environmental stress', 'Visible pattern consistent with heat, cold, water or light stress.'),
    ('PHYSICAL_DAMAGE', 'Physical damage', 'Mechanical injury such as cuts, tears or sunscald.'),
    ('UNKNOWN', 'Cannot determine', 'Not enough evidence to classify.'),
    ('INSUFFICIENT_IMAGE_QUALITY', 'Insufficient image quality', 'The photo cannot support a screening result.');

-- ---------------------------------------------------------------------------
-- 10. Model class mappings
-- ---------------------------------------------------------------------------
-- The bridge between a trained model's raw output index and the knowledge
-- base. A class that the model cannot map to a real record is stored as
-- kind='other' so the app returns "identification uncertain" rather than
-- forcing the photo into a known class.
CREATE TABLE model_classes (
    id                  INTEGER PRIMARY KEY,
    model_key           TEXT NOT NULL,
    class_index         INTEGER NOT NULL,
    class_label         TEXT NOT NULL,
    display_name        TEXT,
    kind                TEXT NOT NULL,   -- plant | disease | pest | healthy | other
    plant_id            INTEGER REFERENCES plants(id) ON DELETE SET NULL,
    disease_id          INTEGER REFERENCES diseases(id) ON DELETE SET NULL,
    pest_id             INTEGER REFERENCES pests(id) ON DELETE SET NULL,
    deficiency_id       INTEGER REFERENCES nutrient_deficiencies(id) ON DELETE SET NULL,
    health_code         TEXT REFERENCES health_categories(code),
    dataset             TEXT,
    notes               TEXT,
    verification_status TEXT NOT NULL DEFAULT 'UNVERIFIED',
    source_id           INTEGER REFERENCES sources(id),
    UNIQUE (model_key, class_index)
);

CREATE INDEX ix_model_classes_model ON model_classes (model_key);

