-- 009_search.sql
-- Full-text + trigram search indexes.
-- Denormalized search documents are maintained by trigger so that GIN indexes
-- can be used; a plain view cannot carry an index.

CREATE TABLE plant_search_index (
    plant_id        BIGINT PRIMARY KEY REFERENCES plants(id) ON DELETE CASCADE,
    scientific_name TEXT NOT NULL,
    common_names    TEXT,
    synonyms        TEXT,
    family          TEXT,
    genus           TEXT,
    doc             tsvector NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_reindex_plant(p_plant_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_sci   TEXT;
    v_genus TEXT;
    v_fam   TEXT;
    v_names TEXT;
    v_syn   TEXT;
    v_doc   tsvector;
BEGIN
    SELECT p.scientific_name, p.genus, p.family
      INTO v_sci, v_genus, v_fam
      FROM plants p
     WHERE p.id = p_plant_id AND p.is_deleted = FALSE;

    IF v_sci IS NULL THEN
        DELETE FROM plant_search_index WHERE plant_id = p_plant_id;
        RETURN;
    END IF;

    SELECT string_agg(DISTINCT n.name, ' ' ORDER BY n.name)
      INTO v_names
      FROM plant_names n
     WHERE n.plant_id = p_plant_id;

    SELECT string_agg(DISTINCT s.synonym, ' ' ORDER BY s.synonym)
      INTO v_syn
      FROM plant_synonyms s
     WHERE s.plant_id = p_plant_id;

    v_doc := setweight(to_tsvector('simple', coalesce(v_sci, '')), 'A')
          || setweight(to_tsvector('simple', coalesce(v_names, '')), 'A')
          || setweight(to_tsvector('simple', coalesce(v_syn, '')), 'B')
          || setweight(to_tsvector('simple', coalesce(v_genus, '')), 'B')
          || setweight(to_tsvector('simple', coalesce(v_fam, '')), 'C');

    INSERT INTO plant_search_index
        (plant_id, scientific_name, common_names, synonyms, family, genus, doc, updated_at)
    VALUES
        (p_plant_id, v_sci, v_names, v_syn, v_fam, v_genus, v_doc, now())
    ON CONFLICT (plant_id) DO UPDATE
        SET scientific_name = EXCLUDED.scientific_name,
            common_names    = EXCLUDED.common_names,
            synonyms        = EXCLUDED.synonyms,
            family          = EXCLUDED.family,
            genus           = EXCLUDED.genus,
            doc             = EXCLUDED.doc,
            updated_at      = now();
END;
$$;

CREATE INDEX idx_plant_search_doc ON plant_search_index USING gin (doc);
CREATE INDEX idx_plant_search_sci_trgm ON plant_search_index USING gin (scientific_name gin_trgm_ops);
CREATE INDEX idx_plant_search_names_trgm ON plant_search_index USING gin (common_names gin_trgm_ops);
CREATE INDEX idx_plant_search_syn_trgm ON plant_search_index USING gin (synonyms gin_trgm_ops);

CREATE OR REPLACE FUNCTION fn_trigger_reindex_plant() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id BIGINT := COALESCE(NEW.plant_id, NEW.id, OLD.plant_id, OLD.id);
BEGIN
    PERFORM fn_reindex_plant(v_id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_reindex_plants AFTER INSERT OR UPDATE OF scientific_name, genus, family, is_deleted
    ON plants FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();
CREATE TRIGGER trg_reindex_plants_delete AFTER DELETE ON plants
    FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();
CREATE TRIGGER trg_reindex_names AFTER INSERT OR UPDATE OR DELETE
    ON plant_names FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();
CREATE TRIGGER trg_reindex_synonyms AFTER INSERT OR UPDATE OR DELETE
    ON plant_synonyms FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();

CREATE TABLE condition_search_index (
    condition_class condition_class NOT NULL,
    condition_ref   BIGINT NOT NULL,
    title           TEXT NOT NULL,
    subtitle        TEXT,
    keywords        TEXT,
    doc             tsvector NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (condition_class, condition_ref)
);

CREATE INDEX idx_condition_search_doc ON condition_search_index USING gin (doc);
CREATE INDEX idx_condition_search_title_trgm ON condition_search_index USING gin (title gin_trgm_ops);

CREATE OR REPLACE FUNCTION fn_reindex_disease(p_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_doc tsvector; v_name TEXT; v_pathogen TEXT; v_syms TEXT;
BEGIN
    SELECT d.name, d.pathogen_scientific_name INTO v_name, v_pathogen
      FROM diseases d WHERE d.id = p_id;
    IF v_name IS NULL THEN
        DELETE FROM condition_search_index WHERE condition_class = 'DISEASE' AND condition_ref = p_id;
        RETURN;
    END IF;
    SELECT string_agg(DISTINCT s.name, ' ' ORDER BY s.name) INTO v_syms
      FROM disease_symptoms ds JOIN symptoms s ON s.id = ds.symptom_id
     WHERE ds.disease_id = p_id;
    v_doc := setweight(to_tsvector('simple', v_name), 'A')
          || setweight(to_tsvector('simple', coalesce(v_pathogen, '')), 'A')
          || setweight(to_tsvector('simple', coalesce(v_syms, '')), 'B');
    INSERT INTO condition_search_index (condition_class, condition_ref, title, subtitle, keywords, doc, updated_at)
    VALUES ('DISEASE', p_id, v_name, v_pathogen, v_syms, v_doc, now())
    ON CONFLICT (condition_class, condition_ref) DO UPDATE
        SET title = EXCLUDED.title, subtitle = EXCLUDED.subtitle,
            keywords = EXCLUDED.keywords, doc = EXCLUDED.doc, updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION fn_reindex_pest(p_id BIGINT) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_doc tsvector; v_name TEXT; v_sci TEXT; v_syms TEXT;
BEGIN
    SELECT p.name, p.scientific_name INTO v_name, v_sci FROM pests p WHERE p.id = p_id;
    IF v_name IS NULL THEN
        DELETE FROM condition_search_index WHERE condition_class = 'PEST' AND condition_ref = p_id;
        RETURN;
    END IF;
    SELECT string_agg(DISTINCT s.name, ' ' ORDER BY s.name) INTO v_syms
      FROM pest_symptoms ps JOIN symptoms s ON s.id = ps.symptom_id
     WHERE ps.pest_id = p_id;
    v_doc := setweight(to_tsvector('simple', v_name), 'A')
          || setweight(to_tsvector('simple', coalesce(v_sci, '')), 'A')
          || setweight(to_tsvector('simple', coalesce(v_syms, '')), 'B');
    INSERT INTO condition_search_index (condition_class, condition_ref, title, subtitle, keywords, doc, updated_at)
    VALUES ('PEST', p_id, v_name, v_sci, v_syms, v_doc, now())
    ON CONFLICT (condition_class, condition_ref) DO UPDATE
        SET title = EXCLUDED.title, subtitle = EXCLUDED.subtitle,
            keywords = EXCLUDED.keywords, doc = EXCLUDED.doc, updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION fn_trigger_reindex_disease() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := COALESCE(NEW.disease_id, NEW.id, OLD.disease_id, OLD.id);
BEGIN
    PERFORM fn_reindex_disease(v_id);
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trigger_reindex_pest() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := COALESCE(NEW.pest_id, NEW.id, OLD.pest_id, OLD.id);
BEGIN
    PERFORM fn_reindex_pest(v_id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_reindex_diseases AFTER INSERT OR UPDATE OF name, pathogen_scientific_name
    ON diseases FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_disease();
CREATE TRIGGER trg_reindex_diseases_del AFTER DELETE ON diseases
    FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_disease();
CREATE TRIGGER trg_reindex_disease_symptoms AFTER INSERT OR UPDATE OR DELETE
    ON disease_symptoms FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_disease();
CREATE TRIGGER trg_reindex_pests AFTER INSERT OR UPDATE OF name, scientific_name
    ON pests FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_pest();
CREATE TRIGGER trg_reindex_pests_del AFTER DELETE ON pests
    FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_pest();
CREATE TRIGGER trg_reindex_pest_symptoms AFTER INSERT OR UPDATE OR DELETE
    ON pest_symptoms FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_pest();

-- Public search entry point. Ranking is by ts_rank plus an exact/prefix boost.
CREATE OR REPLACE FUNCTION fn_search_plants(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
) RETURNS TABLE (
    plant_id BIGINT,
    scientific_name TEXT,
    common_names TEXT,
    family TEXT,
    rank REAL
)
LANGUAGE sql STABLE AS $$
    WITH q AS (SELECT btrim(coalesce(p_query, '')) AS txt)
    SELECT si.plant_id,
           si.scientific_name,
           si.common_names,
           si.family,
           (
             ts_rank(si.doc, websearch_to_tsquery('simple', q.txt))
             + CASE WHEN lower(si.scientific_name) = lower(q.txt) THEN 10 ELSE 0 END
             + CASE WHEN lower(si.scientific_name) LIKE lower(q.txt) || '%' THEN 5 ELSE 0 END
             + CASE WHEN si.common_names ILIKE '%' || q.txt || '%' THEN 3 ELSE 0 END
           )::REAL AS rank
      FROM plant_search_index si, q
     WHERE q.txt <> ''
       AND (
             si.doc @@ websearch_to_tsquery('simple', q.txt)
          OR si.scientific_name ILIKE '%' || q.txt || '%'
          OR si.common_names   ILIKE '%' || q.txt || '%'
          OR si.synonyms       ILIKE '%' || q.txt || '%'
       )
     ORDER BY rank DESC, si.scientific_name
     LIMIT LEAST(GREATEST(p_limit, 1), 200)
     OFFSET GREATEST(p_offset, 0);
$$;

CREATE OR REPLACE FUNCTION fn_search_conditions(
    p_query TEXT,
    p_class condition_class DEFAULT NULL,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
) RETURNS TABLE (
    condition_class condition_class,
    condition_ref BIGINT,
    title TEXT,
    subtitle TEXT,
    rank REAL
)
LANGUAGE sql STABLE AS $$
    WITH q AS (SELECT btrim(coalesce(p_query, '')) AS txt)
    SELECT c.condition_class, c.condition_ref, c.title, c.subtitle,
           (ts_rank(c.doc, websearch_to_tsquery('simple', q.txt))
            + CASE WHEN lower(c.title) = lower(q.txt) THEN 10 ELSE 0 END
            + CASE WHEN c.title ILIKE lower(q.txt) || '%' THEN 5 ELSE 0 END)::REAL AS rank
      FROM condition_search_index c, q
     WHERE q.txt <> ''
       AND (p_class IS NULL OR c.condition_class = p_class)
       AND (c.doc @@ websearch_to_tsquery('simple', q.txt) OR c.title ILIKE '%' || q.txt || '%')
     ORDER BY rank DESC, c.title
     LIMIT LEAST(GREATEST(p_limit, 1), 200)
     OFFSET GREATEST(p_offset, 0);
$$;
