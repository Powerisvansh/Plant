-- 016_expose_canonical_name_in_views.sql
-- The API reads v_plant_overview, which exposed the primary key as `plant_id`
-- and never selected canonical_name. Clients therefore had no authorship-free
-- name to match on, and `canonical_name` -- the column the uniqueness rule in
-- 014 is built on -- was invisible outside the database.
--
-- This redefines the view exactly as 010_views.sql created it, with one added
-- column. Everything else is byte-for-byte the original so the read model does
-- not drift.
--
-- CREATE OR REPLACE VIEW cannot insert a column in the middle of the select
-- list ("cannot change name of view column"), so the view is dropped and
-- recreated. Nothing depends on it being replaced in place.

DROP VIEW IF EXISTS v_plant_overview;

CREATE OR REPLACE VIEW v_plant_overview AS
SELECT p.id                                   AS plant_id,
       p.canonical_name,
       p.scientific_name,
       p.scientific_name_authorship,
       p.genus,
       p.species,
       p.family,
       p.order_name,
       p.taxonomic_status,
       p.is_accepted,
       p.description,
       p.identification_summary,
       p.growth_habit,
       p.edible_status,
       p.known_uses,
       p.ornamental_use,
       p.agricultural_importance,
       p.distribution_summary,
       p.conservation_status,
       p.verification_status,
       p.last_verified,
       p.external_taxon_source,
       p.external_taxon_key,
       s.name                                 AS taxonomic_source_name,
       s.url                                  AS taxonomic_source_url,
       COALESCE(n.preferred_name, n.any_name) AS common_name,
       (SELECT count(*) FROM images i
         WHERE i.plant_id = p.id AND i.is_usable_for_training)  AS usable_image_count,
       (SELECT count(*) FROM plant_diseases pd WHERE pd.plant_id = p.id) AS disease_count,
       (SELECT count(*) FROM plant_pests pp    WHERE pp.plant_id = p.id) AS pest_count,
       (SELECT count(*) FROM safety_warnings sw WHERE sw.plant_id = p.id) AS warning_count
  FROM plants p
  LEFT JOIN sources s ON s.id = p.taxonomic_source_id
  LEFT JOIN LATERAL (
        SELECT min(n2.name) FILTER (WHERE n2.is_preferred) AS preferred_name,
               min(n2.name) AS any_name
          FROM plant_names n2 WHERE n2.plant_id = p.id
  ) n ON TRUE
 WHERE p.is_deleted = FALSE;
