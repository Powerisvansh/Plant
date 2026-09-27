-- 003_plants_core.sql
-- Plants, names, taxonomy, synonyms, growth requirements, habitats, parts.

CREATE TABLE plants (
    id                          BIGSERIAL PRIMARY KEY,
    scientific_name             TEXT NOT NULL,
    scientific_name_authorship  TEXT,
    canonical_name              TEXT GENERATED ALWAYS AS
                                    (lower(regexp_replace(scientific_name, '\s+', ' ', 'g'))) STORED,
    genus                       TEXT,
    species                     TEXT,
    infraspecific_rank          TEXT,
    infraspecific_epithet       TEXT,
    family                      TEXT,
    order_name                  TEXT,
    class_name                  TEXT,
    phylum                      TEXT,
    kingdom                     TEXT,
    taxonomic_status            TEXT,
    taxonomic_authority         TEXT,
    is_accepted                 BOOLEAN NOT NULL DEFAULT TRUE,
    external_taxon_key          TEXT,
    external_taxon_source       TEXT,
    description                 TEXT,
    identification_summary      TEXT,
    growth_habit                TEXT,
    lifespan                    TEXT,
    mature_height_min_m         NUMERIC(8,2) CHECK (mature_height_min_m IS NULL OR mature_height_min_m >= 0),
    mature_height_max_m         NUMERIC(8,2) CHECK (mature_height_max_m IS NULL OR mature_height_max_m >= 0),
    mature_spread_min_m         NUMERIC(8,2) CHECK (mature_spread_min_m IS NULL OR mature_spread_min_m >= 0),
    mature_spread_max_m         NUMERIC(8,2) CHECK (mature_spread_max_m IS NULL OR mature_spread_max_m >= 0),
    native_range_summary        TEXT,
    introduced_range_summary    TEXT,
    distribution_summary        TEXT,
    conservation_status         TEXT,
    agricultural_importance     TEXT,
    ornamental_use              TEXT,
    known_uses                  TEXT,
    edible_status               TEXT,
    edible_status_note          TEXT,
    habitat_summary             TEXT,
    identification_notes        TEXT,
    verification_status         verification_status NOT NULL DEFAULT 'UNVERIFIED',
    taxonomic_source_id         BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    content_version             INTEGER NOT NULL DEFAULT 1,
    is_deleted                  BOOLEAN NOT NULL DEFAULT FALSE,
    last_verified               DATE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT plants_height_range CHECK (
        mature_height_min_m IS NULL OR mature_height_max_m IS NULL
        OR mature_height_min_m <= mature_height_max_m
    ),
    CONSTRAINT plants_spread_range CHECK (
        mature_spread_min_m IS NULL OR mature_spread_max_m IS NULL
        OR mature_spread_min_m <= mature_spread_max_m
    )
);

CREATE UNIQUE INDEX uq_plants_canonical_name ON plants (canonical_name) WHERE is_deleted;
CREATE INDEX idx_plants_genus ON plants (genus) WHERE is_deleted;
CREATE INDEX idx_plants_family ON plants (family) WHERE is_deleted;
CREATE INDEX idx_plants_order ON plants (order_name) WHERE is_deleted;
CREATE INDEX idx_plants_taxonomic_source ON plants (taxonomic_source_id);
CREATE INDEX idx_plants_verification ON plants (verification_status);
CREATE INDEX idx_plants_external_key ON plants (external_taxon_source, external_taxon_key);

CREATE TRIGGER trg_plants_touch BEFORE UPDATE ON plants
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE plant_names (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    normalized_name     TEXT GENERATED ALWAYS AS (lower(name)) STORED,
    name_type           TEXT NOT NULL DEFAULT 'COMMON',
    language_code       TEXT,
    region              TEXT,
    is_preferred        BOOLEAN NOT NULL DEFAULT FALSE,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, name, language_code, region),
    CONSTRAINT plant_names_type_known CHECK (
        name_type IN ('COMMON','VERNACULAR','LOCAL','TRIVIAL','CULTIVAR','TRADEMARK','OTHER')
    )
);

CREATE INDEX idx_plant_names_plant ON plant_names (plant_id);
CREATE INDEX idx_plant_names_norm ON plant_names (normalized_name);
CREATE UNIQUE INDEX uq_plant_names_preferred
    ON plant_names (plant_id) WHERE is_preferred;

CREATE TABLE plant_taxonomy (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    rank                TEXT NOT NULL,
    name                TEXT NOT NULL,
    rank_parent         TEXT,
    external_key        TEXT,
    external_source     TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, rank, name)
);

CREATE INDEX idx_plant_taxonomy_plant ON plant_taxonomy (plant_id);
CREATE INDEX idx_plant_taxonomy_name ON plant_taxonomy (lower(name));

CREATE TABLE plant_synonyms (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    synonym             TEXT NOT NULL,
    normalized_synonym  TEXT GENERATED ALWAYS AS (lower(synonym)) STORED,
    nomenclatural_status TEXT,
    publication         TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, synonym)
);

CREATE INDEX idx_plant_synonyms_norm ON plant_synonyms (normalized_synonym);

CREATE TABLE plant_growth_requirements (
    id                      BIGSERIAL PRIMARY KEY,
    plant_id                BIGINT NOT NULL UNIQUE REFERENCES plants(id) ON DELETE CASCADE,
    climate                 TEXT,
    temperature_min_c       NUMERIC(5,2) CHECK (temperature_min_c IS NULL OR temperature_min_c BETWEEN -80 AND 80),
    temperature_max_c       NUMERIC(5,2) CHECK (temperature_max_c IS NULL OR temperature_max_c BETWEEN -80 AND 80),
    temperature_optimal_min_c NUMERIC(5,2),
    temperature_optimal_max_c NUMERIC(5,2),
    temperature_basis       measurement_basis NOT NULL DEFAULT 'NOT_MEASURED',
    sunlight                TEXT,
    water_requirement       TEXT,
    soil_type               TEXT,
    soil_ph_min             NUMERIC(4,2) CHECK (soil_ph_min IS NULL OR (soil_ph_min >= 0 AND soil_ph_min <= 14)),
    soil_ph_max             NUMERIC(4,2) CHECK (soil_ph_max IS NULL OR (soil_ph_max >= 0 AND soil_ph_max <= 14)),
    soil_drainage           TEXT,
    humidity_min_pct        NUMERIC(5,2) CHECK (humidity_min_pct IS NULL OR (humidity_min_pct >= 0 AND humidity_min_pct <= 100)),
    humidity_max_pct        NUMERIC(5,2) CHECK (humidity_max_pct IS NULL OR (humidity_max_pct >= 0 AND humidity_max_pct <= 100)),
    growing_season          TEXT,
    frost_tolerance         TEXT,
    drought_tolerance       TEXT,
    waterlog_tolerance      TEXT,
    propagation_methods     TEXT[],
    pruning                 TEXT,
    fertilization           TEXT,
    spacing                 TEXT,
    source_id               BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status     verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified           DATE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT growth_temp_range CHECK (
        temperature_min_c IS NULL OR temperature_max_c IS NULL
        OR temperature_min_c <= temperature_max_c
    ),
    CONSTRAINT growth_ph_range CHECK (
        soil_ph_min IS NULL OR soil_ph_max IS NULL OR soil_ph_min <= soil_ph_max
    )
);

CREATE TRIGGER trg_growth_touch BEFORE UPDATE ON plant_growth_requirements
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE plant_habitats (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    habitat_type        TEXT,
    biome               TEXT,
    ecosystem           TEXT,
    region              TEXT,
    country             TEXT,
    elevation_min_m     NUMERIC(8,2) CHECK (elevation_min_m IS NULL OR elevation_min_m >= -500),
    elevation_max_m     NUMERIC(8,2) CHECK (elevation_max_m IS NULL OR elevation_max_m >= -500),
    description         TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, habitat_type, biome, region),
    CONSTRAINT habitats_elevation_range CHECK (
        elevation_min_m IS NULL OR elevation_max_m IS NULL OR elevation_min_m <= elevation_max_m
    )
);

CREATE INDEX idx_plant_habitats_plant ON plant_habitats (plant_id);

CREATE TABLE plant_parts (
    id              BIGSERIAL PRIMARY KEY,
    plant_id        BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    part            plant_part NOT NULL,
    part_name       TEXT,
    present_season  TEXT,
    is_evergreen    BOOLEAN,
    description     TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, part)
);

CREATE INDEX idx_plant_parts_plant ON plant_parts (plant_id);

CREATE TABLE plant_characteristics (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    part                plant_part NOT NULL,
    characteristic_type TEXT NOT NULL,
    characteristic_name TEXT NOT NULL,
    value_text          TEXT,
    value_numeric_min   NUMERIC(14,4),
    value_numeric_max   NUMERIC(14,4),
    value_numeric       NUMERIC(14,4),
    unit                TEXT,
    qualifier           TEXT,
    measurement_basis   measurement_basis NOT NULL DEFAULT 'NOT_MEASURED',
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT characteristics_numeric_range CHECK (
        value_numeric_min IS NULL OR value_numeric_max IS NULL
        OR value_numeric_min <= value_numeric_max
    ),
    CONSTRAINT characteristics_type_known CHECK (
        characteristic_type IN (
            'DIMENSION','COLOR','SHAPE','TEXTURE','ARRANGEMENT','PHENOLOGY',
            'HABIT','ODOR','CHEMICAL','LIFECYCLE','OTHER'
        )
    )
);

CREATE UNIQUE INDEX uq_plant_characteristic
    ON plant_characteristics (plant_id, part, characteristic_type, characteristic_name);
CREATE INDEX idx_plant_characteristics_plant ON plant_characteristics (plant_id);
CREATE INDEX idx_plant_characteristics_lookup ON plant_characteristics (characteristic_name);

CREATE TABLE plant_identification_features (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    part                plant_part NOT NULL,
    feature             TEXT NOT NULL,
    description         TEXT,
    distinguish_from    TEXT,
    diagnostic_weight   SMALLINT CHECK (diagnostic_weight IS NULL OR diagnostic_weight BETWEEN 1 AND 5),
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, part, feature)
);

CREATE INDEX idx_plant_id_features_plant ON plant_identification_features (plant_id);
