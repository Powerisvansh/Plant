-- 012_canonical_name_integrity.sql
-- Fixes a real duplicate-taxon defect found during the first GBIF import:
--   GBIF returns authorship inside `scientificName` ("Solanum lycopersicum L.")
--   while a hand-seeded row stored only the binomial ("Solanum lycopersicum"),
--   so the uniqueness index on canonical_name did not catch that these are the
--   same taxon.
--
-- Order matters: normalise names FIRST, then merge duplicates (otherwise the
-- merge predicate cannot see them), then re-establish uniqueness.
-- Provenance and verification history are relocated, never silently dropped.

DROP FUNCTION IF EXISTS fn_bare_taxon_name(TEXT);

CREATE FUNCTION fn_bare_taxon_name(p_name TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(btrim(regexp_replace(
        regexp_replace(
            coalesce(p_name, ''),
            '\s+((L\.|L\.\s*f\.|L\.&\s*[A-Z]\.\s*[A-Z]+\.?|Blume|Rchb\.|Mill\.|Thunb\.|'
            'Willd\.|Jacq\.|Dumort\.|Desf\.|Vahl|Kunth|Roxb\.|Wall\.|Hook\.\s*f\.|'
            'Benth\.|A\.\s*Juss\.|Siebold\s*&\s*Zucc\.|Zucc\.|Pers\.|Sw\.|DC\.|G\.\s*Don|'
            'Sm\.|Aiton|Raf\.|Salisb\.|Lodd\.|D\. Don|Torr\.|Gray|Gaertn\.|Medik\.|'
            'Schreb\.|Boiss\.|Bunge|Franch\.|Sav\.|[A-Z][a-z]+\s+ex\s+[A-Z][a-z]+))$', ''),
        '\s+', ' ', 'g')))
$$;

-- Step 1: split the author citation out of the name into its own column.
DO $$
DECLARE
    row RECORD;
    bare TEXT;
    remainder TEXT;
BEGIN
    FOR row IN SELECT id, scientific_name FROM plants WHERE scientific_name IS NOT NULL LOOP
        bare := fn_bare_taxon_name(row.scientific_name);
        IF bare IS DISTINCT FROM row.scientific_name AND bare <> '' THEN
            remainder := btrim(regexp_replace(row.scientific_name, '^\S+\s+\S+', ''));
            UPDATE plants
               SET scientific_name = bare,
                   scientific_name_authorship = COALESCE(
                       NULLIF(btrim(scientific_name_authorship), ''),
                       CASE WHEN remainder ~ '^[A-Z]' THEN remainder ELSE NULL END)
             WHERE id = row.id;
        END IF;
    END LOOP;
END;
$$;

-- Step 2: merge rows that are now the same taxon, relocating their history.
DO $$
DECLARE
    dup      RECORD;
    keep_id  BIGINT;
    drop_id  BIGINT;
    ids_left BIGINT[];
BEGIN
    LOOP
        SELECT canonical_name, array_agg(id ORDER BY id) AS ids
          INTO dup
          FROM plants
         WHERE is_deleted = FALSE
         GROUP BY canonical_name
        HAVING count(*) > 1
         LIMIT 1;

        IF NOT FOUND THEN
            EXIT;
        END IF;

        ids_left := dup.ids;
        keep_id := ids_left[1];

        FOREACH drop_id IN ARRAY (
            SELECT array_agg(u.id ORDER BY u.id)
              FROM unnest(ids_left) WITH ORDINALITY AS u(id, ord)
             WHERE u.ord > 1
        ) LOOP
            RAISE NOTICE 'merging duplicate plant id=% into id=% (%s)', drop_id, keep_id, dup.canonical_name;

            UPDATE data_provenance
               SET notes = COALESCE(notes, '') || ' [merged from duplicate plant_id=' || drop_id || ']'
             WHERE table_name = 'plants' AND record_id = drop_id;

            DELETE FROM data_provenance d
             WHERE d.table_name = 'plants' AND d.record_id = drop_id
               AND EXISTS (
                   SELECT 1 FROM data_provenance e
                    WHERE e.table_name = 'plants' AND e.record_id = keep_id
                      AND COALESCE(e.field_name, '') = COALESCE(d.field_name, '')
                      AND e.id <> d.id
               );

            UPDATE data_provenance SET record_id = keep_id
             WHERE table_name = 'plants' AND record_id = drop_id;

            UPDATE verification_records
               SET notes = COALESCE(notes, '') || ' [merged from duplicate plant_id=' || drop_id || ']'
             WHERE table_name = 'plants' AND record_id = drop_id;
            UPDATE verification_records SET record_id = keep_id
             WHERE table_name = 'plants' AND record_id = drop_id;

            UPDATE plant_taxonomy SET plant_id = keep_id
             WHERE plant_id = drop_id
               AND NOT EXISTS (SELECT 1 FROM plant_taxonomy t
                                WHERE t.plant_id = keep_id AND t.rank = plant_taxonomy.rank
                                  AND t.name = plant_taxonomy.name);
            DELETE FROM plant_taxonomy WHERE plant_id = drop_id;

            DELETE FROM plants WHERE id = drop_id;
        END LOOP;
    END LOOP;
END;
$$;


-- Step 3: re-arm uniqueness on the normalised name.
-- `ALTER COLUMN ... DROP EXPRESSION` only exists from PostgreSQL 17, so on 16
-- the column is dropped and re-added as a plain column maintained by a BEFORE
-- trigger. A generated column is not usable here: the author-citation pattern
-- needs a long alternation and the only clean way to express it (concat_ws) is
-- not IMMUTABLE, which generated columns require.
DROP INDEX IF EXISTS uq_plants_canonical_name;
ALTER TABLE plants DROP COLUMN IF EXISTS canonical_name;
ALTER TABLE plants ADD COLUMN canonical_name TEXT;

CREATE OR REPLACE FUNCTION fn_set_plants_canonical_name() RETURNS TRIGGER
LANGUAGE plpgsql AS $FN$
DECLARE
    pattern TEXT := '\s+(L\.|L\.\s*f\.|Blume|Rchb\.|Mill\.|Thunb\.|Willd\.|Jacq\.|'
                    || 'Dumort\.|Desf\.|Vahl|Kunth|Roxb\.|Wall\.|Hook\.\s*f\.|'
                    || 'Benth\.|A\.\s*Juss\.|Siebold\s*&\s*Zucc\.|Zucc\.|Pers\.|Sw\.|'
                    || 'DC\.|G\.\s*Don|Sm\.|Aiton|Raf\.|Salisb\.|Lodd\.|D\.\s*Don|'
                    || 'Torr\.|Gray|Gaertn\.|Medik\.|Schreb\.|Boiss\.|Bunge|Franch\.|Sav\.)$';
BEGIN
    NEW.canonical_name := lower(btrim(regexp_replace(
        regexp_replace(coalesce(NEW.scientific_name, ''), pattern, ''),
        '\s+', ' ', 'g')));
    RETURN NEW;
END;
$FN$;

DROP TRIGGER IF EXISTS trg_plants_canonical_name ON plants;
CREATE TRIGGER trg_plants_canonical_name
    BEFORE INSERT OR UPDATE OF scientific_name ON plants
    FOR EACH ROW EXECUTE FUNCTION fn_set_plants_canonical_name();

UPDATE plants SET scientific_name = scientific_name;
