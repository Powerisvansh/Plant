-- 008_images_datasets_models.sql
-- Image metadata, dataset provenance, annotations, model registry and
-- real-measurement-only science-fair metrics.

CREATE TABLE import_batches (
    id              BIGSERIAL PRIMARY KEY,
    batch_key       TEXT NOT NULL UNIQUE,
    script_name     TEXT NOT NULL,
    script_version  TEXT,
    dataset_id      BIGINT,
    dry_run         BOOLEAN NOT NULL DEFAULT FALSE,
    status          TEXT NOT NULL DEFAULT 'RUNNING',
    operator        TEXT NOT NULL DEFAULT current_user,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    files_seen      INTEGER NOT NULL DEFAULT 0,
    files_imported  INTEGER NOT NULL DEFAULT 0,
    files_skipped   INTEGER NOT NULL DEFAULT 0,
    files_failed    INTEGER NOT NULL DEFAULT 0,
    bytes_seen      BIGINT NOT NULL DEFAULT 0,
    error_log_path  TEXT,
    notes           TEXT,
    CONSTRAINT import_batch_status_known CHECK (
        status IN ('RUNNING','COMPLETED','COMPLETED_WITH_ERRORS','FAILED','ABORTED')
    )
);

CREATE TABLE datasets (
    id                      BIGSERIAL PRIMARY KEY,
    name                    TEXT NOT NULL,
    version                 TEXT NOT NULL,
    description             TEXT,
    provider                TEXT,
    source_id               BIGINT REFERENCES sources(id) ON DELETE RESTRICT,
    source_url              TEXT,
    license                 license_type NOT NULL DEFAULT 'UNKNOWN',
    license_url             TEXT,
    terms_url               TEXT,
    attribution_required    BOOLEAN NOT NULL DEFAULT FALSE,
    attribution_text        TEXT,
    redistribution_allowed  BOOLEAN,
    commercial_use_allowed  BOOLEAN,
    requires_attribution    BOOLEAN NOT NULL DEFAULT FALSE,
    image_count             INTEGER NOT NULL DEFAULT 0,
    total_bytes             BIGINT NOT NULL DEFAULT 0,
    class_count             INTEGER,
    obtained_at             DATE,
    local_path              TEXT,
    parent_dataset_id       BIGINT REFERENCES datasets(id) ON DELETE SET NULL,
    status                  TEXT NOT NULL DEFAULT 'REGISTERED',
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    import_batch_id         BIGINT REFERENCES import_batches(id) ON DELETE SET NULL,
    license_verified        BOOLEAN NOT NULL DEFAULT FALSE,
    license_verified_at     TIMESTAMPTZ,
    license_verified_by     TEXT,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name, version),
    CONSTRAINT dataset_status_known CHECK (
        status IN ('REGISTERED','PENDING_LICENSE_REVIEW','APPROVED','REJECTED','PROCESSING','RETIRED')
    )
);

CREATE INDEX idx_datasets_license ON datasets (license);
CREATE INDEX idx_datasets_status ON datasets (status);
CREATE TRIGGER trg_datasets_touch BEFORE UPDATE ON datasets
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

ALTER TABLE import_batches
    ADD CONSTRAINT import_batches_dataset_fk
    FOREIGN KEY (dataset_id) REFERENCES datasets(id) ON DELETE SET NULL;

CREATE TABLE images (
    id                  BIGSERIAL PRIMARY KEY,
    dataset_id          BIGINT REFERENCES datasets(id) ON DELETE SET NULL,
    file_path           TEXT NOT NULL,
    relative_path       TEXT,
    original_filename   TEXT,
    file_sha256         TEXT NOT NULL CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
    phash               TEXT,
    mime_type           TEXT,
    file_extension      TEXT,
    file_bytes          BIGINT CHECK (file_bytes IS NULL OR file_bytes > 0),
    image_width         INTEGER CHECK (image_width IS NULL OR image_width > 0),
    image_height        INTEGER CHECK (image_height IS NULL OR image_height > 0),
    plant_id            BIGINT REFERENCES plants(id) ON DELETE SET NULL,
    part                plant_part,
    condition           image_condition NOT NULL DEFAULT 'UNKNOWN',
    condition_class     condition_class NOT NULL DEFAULT 'UNKNOWN',
    symptom_id          BIGINT REFERENCES symptoms(id) ON DELETE SET NULL,
    disease_id          BIGINT REFERENCES diseases(id) ON DELETE SET NULL,
    pest_id             BIGINT REFERENCES pests(id) ON DELETE SET NULL,
    nutrient_deficiency_id BIGINT REFERENCES nutrient_deficiencies(id) ON DELETE SET NULL,
    environmental_stress_id BIGINT REFERENCES environmental_stresses(id) ON DELETE SET NULL,
    original_label      TEXT,
    split               dataset_split NOT NULL DEFAULT 'UNASSIGNED',
    original_url        TEXT,
    collection_date     DATE,
    capture_device      TEXT,
    license             license_type NOT NULL DEFAULT 'UNKNOWN',
    copyright_status    copyright_status NOT NULL DEFAULT 'UNKNOWN',
    copyright_holder    TEXT,
    attribution_text    TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    quality_score       NUMERIC(5,4) CHECK (quality_score IS NULL OR (quality_score >= 0 AND quality_score <= 1)),
    blur_score          NUMERIC(10,4),
    mean_brightness     NUMERIC(5,4),
    annotation_status   annotation_status NOT NULL DEFAULT 'UNANNOTATED',
    verified            BOOLEAN NOT NULL DEFAULT FALSE,
    verification_source_id BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    is_duplicate_of     BIGINT REFERENCES images(id) ON DELETE SET NULL,
    is_derivative_of    BIGINT REFERENCES images(id) ON DELETE SET NULL,
    is_usable_for_training BOOLEAN NOT NULL DEFAULT FALSE,
    unusable_reason     TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_images_sha256 ON images (file_sha256);
CREATE INDEX idx_images_dataset ON images (dataset_id);
CREATE INDEX idx_images_plant ON images (plant_id) WHERE plant_id IS NOT NULL;
CREATE INDEX idx_images_disease ON images (disease_id) WHERE disease_id IS NOT NULL;
CREATE INDEX idx_images_pest ON images (pest_id) WHERE pest_id IS NOT NULL;
CREATE INDEX idx_images_symptom ON images (symptom_id) WHERE symptom_id IS NOT NULL;
CREATE INDEX idx_images_split ON images (split, is_usable_for_training);
CREATE INDEX idx_images_condition ON images (condition_class, condition);
CREATE INDEX idx_images_phash ON images (phash) WHERE phash IS NOT NULL;
CREATE INDEX idx_images_license ON images (license, copyright_status);
CREATE INDEX idx_images_path ON images (file_path);
CREATE TRIGGER trg_images_touch BEFORE UPDATE ON images
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE disease_images (
    id              BIGSERIAL PRIMARY KEY,
    image_id        BIGINT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    disease_id      BIGINT NOT NULL REFERENCES diseases(id) ON DELETE CASCADE,
    part            plant_part,
    role            TEXT NOT NULL DEFAULT 'SYMPTOM',
    is_representative BOOLEAN NOT NULL DEFAULT FALSE,
    caption         TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (image_id, disease_id),
    CONSTRAINT disease_image_role_known CHECK (
        role IN ('SYMPTOM','SIGN','PATHOGEN','DAMAGE','COMPARISON','REFERENCE')
    )
);

CREATE INDEX idx_disease_images_disease ON disease_images (disease_id);

CREATE TABLE pest_images (
    id              BIGSERIAL PRIMARY KEY,
    image_id        BIGINT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    pest_id         BIGINT NOT NULL REFERENCES pests(id) ON DELETE CASCADE,
    part            plant_part,
    role            TEXT NOT NULL DEFAULT 'DAMAGE',
    life_stage      TEXT,
    is_representative BOOLEAN NOT NULL DEFAULT FALSE,
    caption         TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (image_id, pest_id),
    CONSTRAINT pest_image_role_known CHECK (
        role IN ('DAMAGE','SPECIMEN','EGG','LARVA','PUPA','ADULT','NEST','COMPARISON','REFERENCE')
    )
);

CREATE INDEX idx_pest_images_pest ON pest_images (pest_id);

CREATE TABLE symptom_images (
    id              BIGSERIAL PRIMARY KEY,
    image_id        BIGINT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    symptom_id      BIGINT NOT NULL REFERENCES symptoms(id) ON DELETE CASCADE,
    part            plant_part,
    is_representative BOOLEAN NOT NULL DEFAULT FALSE,
    caption         TEXT,
    source_id       BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (image_id, symptom_id)
);

CREATE INDEX idx_symptom_images_symptom ON symptom_images (symptom_id);

CREATE TABLE plant_image_links (
    image_id        BIGINT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    plant_id        BIGINT NOT NULL REFERENCES plants(id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'SUBJECT',
    part            plant_part,
    condition       image_condition NOT NULL DEFAULT 'HEALTHY',
    is_representative BOOLEAN NOT NULL DEFAULT FALSE,
    caption         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (image_id, plant_id),
    CONSTRAINT plant_image_role_known CHECK (
        role IN ('SUBJECT','WHOLE_PLANT','HEALTHY_REFERENCE','PART_DETAIL','COMPARISON')
    )
);

CREATE INDEX idx_plant_image_links_plant ON plant_image_links (plant_id);

CREATE TABLE image_annotations (
    id                  BIGSERIAL PRIMARY KEY,
    image_id            BIGINT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    annotator           TEXT,
    annotation_method   TEXT NOT NULL DEFAULT 'MANUAL',
    plant_id            BIGINT REFERENCES plants(id) ON DELETE SET NULL,
    part                plant_part,
    condition_class     condition_class,
    symptom_id          BIGINT REFERENCES symptoms(id) ON DELETE SET NULL,
    disease_id          BIGINT REFERENCES diseases(id) ON DELETE SET NULL,
    pest_id             BIGINT REFERENCES pests(id) ON DELETE SET NULL,
    label_value         TEXT,
    bbox_x              NUMERIC(7,4) CHECK (bbox_x IS NULL OR (bbox_x >= 0 AND bbox_x <= 1)),
    bbox_y              NUMERIC(7,4) CHECK (bbox_y IS NULL OR (bbox_y >= 0 AND bbox_y <= 1)),
    bbox_w              NUMERIC(7,4) CHECK (bbox_w IS NULL OR (bbox_w >= 0 AND bbox_w <= 1)),
    bbox_h              NUMERIC(7,4) CHECK (bbox_h IS NULL OR (bbox_h >= 0 AND bbox_h <= 1)),
    polygon             JSONB,
    is_agreed           BOOLEAN,
    annotator_notes     TEXT,
    source_id           BIGINT REFERENCES sources(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT image_annot_method_known CHECK (
        annotation_method IN ('MANUAL','EXPERT_REVIEW','IMPORT_LABEL','MODEL_INFERRED','HEURISTIC')
    ),
    CONSTRAINT image_annot_bbox_complete CHECK (
        (bbox_x IS NULL AND bbox_y IS NULL AND bbox_w IS NULL AND bbox_h IS NULL)
        OR (bbox_x IS NOT NULL AND bbox_y IS NOT NULL AND bbox_w IS NOT NULL AND bbox_h IS NOT NULL)
    )
);

CREATE INDEX idx_image_annotations_image ON image_annotations (image_id);

CREATE TABLE image_quality_checks (
    id                  BIGSERIAL PRIMARY KEY,
    image_id            BIGINT NOT NULL REFERENCES images(id) ON DELETE CASCADE,
    checked_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    file_exists         BOOLEAN NOT NULL,
    is_corrupt          BOOLEAN NOT NULL DEFAULT FALSE,
    extension_matches   BOOLEAN NOT NULL DEFAULT TRUE,
    expected_mime_type  TEXT,
    actual_mime_type    TEXT,
    dimensions_ok       BOOLEAN NOT NULL DEFAULT TRUE,
    mean_brightness     NUMERIC(5,4),
    laplacian_variance  NUMERIC(12,4),
    overall_status      TEXT NOT NULL DEFAULT 'UNKNOWN',
    issues              TEXT[],
    checker_version     TEXT,
    CONSTRAINT quality_status_known CHECK (
        overall_status IN ('PASS','PASS_WITH_WARNINGS','FAIL','UNKNOWN')
    )
);

CREATE INDEX idx_image_quality_image ON image_quality_checks (image_id);
CREATE INDEX idx_image_quality_status ON image_quality_checks (overall_status);

CREATE TABLE data_quality_reports (
    id              BIGSERIAL PRIMARY KEY,
    run_key         TEXT NOT NULL UNIQUE,
    scope           TEXT NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    checker_version TEXT,
    total_checked   INTEGER NOT NULL DEFAULT 0,
    passed          INTEGER NOT NULL DEFAULT 0,
    warnings        INTEGER NOT NULL DEFAULT 0,
    failed          INTEGER NOT NULL DEFAULT 0,
    report_path     TEXT,
    summary         JSONB,
    status          TEXT NOT NULL DEFAULT 'RUNNING'
);

CREATE TABLE data_quality_findings (
    id              BIGSERIAL PRIMARY KEY,
    report_id       BIGINT NOT NULL REFERENCES data_quality_reports(id) ON DELETE CASCADE,
    check_key       TEXT NOT NULL,
    severity        severity_level NOT NULL,
    category        TEXT NOT NULL,
    table_name      TEXT,
    record_id       BIGINT,
    field_name      TEXT,
    message         TEXT NOT NULL,
    suggested_action TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_quality_findings_report ON data_quality_findings (report_id);
CREATE INDEX idx_quality_findings_severity ON data_quality_findings (severity);

CREATE TABLE model_versions (
    id                  BIGSERIAL PRIMARY KEY,
    model_name          TEXT NOT NULL,
    version             TEXT NOT NULL,
    task                TEXT NOT NULL,
    architecture        TEXT,
    framework           TEXT,
    framework_version   TEXT,
    input_size          TEXT,
    num_classes         INTEGER CHECK (num_classes IS NULL OR num_classes > 0),
    weights_path        TEXT,
    weights_sha256      TEXT CHECK (weights_sha256 IS NULL OR weights_sha256 ~ '^[0-9a-f]{64}$'),
    training_dataset_id BIGINT REFERENCES datasets(id) ON DELETE SET NULL,
    validation_dataset_id BIGINT REFERENCES datasets(id) ON DELETE SET NULL,
    test_dataset_id     BIGINT REFERENCES datasets(id) ON DELETE SET NULL,
    metrics_basis       metrics_basis NOT NULL DEFAULT 'NOT_MEASURED',
    is_deployed         BOOLEAN NOT NULL DEFAULT FALSE,
    status              TEXT NOT NULL DEFAULT 'TRAINED',
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (model_name, version),
    CONSTRAINT model_task_known CHECK (
        task IN ('IDENTIFICATION','DISEASE_CLASSIFICATION','PEST_CLASSIFICATION','SEGMENTATION','QUALITY_GATE','SYMPTOM_DETECTION')
    ),
    CONSTRAINT model_status_known CHECK (
        status IN ('TRAINING','TRAINED','EVALUATED','DEPLOYED','RETIRED','REJECTED')
    ),
    CONSTRAINT model_metrics_basis_consistent CHECK (
        metrics_basis <> 'MEASURED' OR test_dataset_id IS NOT NULL
    )
);

CREATE INDEX idx_model_versions_task ON model_versions (task, is_deployed);
CREATE TRIGGER trg_model_versions_touch BEFORE UPDATE ON model_versions
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE TABLE model_metrics (
    id                  BIGSERIAL PRIMARY KEY,
    model_version_id    BIGINT NOT NULL REFERENCES model_versions(id) ON DELETE CASCADE,
    dataset_id          BIGINT REFERENCES datasets(id) ON DELETE SET NULL,
    split               dataset_split,
    metric_name         TEXT NOT NULL,
    metric_value        NUMERIC(12,6) NOT NULL,
    sample_size         INTEGER CHECK (sample_size IS NULL OR sample_size > 0),
    ci_lower            NUMERIC(12,6),
    ci_upper            NUMERIC(12,6),
    measured_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    measurement_script  TEXT,
    measurement_notes   TEXT,
    UNIQUE (model_version_id, dataset_id, split, metric_name, measured_at)
);

CREATE INDEX idx_model_metrics_model ON model_metrics (model_version_id, metric_name);

CREATE TABLE model_evaluations (
    id                  BIGSERIAL PRIMARY KEY,
    model_version_id    BIGINT NOT NULL REFERENCES model_versions(id) ON DELETE CASCADE,
    dataset_id          BIGINT NOT NULL REFERENCES datasets(id) ON DELETE RESTRICT,
    split               dataset_split NOT NULL,
    sample_size         INTEGER NOT NULL CHECK (sample_size > 0),
    confusion_matrix    JSONB,
    per_class_metrics   JSONB,
    measured_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    evaluation_script   TEXT,
    notes               TEXT,
    UNIQUE (model_version_id, dataset_id, split)
);

CREATE TABLE model_classes (
    id                  BIGSERIAL PRIMARY KEY,
    model_version_id    BIGINT NOT NULL REFERENCES model_versions(id) ON DELETE CASCADE,
    class_index         INTEGER NOT NULL CHECK (class_index >= 0),
    class_label         TEXT NOT NULL,
    class_kind          condition_class NOT NULL DEFAULT 'UNKNOWN',
    plant_id            BIGINT REFERENCES plants(id) ON DELETE SET NULL,
    disease_id          BIGINT REFERENCES diseases(id) ON DELETE SET NULL,
    pest_id             BIGINT REFERENCES pests(id) ON DELETE SET NULL,
    description         TEXT,
    UNIQUE (model_version_id, class_index),
    UNIQUE (model_version_id, class_label)
);

CREATE INDEX idx_model_classes_lookup ON model_classes (class_label);

CREATE TABLE model_labels (
    id                  BIGSERIAL PRIMARY KEY,
    label_key           TEXT NOT NULL UNIQUE,
    display_name        TEXT NOT NULL,
    class_kind          condition_class NOT NULL DEFAULT 'UNKNOWN',
    plant_id            BIGINT REFERENCES plants(id) ON DELETE SET NULL,
    disease_id          BIGINT REFERENCES diseases(id) ON DELETE SET NULL,
    pest_id             BIGINT REFERENCES pests(id) ON DELETE SET NULL,
    symptom_id          BIGINT REFERENCES symptoms(id) ON DELETE SET NULL,
    aliases             TEXT[],
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT model_label_has_subject CHECK (
        plant_id IS NOT NULL OR disease_id IS NOT NULL
        OR pest_id IS NOT NULL OR symptom_id IS NOT NULL OR class_kind <> 'UNKNOWN'
    )
);

CREATE TABLE prediction_records (
    id                  BIGSERIAL PRIMARY KEY,
    model_version_id    BIGINT NOT NULL REFERENCES model_versions(id) ON DELETE RESTRICT,
    image_id            BIGINT REFERENCES images(id) ON DELETE SET NULL,
    scan_session_id     BIGINT,
    top1_label          TEXT,
    top1_probability    NUMERIC(6,5) CHECK (top1_probability IS NULL OR (top1_probability >= 0 AND top1_probability <= 1)),
    probability_is_real BOOLEAN NOT NULL DEFAULT FALSE,
    top_k               JSONB,
    latency_ms          NUMERIC(10,3) CHECK (latency_ms IS NULL OR latency_ms >= 0),
    pipeline_version    TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT probability_flag_consistent CHECK (
        top1_probability IS NULL OR probability_is_real = TRUE
    )
);

CREATE INDEX idx_predictions_scan ON prediction_records (scan_session_id);
CREATE INDEX idx_predictions_model ON prediction_records (model_version_id, created_at DESC);

CREATE TABLE scan_sessions (
    id                  BIGSERIAL PRIMARY KEY,
    client_ref          TEXT,
    app_version         TEXT,
    pipeline_version    TEXT NOT NULL,
    image_count         INTEGER NOT NULL DEFAULT 0,
    identification_status TEXT NOT NULL DEFAULT 'UNABLE',
    identification_method TEXT,
    confidence_basis    confidence_basis NOT NULL DEFAULT 'NOT_APPLICABLE',
    confidence_value    NUMERIC(6,5) CHECK (confidence_value IS NULL OR (confidence_value >= 0 AND confidence_value <= 1)),
    confidence_qualitative uncertainty_level,
    uncertainty_explanation TEXT,
    identified_plant_id BIGINT REFERENCES plants(id) ON DELETE SET NULL,
    health_indicator_value NUMERIC(5,2) CHECK (health_indicator_value IS NULL OR (health_indicator_value >= 0 AND health_indicator_value <= 100)),
    health_indicator_label TEXT,
    health_indicator_method TEXT,
    duration_ms         INTEGER,
    disclaimer_shown    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT scan_confidence_flag CHECK (
        confidence_value IS NULL OR confidence_basis IN ('MODEL_PROBABILITY', 'MEASURED_SCORE')
    ),
    CONSTRAINT scan_identification_status_known CHECK (
        identification_status IN ('IDENTIFIED','UNCERTAIN','UNABLE','REJECTED_QUALITY')
    )
);

ALTER TABLE prediction_records
    ADD CONSTRAINT prediction_scan_fk
    FOREIGN KEY (scan_session_id) REFERENCES scan_sessions(id) ON DELETE CASCADE;

CREATE TABLE scan_condition_candidates (
    id                  BIGSERIAL PRIMARY KEY,
    scan_session_id     BIGINT NOT NULL REFERENCES scan_sessions(id) ON DELETE CASCADE,
    condition_class     condition_class NOT NULL,
    condition_ref       BIGINT,
    condition_label     TEXT NOT NULL,
    rank                SMALLINT NOT NULL DEFAULT 1,
    confidence_basis    confidence_basis NOT NULL DEFAULT 'HEURISTIC_RULE',
    confidence_value    NUMERIC(6,5) CHECK (confidence_value IS NULL OR (confidence_value >= 0 AND confidence_value <= 1)),
    confidence_qualitative uncertainty_level,
    supporting_evidence JSONB,
    is_ai_generated     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (scan_session_id, condition_class, condition_ref, condition_label)
);

CREATE INDEX idx_scan_candidates_scan ON scan_condition_candidates (scan_session_id, rank);

CREATE TABLE scan_evidence (
    id                  BIGSERIAL PRIMARY KEY,
    scan_session_id     BIGINT NOT NULL REFERENCES scan_sessions(id) ON DELETE CASCADE,
    image_id            BIGINT REFERENCES images(id) ON DELETE SET NULL,
    symptom_id          BIGINT REFERENCES symptoms(id) ON DELETE SET NULL,
    evidence_text       TEXT NOT NULL,
    measured_value      NUMERIC(12,6),
    unit                TEXT,
    bbox                JSONB,
    source_component    TEXT NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_scan_evidence_scan ON scan_evidence (scan_session_id);
