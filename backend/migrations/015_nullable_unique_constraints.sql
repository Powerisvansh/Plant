-- 015_nullable_unique_constraints.sql
-- Several per-plant unique constraints included nullable columns. In SQL, NULL
-- never equals NULL for the purpose of a unique index, so those constraints
-- silently admitted unlimited duplicates instead of preventing them. The
-- importer relies on ON CONFLICT DO UPDATE against exactly these constraints:
--
--   plant_habitats (plant_id, habitat_type, biome, region)
--       biome is never populated by the GBIF distribution import, so every
--       re-run inserted another full set of rows. Observed growth: 1564 -> 4118.
--   plant_names (plant_id, name, language_code, region)
--       language_code and region are frequently NULL for vernacular names.
--
-- PostgreSQL 15+ supports UNIQUE NULLS NOT DISTINCT, which makes NULLs compare
-- equal for uniqueness. That is the correct semantics here: two rows with the
-- same plant, name and NULL language genuinely are the same fact recorded
-- twice. Version 16 is in use, so no compatibility shim is needed.
--
-- Note on plant_habitats: the natural key must include `country`, not just
-- `region`. A GBIF distribution row for "Solanum lycopersicum / AD" and one for
-- "... / FR" differ only in country, and both carry a NULL region. Deduplicating
-- on (plant_id, habitat_type, biome, region) alone collapses all of a plant's
-- countries into one row, which is data loss rather than deduplication.

-- ---------------------------------------------------------------------------
-- Step 1: collapse only genuine duplicates.
-- ---------------------------------------------------------------------------
DELETE FROM plant_habitats h
 WHERE h.id > (
       SELECT min(h2.id) FROM plant_habitats h2
        WHERE h2.plant_id = h.plant_id
          AND h2.habitat_type = h.habitat_type
          AND COALESCE(h2.biome, '') = COALESCE(h.biome, '')
          AND COALESCE(h2.region, '') = COALESCE(h.region, '')
          AND COALESCE(h2.country, '') = COALESCE(h.country, '')
    );

DELETE FROM plant_names n
 WHERE n.id > (
       SELECT min(n2.id) FROM plant_names n2
        WHERE n2.plant_id = n.plant_id
          AND n2.name = n.name
          AND COALESCE(n2.language_code, '') = COALESCE(n.language_code, '')
          AND COALESCE(n2.region, '') = COALESCE(n.region, '')
    );

DELETE FROM plant_synonyms s
 WHERE s.id > (
       SELECT min(s2.id) FROM plant_synonyms s2
        WHERE s2.plant_id = s.plant_id
          AND s2.synonym = s.synonym
    );

-- ---------------------------------------------------------------------------
-- Step 2: replace the nullable-column constraints with NULLS NOT DISTINCT ones.
-- ---------------------------------------------------------------------------
ALTER TABLE plant_habitats
    DROP CONSTRAINT IF EXISTS plant_habitats_plant_id_habitat_type_biome_region_key;
ALTER TABLE plant_habitats
    DROP CONSTRAINT IF EXISTS plant_habitats_plant_id_habitat_type_biome_region_country_key;
ALTER TABLE plant_habitats
    ADD CONSTRAINT plant_habitats_plant_id_habitat_type_biome_region_country_key
    UNIQUE NULLS NOT DISTINCT (plant_id, habitat_type, biome, region, country);

ALTER TABLE plant_names
    DROP CONSTRAINT IF EXISTS plant_names_plant_id_name_language_code_region_key;
ALTER TABLE plant_names
    ADD CONSTRAINT plant_names_plant_id_name_language_code_region_key
    UNIQUE NULLS NOT DISTINCT (plant_id, name, language_code, region);

CREATE UNIQUE INDEX IF NOT EXISTS uq_plant_synonyms_plant_synonym
    ON plant_synonyms (plant_id, synonym);
