-- 004_appearance.sql
-- What a HEALTHY plant normally looks like, per plant part.
-- Numeric values must declare how they were obtained; `measurement_basis`
-- prevents invented measurements from being presented as fact.

CREATE TABLE plant_appearance (
    id                  BIGSERIAL PRIMARY KEY,
    plant_id            BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    part                plant_part NOT NULL,
    summary             TEXT,
    description         TEXT,
    season              TEXT,
    stage               TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    last_verified       DATE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plant_id, part)
);

CREATE TRIGGER trg_appearance_touch BEFORE UPDATE ON plant_appearance
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE plant_appearance_attributes (
    id                  BIGSERIAL PRIMARY KEY,
    appearance_id       BIGINT NOT NULL REFERENCES plant_appearance(id) ON DELETE CASCADE,
    attribute           TEXT NOT NULL,
    attribute_value     TEXT NOT NULL,
    color_name          TEXT,
    color_hex           TEXT CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-Fa-f]{6}$'),
    value_min           NUMERIC(14,4),
    value_max           NUMERIC(14,4),
    unit                TEXT,
    measurement_basis   measurement_basis NOT NULL DEFAULT 'REPORTED_BY_SOURCE',
    is_normal_variation BOOLEAN NOT NULL DEFAULT FALSE,
    variation_note      TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    verification_status verification_status NOT NULL DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT appearance_attr_type CHECK (
        attribute IN (
            'COLOR','SHAPE','TEXTURE','SIZE_RANGE','ARRANGEMENT',
            'GROWTH_PATTERN','SURFACE','MARGIN','VENATION','NORMAL_VARIATION','OTHER'
        )
    ),
    CONSTRAINT appearance_attr_range CHECK (
        value_min IS NULL OR value_max IS NULL OR value_min <= value_max
    )
);

CREATE UNIQUE INDEX uq_appearance_attribute
    ON plant_appearance_attributes (appearance_id, attribute, attribute_value);
CREATE INDEX idx_appearance_attr_lookup ON plant_appearance_attributes (attribute, color_name);
