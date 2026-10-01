# Treatment database — current state and the rules for filling it

**Status: EMPTY. `treatments` = 0 rows, `treatment_products` = 0 rows,
`active_ingredients` = 0 rows, `prevention_methods` = 0 rows.**

This is deliberate, and it is the single most important honesty decision in the
project. A treatment row is the one place where a plausible-looking invention
can hurt someone: a wrong dose of a pesticide damages a crop, a poisoned
handler, or a contaminated harvest.

## Why it is empty rather than approximate

The specification forbids inventing dosage, and the project enforces that with a
schema-level gate rather than a convention:

* `v_treatment_dosage_verified` (PostgreSQL build) and the equivalent SQLite
  view only ever expose a dosage row that carries **all** of
  `label_page_reference`, `label_url`, `label_sha256` and `last_verified`.
* A dosage with no label backing is not "shown with a warning" — it is not
  returned at all.

So the honest options were: import verified label data, or ship nothing. Nothing
was available at build time, so nothing shipped.

## What a treatment row must contain

`schema_version 1` defines the columns. The non-negotiable ones:

| Field | Requirement |
|---|---|
| `crop` / `plant_id` | the crop and species the recommendation is for |
| `disease_id` / `pest_id` | the target; a treatment row must name what it treats |
| `product_name`, `formulation`, `concentration` | as printed on the label |
| `dosage_value`, `dosage_unit` | numeric dose **with** its unit; never a bare number |
| `water_volume_l` | spray volume, where the label states one |
| `application_method` | foliar spray, soil application, trunk injection, … |
| `frequency`, `application_timing` | how often and at which growth stage |
| `phi_days` | pre-harvest interval / waiting period, where applicable |
| `label_url`, `label_page_reference`, `label_sha256` | the label itself |
| `jurisdiction` | which country's label this is |
| `source_id`, `last_verified` | provenance and currency |

`jurisdiction` is not decoration. A dose legal in one country is not
automatically legal in another, and the app is built in India, so Indian
recommendations take priority and non-Indian rows are labelled with their
jurisdiction.

## India priority

Per the specification, Indian sources are searched first:

* ICAR and ICAR-NCIPM (National Institute of Plant Health Management) —
  pest and disease management material, much of it aimed at Indian crops
* State agricultural universities — package-of-practices documents
* Government agricultural advisories
* Registered product labels, which are the only acceptable basis for a dose

An old recommendation is not treated as current. Rows carry `last_verified`, and
anything past its review window is either re-verified against a current label or
suppressed from the verified view.

## Non-chemical management comes first

Even once treatment rows exist, the retrieval order is fixed:

1. remove severely affected material
2. improve air circulation
3. correct irrigation and drainage
4. sanitation
5. physical pest removal
6. crop rotation and resistant varieties
7. biological control
8. monitoring

A chemical product is presented only after these, and always with its label
data. Chemical treatment is never the first recommendation the app makes.

## What the app shows today

With the tables empty, the treatment section of a plant's detail screen reads:

> **Verified dosage information is unavailable.**
> No label-verified treatment record exists for this plant in this release.
> Start with cultural and physical controls, and consult a local agricultural
> advisory service.

It does not substitute a generic dose, a neighbouring crop's dose, or a
"typical" range.

## Plan to close the gap

1. Register the Indian reference sources in `sources` with licence and retrieval
   date.
2. Import package-of-practices documents for the priority crops (rice, wheat,
   maize, cotton, sugarcane, mustard, chickpea, pigeonpea, soybean, groundnut,
   millets, tomato, potato, onion, chilli, brinjal, cabbage, cauliflower).
3. For every dose, capture the label reference. Rows that cannot supply one are
   recorded as cultural/biological management only, with no dose columns filled.
4. Add `scripts/verify_sources.py` to re-check every `label_url` and refresh
   `last_verified`, flagging anything that has gone stale.
5. Re-run `scripts/validate_plants.py`; treatment coverage is reported in the
   table detail block.
