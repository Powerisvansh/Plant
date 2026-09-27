-- 013_display_casing_and_search_repair.sql
-- Two real defects found after 012_canonical_name_integrity.sql was applied:
--
--   1. `fn_bare_taxon_name()` lowercases as a side effect, so Step 1 of 012
--      rewrote display names to "solanum lycopersicum". `canonical_name` is
--      the normalised/lookup key and may be lowercase, but `scientific_name`
--      is what the UI and the API return, so it must keep botanical casing.
--   2. `fn_trigger_reindex_plant()` in 009 uses
--      `COALESCE(NEW.plant_id, NEW.id, ...)`. `plants` has no `plant_id`
--      column, so the trigger on `plants` raised an error; on `plant_names`
--      and `plant_synonyms` it silently reindexed the *name row's* id as if
--      it were a plant id. A patch had been applied straight to the live
--      database, which made the plant triggers work but left the child-table
--      triggers indexing the wrong id, and left fresh installs broken.
--
-- This migration fixes both in a reproducible, versioned way.

-- ---------------------------------------------------------------------------
-- Step 1: restore botanical display casing.
-- Only rows that are entirely lowercase are touched, and only the genus is
-- capitalised: "Solanum lycopersicum". Infraspecific rank words (subsp., var.,
-- f.) and their following terms are left alone because their casing is not
-- predictable from the binomial.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    row RECORD;
    parts TEXT[];
    v_genus TEXT;
    v_tail  TEXT;
BEGIN
    FOR row IN
        SELECT id, scientific_name
          FROM plants
         WHERE scientific_name IS NOT NULL
           AND btrim(scientific_name) <> ''
           AND scientific_name = lower(scientific_name)
    LOOP
        parts := string_to_array(
            btrim(regexp_replace(row.scientific_name, '\s+', ' ', 'g')), ' ');
        IF array_length(parts, 1) < 2 THEN
            CONTINUE;
        END IF;
        v_genus := upper(left(parts[1], 1)) || lower(substr(parts[1], 2));
        v_tail  := lower(array_to_string(parts[2:array_length(parts, 1)], ' '));
        UPDATE plants
           SET scientific_name = v_genus || ' ' || v_tail
         WHERE id = row.id;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Step 2: table-aware reindex trigger.
-- 009 used COALESCE(NEW.plant_id, NEW.id, ...). `plants` has no `plant_id`
-- column, so the plant triggers raised an error, and on plant_names /
-- plant_synonyms it silently reindexed the *name row's* id as if it were a
-- plant id. A patch had been applied straight to the live database, which made
-- the plant triggers work but left the child-table triggers indexing the wrong
-- id, and left fresh installs broken.
--
-- TG_TABLE_NAME and TG_OP are only readable inside a trigger function, so the
-- dispatch has to live in the trigger function itself. NEW/OLD are record
-- variables, so the field access is resolved at run time per table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trigger_reindex_plant() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id BIGINT;
BEGIN
    IF TG_TABLE_NAME = 'plants' THEN
        v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
    ELSIF TG_TABLE_NAME IN ('plant_names', 'plant_synonyms') THEN
        v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.plant_id ELSE NEW.plant_id END;
    ELSE
        RAISE EXCEPTION 'fn_trigger_reindex_plant: unsupported table %', TG_TABLE_NAME;
    END IF;

    IF v_id IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM fn_reindex_plant(v_id);
    RETURN NULL;
END;
$$;

-- Recreate all four triggers so they are guaranteed to point at the fixed
-- function rather than depending on whatever was in the live database.
DROP TRIGGER IF EXISTS trg_reindex_plants        ON plants;
DROP TRIGGER IF EXISTS trg_reindex_plants_delete ON plants;
DROP TRIGGER IF EXISTS trg_reindex_names         ON plant_names;
DROP TRIGGER IF EXISTS trg_reindex_synonyms      ON plant_synonyms;

CREATE TRIGGER trg_reindex_plants AFTER INSERT OR UPDATE OF scientific_name, genus, family, is_deleted
    ON plants FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();
CREATE TRIGGER trg_reindex_plants_delete AFTER DELETE
    ON plants FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();
CREATE TRIGGER trg_reindex_names AFTER INSERT OR UPDATE OR DELETE
    ON plant_names FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();
CREATE TRIGGER trg_reindex_synonyms AFTER INSERT OR UPDATE OR DELETE
    ON plant_synonyms FOR EACH ROW EXECUTE FUNCTION fn_trigger_reindex_plant();

-- ---------------------------------------------------------------------------
-- Step 3: rebuild every search document from the corrected data.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    row RECORD;
BEGIN
    FOR row IN SELECT id FROM plants LOOP
        PERFORM fn_reindex_plant(row.id);
    END LOOP;
END;
$$;
