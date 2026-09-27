-- ---------------------------------------------------------------------------
-- 017: refuse to merge a plant into itself.
--
-- fn_merge_duplicate_plants(p_keep, p_drop) had no guard against
-- p_keep = p_drop. Every statement in the function is written for two
-- distinct plants, so the self-merge case was not a harmless no-op: it fell
-- through to `DELETE FROM plants WHERE id = p_drop`, which removed the very
-- record the caller asked to keep. Any tooling bug or bad manual call could
-- therefore destroy a plant row together with its provenance.
--
-- This redefines the function with the guard first. The body is otherwise
-- identical to 014 so the merge semantics do not change.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_merge_duplicate_plants(p_keep BIGINT, p_drop BIGINT)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_keep IS NULL OR p_drop IS NULL THEN
        RAISE EXCEPTION 'fn_merge_duplicate_plants: both plant ids are required'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF p_keep = p_drop THEN
        RAISE EXCEPTION
            'fn_merge_duplicate_plants: refusing to merge plant % into itself', p_keep
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

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
