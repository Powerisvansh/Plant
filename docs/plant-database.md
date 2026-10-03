# Plant database

## Size and provenance

`knowledge/dist/plantdoctor.db` is a SQLite database shipped inside the APK as
`mobile/assets/plant_knowledge/plantdoctor.db` (18.8 MB). It is built from
`knowledge/data/raw/gbif_species.json` by
`knowledge/scripts/build_sqlite.py`.

| Metric | Value |
| --- | --- |
| Plant records | 10,000 |
| Duplicate scientific names | 0 |
| Unique slugs | 10,000 |
| Families | 333 |
| Genera | 2,166 |
| Missing scientific name | 0 |
| Missing taxonomy | 0 |
| Missing source | 0 |
| Missing authorship | 10 |
| Records with a common name | 4,157 |
| Records without one | 5,843 |
| Integrity check | ok |
| Foreign-key violations | 0 |

Every plant row carries its data source in `provenance`, and the taxon status
is taken from GBIF's backbone taxonomy rather than invented.

## Categories

Every one of the 10,000 plants sits in at least one user-facing category, and
exactly one is flagged primary for the browse card — so there is no
uncategorised pile.

| Table | Rows |
| --- | --- |
| `plant_categories` | 22 |
| `plant_category_map` | 10,173 |
| `plant_crops` | 61 |
| `plant_traits` | 179 |

The vocabulary covers the ways a grower actually browses: food crop, cereal,
pulse, oilseed, vegetable, fruit, herb, spice, agricultural/cash crop, fibre,
plantation, forage, rooftop/container, ornamental, indoor, medicinal, aquatic,
weed, tree, shrub, climber and succulent.

Current membership:

| Category | Plants |
| --- | --- |
| Ornamental | 5,184 |
| Indoor plant | 994 |
| Fruit | 666 |
| Tree | 576 |
| Medicinal / aromatic | 550 |
| Vegetable | 481 |
| Spice | 391 |
| Wild / weedy | 354 |
| Cereal / grain | 336 |
| Pulse / legume | 325 |
| Agricultural / cash crop | 104 |
| Food crop | 67 |
| Oilseed | 65 |
| Rooftop / container garden | 58 |
| Herb | 9 |
| Fodder / forage | 6 |
| Aquatic / wetland | 5 |
| Plantation crop | 2 |

Membership comes from two curated sources, and neither invents a taxon:

1. **`crop_coverage.json`** — explicit per-species membership for the 61 food,
   agricultural and urban-garden plants people ask about, together with crop
   attributes (crop role, edible part, sowing season, harvest period, duration,
   cultivation system) and horticultural traits. This always wins.
2. **The GBIF harvest group fallback** — every remaining species is mapped from
   the collection bucket it was imported under, so nothing is left unclassified.

Category assignment groups taxa the GBIF import already confirmed and records
no new biological claim, so these rows are stored `UNVERIFIED_CATEGORY` rather
than `VERIFIED`. `MEDICINAL` is a *use* category only — never a safety, dosage
or efficacy claim, and it never implies a plant is safe to consume.

`ROOFTOP_GARDEN` is granted only where `rooftop_greenery.json` or
`crop_coverage.json` carries explicit siting evidence. It is never inferred from
a species merely being a herb or a succulent, because a wrong "grows on your
balcony" claim is worse than an absent one.

Four vocabulary entries currently hold **no** members — `CLIMBER`,
`FIBRE_CROP`, `SHRUB` and `SUCCULENT`. They are defined and available, but
nothing maps to them yet: the harvest groups they would come from
(`fibre_and_industrial`, `houseplants_and_succulents`, `trees_and_forestry`)
all resolve to broader categories instead. The browse screen hides a chip whose
count is zero, so these never appear as an empty filter. Assigning them needs
either an explicit `crop_coverage.json` entry or a finer group map — it is not
inferred, because guessing a growth form from a genus name is exactly the kind
of claim this project refuses to make.

## Scan suggestions

`ScanSuggestionService` turns one scan into concrete next steps by joining the
image measurements to this database. It is the layer between "a model said this
is a tomato" and "here is what to do about it".

Three rules govern it, and each is enforced by a test:

| Rule | Why |
| --- | --- |
| **Never name a species the model did not confidently name** | Below the 0.45 floor the result stays uncertain, so no species is attached |
| **Never suggest a cause without measured evidence** | A leaf with no yellowing is never told about nitrogen deficiency |
| **Never suggest a dose** | `treatments` is empty by design; no rate can be printed |

What a scan can therefore produce:

- **Categories** — the named plant's real category labels, e.g.
  "Food crop · Vegetable · Agricultural / cash crop · Rooftop / container garden"
- **Cultivation detail** — crop role, edible part, life cycle, sowing season,
  harvest period and duration, but only for the 61 species that have a curated
  record
- **Symptom observations** — driven by the measured yellow, brown and spotted
  fractions, phrased as observations rather than diagnoses
- **Cultural controls first** — the project's fixed retrieval order: physical
  and cultural steps before anything chemical
- **Related plants** — same genus, then same family, drawn from all 10,000
  records and tappable straight into the profile
- **A safety line** — every record is `UNKNOWN` toxicity, so the screen states
  that absence from a toxic list is not proof of safety

Suggestions are derived from pixels first, so a plant the model cannot identify
still receives useful, evidence-based guidance instead of a dead end.

## Measured model behaviour on real photographs

The shipped TFLite classifier was run against 12 real PlantVillage photographs
(`ml/scripts/run_model_on_real_photos.py`, sampling is scripted alongside it):

| Result | Value |
| --- | --- |
| Crop identified correctly | **12 / 12** |
| Healthy vs diseased correct | **12 / 12** |
| Named above the 0.60 threshold | 12 / 12 |

The only error was a specific-disease confusion: `Tomato___Early_blight` was
called `Tomato___Late_blight` — correct crop, correctly "diseased", wrong
condition.

This is why both analysis layers exist. The pixel engine alone scored 8–9 / 12
and called `Apple___Black_rot` and `Apple___Apple_scab` "Looks healthy"; the
classifier identified both correctly.

### Known limitation: no out-of-distribution handling

Two deliberately non-plant inputs were also run:

| Input | Prediction | Behaviour |
| --- | --- | --- |
| Flat grey square | Tomato mosaic virus, 36.3% | correctly uncertain |
| Synthetic green shape | **Soybean healthy, 78.4%** | **over-confident** |

The model has no concept of "not a plant I know", so anything vaguely
leaf-shaped is assigned to the nearest of its 14 crops with real confidence.

A pixel-level foliage gate was trialled and **rejected on measurement**. Real
leaf photos span `plantCoverage` 0.197–0.970 while the synthetic shape sits at
0.176 — the margin is only 0.02, so any floor that excluded it would sit within
2 points of the sparsest real leaf and would refuse a legitimate photo of a
small, distant leaf. A green-fraction floor is worse: `Potato___Early_blight`
measures 0.008 green, so it would reject a genuinely diseased plant outright.

Closing this properly requires retraining with negatives, which changes the
published model metrics and needs its own evaluation run. Until then the
behaviour is documented rather than patched over. `real_photo_pipeline_test.dart`
records the measured numbers so the finding is not lost.

Rooftop and terrace siting guidance lives in its own `plant_rooftop` table and
its own curated file, `knowledge/data/curated/rooftop_greenery.json`. See
[rooftop-greenery.md](rooftop-greenery.md) for how to add a species.

## Honest limitations

**All 10,000 records are `UNVERIFIED`.** They are real GBIF taxon records with
taxonomy and source attached, but the *agronomic* content has not been checked
by an expert. The app shows this status rather than implying the records are
field-verified. `verification_records` is 0 and stays 0 until a human reviewer
signs off.

**No images.** `plant_images` is 0. Identification comes from the crop/condition
model, not from matching a photo to these records.

**Cultivation data is empty.** `growing_conditions` and related tables have no
rows, so the app's growing-conditions section states that no sourced data is
available for that species instead of showing typical values for the genus.

**Toxicity is `UNKNOWN` for all 10,000.** See `docs/toxicity-database.md`.

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

`build_sqlite.py` refuses to fabricate rows: if the 10,000-record target is not
met it reports the shortfall and exits non-zero rather than inserting
placeholders.

## How the 10,000 records were discovered

Discovery runs in two stages, both requiring the same evidence — a species is
only staged once GBIF confirms it is an accepted Plantae `SPECIES` with real
occurrence records in India.

1. **Curated genus worklist** (`target_genera.json`, 321 genera in 12 groups).
   This runs first so the India-relevant crop, medicinal, ornamental and
   forestry genera are covered deliberately. Per-genus caps stop one huge genus
   dominating the catalogue.
2. **Kingdom-level paging.** The curated list saturates at roughly 5,800
   species, because a genus can only ever contribute what is recorded in India
   *within that genus* — *Solanum*, for example, has only 97 India-recorded
   species. Past that point `collect_wide()` pages
   `/occurrence/search?country=IN&taxonKey=6&facet=speciesKey` with
   `facetOffset`, which returns the same kind of occurrence evidence across the
   whole plant kingdom. It is resumable: the next facet offset is recorded in
   `gbif_state.json` under `__wide__`, so an interrupted run continues instead
   of restarting.

The two routes together produced 10,000 unique species across 333 families and
2,166 genera, adding 4,172 species by wide paging.
