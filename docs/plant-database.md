# Plant database

## Size and provenance

`knowledge/dist/plantdoctor.db` is a SQLite database shipped inside the APK as
`mobile/assets/plant_knowledge/plantdoctor.db` (6.5 MB). It is built from
`knowledge/data/raw/gbif_species.json` by
`knowledge/scripts/build_sqlite.py`.

| Metric | Value |
| --- | --- |
| Plant records | 3,918 |
| Duplicate scientific names | 0 |
| Unique slugs | 3,918 |
| Families | 92 |
| Genera | 310 |
| Missing scientific name | 0 |
| Missing taxonomy | 0 |
| Missing source | 0 |
| Missing authorship | 10 |
| Records with a common name | 1,819 |
| Records without one | 2,099 |
| Integrity check | ok |
| Foreign-key violations | 0 |

Every plant row carries its data source in `provenance`, and the taxon status
is taken from GBIF's backbone taxonomy rather than invented.

## Honest limitations

**All 3,918 records are `UNVERIFIED`.** They are real GBIF taxon records with
taxonomy and source attached, but the *agronomic* content has not been checked
by an expert. The app shows this status rather than implying the records are
field-verified. `verification_records` is 0 and stays 0 until a human reviewer
signs off.

**No images.** `plant_images` is 0. Identification comes from the crop/condition
model, not from matching a photo to these records.

**Cultivation data is empty.** `growing_conditions` and related tables have no
rows, so the app's growing-conditions section states that no sourced data is
available for that species instead of showing typical values for the genus.

**Toxicity is `UNKNOWN` for all 3,918.** See `docs/toxicity-database.md`.

## How a scan reaches these records

1. The TFLite model predicts one of 38 crop/condition classes.
2. `ml/scripts/build_model_labels.py` writes `plant_slug` into
   `mobile/assets/models/plantdoctor_plants.labels.json` for each class, by
   matching the class's scientific name to a row in this database.
3. `PlantModelService` returns the prediction with its slug.
4. `IdentificationService` sets `IdentificationCandidate.plantId` to that slug.
5. `KnowledgeRepository.profileForSlug()` opens the profile screen.

All 38 classes link to a real row and 0 are unresolved, enforced by
`mobile/test/model_bundle_test.dart`.

The knowledge database is opened read-only from the app's documents directory
as `plantdoctor_knowledge.db`, which deliberately differs from the app's
writable `plantdoctor.db` so the shipped read-only data is never modified.

## Rebuilding

```bash
python3 knowledge/scripts/build_sqlite.py
python3 scripts/validate_plants.py
python3 ml/scripts/build_model_labels.py
```

`build_sqlite.py` writes both `knowledge/dist/plantdoctor.db` and the
`mobile/assets/plant_knowledge/` copy the app packages, so there is no manual
copy step. The asset copy is published only after validation passes, so a
failed build cannot leave the app bundling a rejected database. Pass
`--asset ""` to build into `dist` alone.

`build_sqlite.py` refuses to fabricate rows: if the 2,000-record target is not
met it reports the shortfall and exits non-zero rather than inserting
placeholders.
