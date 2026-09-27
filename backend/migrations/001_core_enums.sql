-- 001_core_enums.sql
-- Controlled vocabularies. Every enum value here is part of the public API contract.

CREATE TYPE verification_status AS ENUM (
    'VERIFIED',
    'PARTIALLY_VERIFIED',
    'UNVERIFIED',
    'CONFLICTING',
    'UNKNOWN'
);

CREATE TYPE license_type AS ENUM (
    'CC0',
    'CC_BY_3_0',
    'CC_BY_4_0',
    'CC_BY_SA_3_0',
    'CC_BY_SA_4_0',
    'CC_BY_NC_4_0',
    'PUBLIC_DOMAIN',
    'ODC_BY_1_0',
    'PERMISSION_GRANTED',
    'PROPRIETARY',
    'UNKNOWN'
);

CREATE TYPE source_type AS ENUM (
    'TAXONOMIC_DATABASE',
    'PEER_REVIEWED_PAPER',
    'GOVERNMENT_AGENCY',
    'UNIVERSITY_EXTENSION',
    'FIELD_GUIDE',
    'REFERENCE_WORK',
    'PRODUCT_LABEL',
    'REGULATORY_REGISTER',
    'CLINICAL_REFERENCE',
    'VETERINARY_REFERENCE',
    'STANDARD',
    'WIKI_OTHER',
    'PERSONAL_OBSERVATION',
    'OTHER'
);

CREATE TYPE plant_part AS ENUM (
    'WHOLE_PLANT',
    'LEAF',
    'FLOWER',
    'FRUIT',
    'STEM',
    'ROOT',
    'SEED',
    'BARK',
    'BUD',
    'TENDRIL',
    'POLLEN',
    'NECTAR',
    'ALL_PARTS',
    'UNKNOWN'
);

CREATE TYPE condition_class AS ENUM (
    'DISEASE',
    'PEST',
    'NUTRIENT_DEFICIENCY',
    'ENVIRONMENTAL_STRESS',
    'PHYSICAL_DAMAGE',
    'NORMAL_VARIATION',
    'UNKNOWN'
);

CREATE TYPE toxicity_status AS ENUM (
    'NON_TOXIC',
    'TOXIC',
    'POTENTIALLY_TOXIC',
    'UNKNOWN'
);

CREATE TYPE risk_level AS ENUM (
    'NONE',
    'LOW',
    'MODERATE',
    'HIGH',
    'SEVERE',
    'UNKNOWN'
);

CREATE TYPE severity_level AS ENUM (
    'NONE',
    'MILD',
    'MODERATE',
    'SEVERE',
    'LIFE_THREATENING',
    'UNKNOWN'
);

CREATE TYPE evidence_level AS ENUM (
    'AUTHORITATIVE_REFERENCE',
    'PEER_REVIEWED',
    'GOVERNMENT_EXTENSION',
    'MULTIPLE_INDEPENDENT_REPORTS',
    'SINGLE_REPORT',
    'ANECDOTAL',
    'UNVERIFIED'
);

CREATE TYPE confidence_basis AS ENUM (
    'MODEL_PROBABILITY',
    'MEASURED_SCORE',
    'HEURISTIC_RULE',
    'EXPERT_RULE',
    'QUALITATIVE_ESTIMATE',
    'NOT_APPLICABLE'
);

CREATE TYPE uncertainty_level AS ENUM (
    'HIGH',
    'MODERATE',
    'LOW',
    'UNKNOWN'
);

CREATE TYPE measurement_basis AS ENUM (
    'MEASURED',
    'REPORTED_BY_SOURCE',
    'APPROXIMATE_RANGE_FROM_SOURCE',
    'ILLUSTRATIVE',
    'NOT_MEASURED'
);

CREATE TYPE image_condition AS ENUM (
    'HEALTHY',
    'DISEASED',
    'PEST_DAMAGED',
    'NUTRIENT_DEFICIENT',
    'STRESSED',
    'DAMAGED',
    'UNKNOWN'
);

CREATE TYPE dataset_split AS ENUM (
    'TRAIN',
    'VALIDATION',
    'TEST',
    'UNASSIGNED'
);

CREATE TYPE copyright_status AS ENUM (
    'PUBLIC_DOMAIN',
    'OPEN_LICENSE',
    'PERMISSION_GRANTED',
    'ALL_RIGHTS_RESERVED',
    'UNKNOWN'
);

CREATE TYPE annotation_status AS ENUM (
    'UNANNOTATED',
    'AUTO_LABELED',
    'HUMAN_REVIEWED',
    'VERIFIED'
);

CREATE TYPE approval_status AS ENUM (
    'PENDING_REVIEW',
    'APPROVED',
    'REJECTED'
);

CREATE TYPE target_kind AS ENUM (
    'DISEASE',
    'PEST',
    'NUTRIENT_DEFICIENCY',
    'ENVIRONMENTAL_STRESS'
);

CREATE TYPE exposure_route AS ENUM (
    'INGESTION',
    'SKIN_CONTACT',
    'EYE_CONTACT',
    'INHALATION',
    'INJECTION',
    'OTHER',
    'UNKNOWN'
);

CREATE TYPE subject_kind AS ENUM (
    'PLANT',
    'PEST',
    'PATHOGEN',
    'UNKNOWN'
);

CREATE TYPE metrics_basis AS ENUM (
    'MEASURED',
    'NOT_MEASURED',
    'LITERATURE_REPORTED'
);

CREATE TYPE record_conflict_status AS ENUM (
    'OPEN',
    'RESOLVED_A',
    'RESOLVED_B',
    'RESOLVED_MERGED',
    'UNRESOLVABLE'
);
