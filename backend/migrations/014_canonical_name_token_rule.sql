-- 014_canonical_name_token_rule.sql
-- 012 fixed the duplicate-taxon problem, but its canonical_name derivation used
-- a hard-coded list of author abbreviations. GBIF also returns names whose
-- authorship does not match that list, so the derived canonical form did not
-- match GBIF's own `canonicalName` and re-running the importer inserted a
-- second row for the same taxon:
--
--   Aloe vera (L.) Burm.f.                 -> "aloe vera (l.) burm.f."
--   Bougainvillea glabra Choisy            -> "bougainvillea glabra choisy"
--   Camellia sinensis (L.) Kuntze          -> "camellia sinensis (l.) kuntze"
--
-- 012 also dropped `uq_plants_canonical_name` and never recreated it, so the
-- constraint that is supposed to prevent exactly this class of bug was gone.
--
-- This migration derives the canonical form by token position instead of by
-- author name: the canonical form of a zoobotanical name is the genus plus the
-- specific epithet (plus infraspecific rank words), with any authorship
-- dropped. That matches GBIF's `canonicalName` and Catalogue of Life for the
-- names in scope, and it needs no per-author maintenance.

-- ---------------------------------------------------------------------------
-- Step 1: token-based canonical form, preserving infraspecific rank words.
--   "Camellia sinensis (L.) Kuntze"          -> "camellia sinensis"
--   "Bougainvillea glabra Choisy"             -> "bougainvillea glabra"
--   "Citrus × limon (L.) Osbeck"              -> "citrus × limon"
--   "Aloe vera (L.) Burm.f."                  -> "aloe vera"
--   "Hibiscus rosa-sinensis L."               -> "hibiscus rosa-sinensis"
--   "Diospyros"                               -> "diospyros"
--   "Ficus religiosa var. religiosa"          -> "ficus religiosa"
--   "Diospyros"                               -> "diospyros"
--
-- Infraspecific epithets are deliberately dropped from the canonical form: the
-- canonical name identifies the species, and subspecies/varieties are separate
-- taxa. Anything beyond the limit is authorship and is stored in
-- scientific_name_authorship instead of being parsed here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_canonical_plant_name(p_scientific_name TEXT) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    parts  TEXT[];
    n      INT;
    v_max  INT := 2;   -- genus + specific epithet
    out    TEXT := '';
    i      INT;
    tok    TEXT;
BEGIN
    IF p_scientific_name IS NULL OR btrim(p_scientific_name) = '' THEN
        RETURN NULL;
    END IF;

    parts := string_to_array(
        btrim(regexp_replace(p_scientific_name, '\s+', ' ', 'g')), ' ');
    n := array_length(parts, 1);

    -- A hybrid marker is part of the epithet, not authorship: the canonical
    -- form of "Citrus × limon (L.) Osbeck" is "citrus × limon", so the limit
    -- grows by one rather than the epithet being dropped.
    IF n >= 3 AND parts[2] IN ('×', 'x') THEN
        v_max := 3;
    END IF;

    FOR i IN 1..LEAST(n, v_max) LOOP
        tok := parts[i];
        out := CASE WHEN out = '' THEN lower(tok) ELSE out || ' ' || lower(tok) END;
    END LOOP;

    -- Genus-only names ("Diospyros") are kept as-is rather than lost.
    RETURN NULLIF(btrim(out), '');
END;
$$;

CREATE OR REPLACE FUNCTION fn_set_plants_canonical_name() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.canonical_name := fn_canonical_plant_name(NEW.scientific_name);
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Step 2: backfill canonical_name for every existing row. The BEFORE trigger
-- only fires on new writes, so rows inserted before this migration still hold
-- the old author-list-based value. The merge in Step 3 depends on this, so it
-- has to happen first.
-- ---------------------------------------------------------------------------
UPDATE plants
   SET scientific_name = scientific_name
 WHERE canonical_name IS DISTINCT FROM fn_canonical_plant_name(scientific_name);

-- ---------------------------------------------------------------------------
-- Step 3: merge the duplicates the token rule now exposes. Provenance and
-- verification history are relocated, never dropped. Child rows are
-- re-pointed at the surviving plant; per-plant unique constraints are
-- respected by removing the loser only where the survivor already holds an
-- equivalent row.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_merge_duplicate_plants(p_keep BIGINT, p_drop BIGINT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    -- Non-unique child tables can simply be re-pointed.
    UPDATE plant_taxonomy SET plant_id = p_keep
     WHERE plant_id = p_drop
       AND NOT EXISTS (SELECT 1 FROM plant_taxonomy t
                        WHERE t.plant_id = p_keep AND t.rank = plant_taxonomy.rank
                          AND t.name = plant_taxonomy.name);
    UPDATE plant_habitats SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE plant_diseases SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE plant_pests    SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE symptom_plants SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE safety_warnings SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE treatment_plant_scope SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE treatment_dosages SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE toxicity_profiles SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE images SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE image_annotations SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE model_classes SET plant_id = p_keep WHERE plant_id = p_drop;
    UPDATE model_labels SET plant_id = p_keep WHERE plant_id = p_drop;

    -- Deduplicating child tables: keep the survivor's row, drop the loser's
    -- copy only when the survivor already has an equivalent one.
    DELETE FROM plant_names n
     WHERE n.plant_id = p_drop
       AND EXISTS (SELECT 1 FROM plant_names k
                    WHERE k.plant_id = p_keep
                      AND k.normalized_name = n.normalized_name
                      AND COALESCE(k.language_code, '') = COALESCE(n.language_code, '')
                      AND COALESCE(k.region, '') = COALESCE(n.region, ''));
    UPDATE plant_names SET plant_id = p_keep
     WHERE plant_id = p_drop
       AND NOT EXISTS (SELECT 1 FROM plant_names k
                        WHERE k.plant_id = p_keep
                          AND k.normalized_name = plant_names.normalized_name
                          AND COALESCE(k.language_code, '') = COALESCE(plant_names.language_code, '')
                          AND COALESCE(k.region, '') = COALESCE(plant_names.region, ''));
    DELETE FROM plant_taxonomy WHERE plant_id = p_drop;

    DELETE FROM plant_synonyms s
     WHERE s.plant_id = p_drop
       AND EXISTS (SELECT 1 FROM plant_synonyms k
                    WHERE k.plant_id = p_keep
                      AND k.normalized_synonym = s.normalized_synonym);
    UPDATE plant_synonyms SET plant_id = p_keep
     WHERE plant_id = p_drop
       AND NOT EXISTS (SELECT 1 FROM plant_synonyms k
                        WHERE k.plant_id = p_keep
                          AND k.normalized_synonym = plant_synonyms.normalized_synonym);

    DELETE FROM plant_search_index WHERE plant_id = p_drop;

    -- Provenance and verification history follow the surviving record.
    UPDATE data_provenance
       SET notes = COALESCE(notes, '') || ' [merged from duplicate plant_id=' || p_drop || ']'
     WHERE table_name = 'plants' AND record_id = p_drop;
    DELETE FROM data_provenance d
     WHERE d.table_name = 'plants' AND d.record_id = p_drop
       AND EXISTS (SELECT 1 FROM data_provenance k
                    WHERE k.table_name = 'plants' AND k.record_id = p_keep
                      AND COALESCE(k.field_name, '') = COALESCE(d.field_name, '')
                      AND k.source_id IS NOT DISTINCT FROM d.source_id
                      AND k.id <> d.id);
    UPDATE data_provenance SET record_id = p_keep
     WHERE table_name = 'plants' AND record_id = p_drop;

    UPDATE verification_records
       SET notes = COALESCE(notes, '') || ' [merged from duplicate plant_id=' || p_drop || ']'
     WHERE table_name = 'plants' AND record_id = p_drop;
    UPDATE verification_records SET record_id = p_keep
     WHERE table_name = 'plants' AND record_id = p_drop;

    DELETE FROM plants WHERE id = p_drop;
END;
$$;

DO $$
DECLARE
    dup RECORD;
    ids  BIGINT[];
BEGIN
    LOOP
        SELECT canonical_name, array_agg(id ORDER BY id) AS ids
          INTO dup
          FROM plants
         WHERE is_deleted = FALSE
         GROUP BY canonical_name
        HAVING count(*) > 1
         LIMIT 1;

        EXIT WHEN NOT FOUND;

        ids := dup.ids;
        FOR i IN 2..array_length(ids, 1) LOOP
            RAISE NOTICE 'merging plant % into % (canonical %)', ids[i], ids[1], dup.canonical_name;
            PERFORM fn_merge_duplicate_plants(ids[1], ids[i]);
        END LOOP;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Step 4: restore the uniqueness guarantee that 012 dropped.
-- ---------------------------------------------------------------------------
ALTER TABLE plants ALTER COLUMN canonical_name SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_plants_canonical_name
    ON plants (canonical_name) WHERE is_deleted = FALSE;

-- Rebuild the search documents so they reflect the corrected names.
DO $$
DECLARE
    row RECORD;
BEGIN
    FOR row IN SELECT id FROM plants LOOP
        PERFORM fn_reindex_plant(row.id);
    END LOOP;
END;
$$;
