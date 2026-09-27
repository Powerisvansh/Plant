-- 011_contract_views.sql
-- Named read models required by the PlantDoctor data contract.
-- The normalised tables remain the source of truth; these views expose the
-- contract names (plant_images, dataset_records) without duplicating storage.

CREATE OR REPLACE VIEW plant_images AS
SELECT i.id                AS image_id,
       i.file_path,
       i.relative_path,
       i.dataset_id,
       d.name              AS dataset_name,
       d.version           AS dataset_version,
       i.plant_id,
       pl.scientific_name  AS plant_scientific_name,
       COALESCE(pli.plant_id, i.plant_id) AS subject_plant_id,
       COALESCE(pli.part, i.part)         AS plant_part,
       COALESCE(pli.role, 'SUBJECT')      AS image_role,
       i.condition,
       i.condition_class,
       i.symptom_id,
       i.disease_id,
       i.pest_id,
       i.nutrient_deficiency_id,
       i.environmental_stress_id,
       i.original_label,
       i.split,
       i.original_url,
       i.collection_date,
       i.image_width,
       i.image_height,
       i.file_bytes,
       i.mime_type,
       i.file_extension,
       i.quality_score,
       i.annotation_status,
       i.verified,
       vs.name             AS verification_source_name,
       s.name              AS source_name,
       s.url               AS source_url,
       i.license,
       i.copyright_status,
       i.copyright_holder,
       i.attribution_text,
       i.is_usable_for_training,
       i.is_duplicate_of,
       i.created_at
  FROM images i
  LEFT JOIN datasets d        ON d.id = i.dataset_id
  LEFT JOIN plant_image_links pli ON pli.image_id = i.id
  LEFT JOIN plants pl         ON pl.id = COALESCE(pli.plant_id, i.plant_id)
  LEFT JOIN sources s         ON s.id = i.source_id
  LEFT JOIN sources vs        ON vs.id = i.verification_source_id;

CREATE OR REPLACE VIEW dataset_records AS
SELECT ds.id                       AS dataset_id,
       ds.name,
       ds.version,
       ds.description,
       ds.provider,
       ds.source_url,
       s.name                      AS source_name,
       s.organization              AS source_organization,
       s.license                   AS source_license,
       ds.license,
       ds.license_url,
       ds.terms_url,
       ds.attribution_required,
       ds.attribution_text,
       ds.redistribution_allowed,
       ds.commercial_use_allowed,
       ds.license_verified,
       ds.license_verified_at,
       ds.license_verified_by,
       ds.image_count,
       ds.total_bytes,
       ds.class_count,
       ds.obtained_at,
       ds.local_path,
       ds.status,
       ds.is_active,
       ds.parent_dataset_id,
       pd.name                     AS parent_dataset_name,
       b.batch_key                 AS import_batch_key,
       b.status                    AS import_batch_status,
       b.script_name,
       b.dry_run,
       b.files_seen,
       b.files_imported,
       b.files_skipped,
       b.files_failed,
       b.started_at                AS import_started_at,
       b.finished_at               AS import_finished_at,
       (SELECT count(*) FROM data_provenance dp
         WHERE dp.table_name = 'datasets' AND dp.record_id = ds.id) AS provenance_record_count,
       ds.created_at,
       ds.updated_at
  FROM datasets ds
  LEFT JOIN sources s  ON s.id = ds.source_id
  LEFT JOIN datasets pd ON pd.id = ds.parent_dataset_id
  LEFT JOIN import_batches b ON b.id = ds.import_batch_id;
