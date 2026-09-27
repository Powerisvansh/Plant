-- 010_views.sql
-- Read models used by the API and the Flutter app.

CREATE OR REPLACE VIEW v_plant_overview AS
SELECT p.id                                   AS plant_id,
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

CREATE OR REPLACE VIEW v_plant_conditions AS
SELECT 'DISEASE'::condition_class AS class,
       pd.id                       AS link_id,
       pd.plant_id,
       d.id                        AS condition_ref,
       d.code                      AS condition_code,
       d.name                      AS condition_name,
       d.pathogen_scientific_name  AS scientific_detail,
       d.verification_status,
       d.last_verified,
       pd.susceptibility,
       NULL::severity_level        AS severity
  FROM plant_diseases pd JOIN diseases d ON d.id = pd.disease_id
UNION ALL
SELECT 'PEST', pp.id, pp.plant_id, p.id, p.code, p.name, p.scientific_name,
       p.verification_status, p.last_verified, NULL, pp.damage_level
  FROM plant_pests pp JOIN pests p ON p.id = pp.pest_id
UNION ALL
SELECT 'NUTRIENT_DEFICIENCY', NULL, p.id, nd.id, nd.code, nd.deficiency_name, nd.element_symbol,
       nd.verification_status, nd.last_verified, NULL, NULL
  FROM plants p CROSS JOIN nutrient_deficiencies nd
 WHERE nd.verification_status IN ('VERIFIED', 'PARTIALLY_VERIFIED')
   AND nd.is_mobile_in_plant IS NOT NULL
   AND p.family IS NOT NULL;

CREATE OR REPLACE VIEW v_plant_symptom_index AS
SELECT DISTINCT sp.plant_id, s.id AS symptom_id, s.code, s.name, s.category,
       COALESCE(spr.part, 'UNKNOWN'::plant_part) AS part, s.verification_status
  FROM symptom_plants sp
  JOIN symptoms s ON s.id = sp.symptom_id
  LEFT JOIN symptom_parts spr ON spr.symptom_id = s.id
UNION
SELECT DISTINCT pd.plant_id, ds.symptom_id, s.code, s.name, s.category,
       ds.part, s.verification_status
  FROM disease_symptoms ds
  JOIN plant_diseases pd ON pd.disease_id = ds.disease_id
  JOIN symptoms s ON s.id = ds.symptom_id
UNION
SELECT DISTINCT pp.plant_id, ps.symptom_id, s.code, s.name, s.category,
       ps.part, s.verification_status
  FROM pest_symptoms ps
  JOIN plant_pests pp ON pp.pest_id = ps.pest_id
  JOIN symptoms s ON s.id = ps.symptom_id;

CREATE OR REPLACE VIEW v_condition_detail AS
SELECT c.condition_class,
       c.condition_ref,
       c.title,
       c.subtitle,
       c.summary,
       c.source_name,
       c.source_url,
       c.verification_status,
       c.last_verified
  FROM (
    SELECT 'DISEASE'::condition_class AS condition_class, d.id AS condition_ref,
           d.name AS title, d.pathogen_scientific_name AS subtitle,
           d.description AS summary, s.name AS source_name, s.url AS source_url,
           d.verification_status, d.last_verified
      FROM diseases d LEFT JOIN sources s ON s.id = d.source_id
    UNION ALL
    SELECT 'PEST', p.id, p.name, p.scientific_name, p.description, s.name, s.url,
           p.verification_status, p.last_verified
      FROM pests p LEFT JOIN sources s ON s.id = p.source_id
    UNION ALL
    SELECT 'NUTRIENT_DEFICIENCY', n.id, n.deficiency_name, n.element_symbol,
           n.description, s.name, s.url, n.verification_status, n.last_verified
      FROM nutrient_deficiencies n LEFT JOIN sources s ON s.id = n.source_id
    UNION ALL
    SELECT 'ENVIRONMENTAL_STRESS', e.id, e.name, NULL,
           e.description, s.name, s.url, e.verification_status, e.last_verified
      FROM environmental_stresses e LEFT JOIN sources s ON s.id = e.source_id
  ) c;

-- Science fair metrics. Only rows with a real measurement are ever exposed;
-- NULL means "Not measured yet." and must be rendered as such by the client.
CREATE OR REPLACE VIEW v_science_fair_metrics AS
WITH kb AS (
    SELECT
      (SELECT count(*) FROM plants WHERE is_deleted = FALSE)                       AS plant_count,
      (SELECT count(*) FROM diseases)                                              AS disease_count,
      (SELECT count(*) FROM pests)                                                 AS pest_count,
      (SELECT count(*) FROM symptoms)                                              AS symptom_count,
      (SELECT count(*) FROM nutrient_deficiencies)                                 AS nutrient_count,
      (SELECT count(*) FROM environmental_stresses)                               AS stress_count,
      (SELECT count(*) FROM images)                                                AS image_count,
      (SELECT count(*) FROM images WHERE is_usable_for_training)                   AS training_image_count,
      (SELECT count(*) FROM images WHERE split = 'TEST')                           AS test_image_count,
      (SELECT count(*) FROM images WHERE split = 'VALIDATION')                     AS validation_image_count,
      (SELECT count(*) FROM sources WHERE approval_status = 'APPROVED')            AS approved_source_count,
      (SELECT count(*) FROM sources WHERE is_citable_in_app)                       AS citable_source_count,
      (SELECT count(*) FROM source_documents)                                      AS source_document_count,
      (SELECT count(*) FROM datasets WHERE license_verified)                       AS license_verified_dataset_count,
      (SELECT count(*) FROM toxicity_profiles)                                     AS toxicity_profile_count,
      (SELECT count(*) FROM v_subject_safety_summary WHERE NOT is_unknown)        AS plants_with_safety_data,
      (SELECT count(*) FROM v_treatment_dosage_verified)                           AS verified_dosage_count,
      (SELECT count(*) FROM treatment_products)                                   AS product_count,
      (SELECT count(*) FROM active_ingredients)                                   AS active_ingredient_count,
      (SELECT count(*) FROM data_provenance)                                       AS provenance_record_count,
      (SELECT count(*) FROM verification_records)                                  AS verification_record_count,
      (SELECT count(*) FROM record_conflicts WHERE status = 'OPEN')                AS open_conflict_count
)
SELECT kb.*,
       (SELECT count(*) FROM model_versions WHERE is_deployed)                     AS deployed_model_count,
       (SELECT max(version) FROM model_versions WHERE is_deployed)                 AS deployed_model_version,
       (SELECT count(*) FROM model_evaluations)                                    AS evaluation_count
  FROM kb;

CREATE OR REPLACE VIEW v_data_quality_summary AS
SELECT r.run_key,
       r.scope,
       r.started_at,
       r.finished_at,
       r.total_checked,
       r.passed,
       r.warnings,
       r.failed,
       r.status,
       (SELECT count(*) FROM data_quality_findings f WHERE f.report_id = r.id) AS finding_count,
       (SELECT count(*) FROM data_quality_findings f
         WHERE f.report_id = r.id AND f.severity IN ('SEVERE','LIFE_THREATENING')) AS critical_finding_count
  FROM data_quality_reports r;

CREATE OR REPLACE VIEW v_missing_knowledge AS
SELECT 'PLANT_MISSING_NAME'        AS check_key, p.id AS record_id, p.scientific_name AS detail
  FROM plants p
 WHERE p.is_deleted = FALSE
   AND NOT EXISTS (SELECT 1 FROM plant_names n WHERE n.plant_id = p.id)
UNION ALL
SELECT 'PLANT_MISSING_TAXONOMY', p.id, p.scientific_name
  FROM plants p
 WHERE p.is_deleted = FALSE AND (p.family IS NULL OR p.order_name IS NULL)
UNION ALL
SELECT 'DISEASE_WITHOUT_SYMPTOMS', d.id, d.name
  FROM diseases d
 WHERE NOT EXISTS (SELECT 1 FROM disease_symptoms ds WHERE ds.disease_id = d.id)
UNION ALL
SELECT 'PEST_WITHOUT_SYMPTOMS', p.id, p.name
  FROM pests p
 WHERE NOT EXISTS (SELECT 1 FROM pest_symptoms ps WHERE ps.pest_id = p.id)
UNION ALL
SELECT 'DISEASE_WITHOUT_PLANT_LINKS', d.id, d.name
  FROM diseases d
 WHERE NOT EXISTS (SELECT 1 FROM plant_diseases pd WHERE pd.disease_id = d.id)
UNION ALL
SELECT 'PEST_WITHOUT_PLANT_LINKS', p.id, p.name
  FROM pests p
 WHERE NOT EXISTS (SELECT 1 FROM plant_pests pp WHERE pp.pest_id = p.id)
UNION ALL
SELECT 'PLANT_WITHOUT_SAFETY_DATA', s.plant_id, s.scientific_name
  FROM v_subject_safety_summary s
 WHERE s.is_unknown
UNION ALL
SELECT 'SOURCE_MISSING', t.id, t.scientific_name
  FROM plants t
 WHERE t.is_deleted = FALSE AND t.taxonomic_source_id IS NULL
UNION ALL
SELECT 'IMAGE_FILE_MISSING', i.id, i.file_path
  FROM images i
 WHERE i.file_path !~ '^/' OR i.file_path = ''
UNION ALL
SELECT 'RECORD_WITH_OPEN_CONFLICT', c.id, c.table_name || '#' || c.record_id || '.' || c.field_name
  FROM record_conflicts c
 WHERE c.status = 'OPEN';
