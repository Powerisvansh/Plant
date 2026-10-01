# Sources

Every record in the PlantDoctor knowledge base is traceable to a registered
source row in the `sources` table. The registry is stored in the built database
(`knowledge/dist/plantdoctor.db` → `sources`) and mirrored in
`data/sources.json`.

## Registered sources

| Key | Name | Kind | Organisation | Licence | Retrieved |
|---|---|---|---|---|---|
| `gbif` | GBIF Backbone Taxonomy | taxonomy | Global Biodiversity Information Facility | CC BY 4.0 | 2026-09 |
| `gbif_occurrences` | GBIF occurrence records (India) | occurrences | Global Biodiversity Information Facility | CC BY 4.0 (per record; see dataset keys) | 2026-09 |
| `plantvillage` | PlantVillage Dataset | images | Penn State / PlantVillage | CC BY-SA 3.0 | 2016 (as published) |
| `curated_project` | PlantDoctor curated content | curated | PlantDoctor project | project-curated | 2026.09.0 |
| `aps_common_names` | APS Common Names of Plant Diseases | reference | American Phytopathological Society | reference-use (facts: disease/pathogen names) | 2026-09 |
| `aspca_toxic_plants` | ASPCA Toxic and Non-Toxic Plants | reference | ASPCA | reference-use (facts) | 2026-09 |

## What each source is allowed to supply

This matters, because a licence that permits taxonomy reuse does **not**
automatically permit reusing photographs or dosage text.

* **`gbif`** — accepted scientific names, authorship, and the
  kingdom → phylum → class → order → family → genus hierarchy. This is where
  all 3,900 plant records come from. Only taxonomy is taken; occurrence media is
  not mirrored.
* **`gbif_occurrences`** — used to bias coverage toward species actually
  recorded in India, so that Haryana/UP agricultural and horticultural plants are
  over-represented relative to a global sample. Occurrence *coordinates* are not
  stored.
* **`plantvillage`** — the image dataset for the visual model. 38 classes across
  14 crops, each class a `Crop___Condition` pair. CC BY-SA 3.0 requires
  attribution **and share-alike** on redistribution, which is why the dataset is
  processed into derived artefacts (splits, a trained model) rather than
  re-published as raw images.
* **`aps_common_names`** — authoritative *names* of plant diseases and the
  pathogens behind them (for example the causal organism of late blight). Facts
  and names only; APS prose is not copied.
* **`aspca_toxic_plants`** — the reference list of toxic and non-toxic plants for
  pets. Used as a **check**, not as a licence to declare a plant safe: absence
  from the list is never recorded as `NON_TOXIC_REPORTED`.
* **`curated_project`** — content authored inside this project. Each such record
  must still name the reference it was written from; "curated" is not a
  substitute for a citation.

## Rules the importers enforce

1. **No source, no record.** A plant, disease, pest, treatment, or toxicity row
   with no `source_id` and no `data_provenance` entry is a build failure, not a
   warning. `scripts/validate_plants.py` fails the build in that case.
2. **Retrieval date is mandatory.** Every source row carries `retrieved_at`, and
   every taxon row can be re-fetched to confirm it still resolves.
3. **No uncontrolled crawling.** GBIF and other providers are accessed through
   their official APIs and download mechanisms, rate-limited, with a recorded
   user agent. The HTML website is not scraped.
4. **Per-record licence variance is respected.** GBIF occurrence records
   individually carry their own licence; the registry says so explicitly rather
   than assuming a blanket CC BY 4.0.
5. **A source can expire.** An agricultural recommendation from several years
   ago is not current. `last_verified` exists so stale rows can be found and
   either re-verified or suppressed.

## Still to be registered

The following content is required by the specification and **not yet sourced**.
Until a source is registered and rows are imported, the corresponding tables are
empty and the app shows the honest "not verified" state rather than filling the
gap:

* Indian agricultural treatment/dosage references (ICAR, ICAR-NCIPM, state
  agricultural universities, official label information)
* Per-plant toxicity profiles and human/livestock safety records
* First-aid and exposure records
* Prevention-method records

See `docs/treatment-database.md` and `docs/toxicity-database.md` for the exact
gap and the plan to close it.
