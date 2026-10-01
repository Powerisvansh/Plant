# Rooftop and terrace greening

Siting guidance for species grown on roofs, terraces and balconies, aimed at
Indian conditions: hot, dusty, reflective-heat heavy, and windy at any height.

The app shows this on each plant's detail screen under **Rooftop and terrace
growing**: light, heat, drought and wind tolerance, minimum container size,
rooting depth, drainage, watering band, and the recurring maintenance.

## Why this is separate from the plant record

A rooftop is a hard siting environment and the ordinary care advice does not
answer the questions a grower actually has. The deciding facts are ones a
species profile never states: how small a pot it will tolerate, how deep it
roots, whether it survives reflected heat, and whether it holds up in wind.
Those go in `plant_rooftop`, one row per plant, rather than being mixed into
the general growing-conditions record.

## Adding a species

Edit `knowledge/data/curated/rooftop_greenery.json` and append to its `species`
list. The `_meta` block documents every field; read it before filling anything
in.

```json
{
  "scientific_name": "Ocimum basilicum L.",
  "rooftop_role": "edible",
  "siting": {
    "exposure": "full sun",
    "heat_tolerance": "moderate",
    "drought_tolerance": "low",
    "wind_exposure": "moderate"
  },
  "container": {
    "min_container_litres": 6,
    "root_depth_cm": 25,
    "drainage": "needs free drainage"
  },
  "watering": {
    "watering_band": "moderate",
    "establishment_watering": "keep the mix moist for the first month"
  },
  "maintenance": {
    "pruning_requirement": "pinch out flower spikes to keep leaf",
    "self_sown": "no",
    "special_hazards": "none recorded"
  },
  "notes": "Wilts in a hot afternoon before it is genuinely dry.",
  "sources": []
}
```

Then rebuild:

```bash
python3 knowledge/scripts/build_sqlite.py
python3 scripts/validate_plants.py
```

The build writes the bundle to `mobile/assets/plant_knowledge/plantdoctor.db`
only after validation passes, so a rejected build never reaches the app.

## The name must already exist

`scientific_name` is resolved against the plants already imported from GBIF.
This file adds horticultural data to existing plants; it never introduces a
taxon. A name that matches nothing **fails the build** rather than being
skipped:

```
rooftop_greenery.json names species that are not in the knowledge base,
so they would be silently dropped: Ocimum africanum.
```

If the species genuinely is not there, add its genus to
`knowledge/data/curated/target_genera.json` and re-run
`knowledge/scripts/import_gbif.py`, which pulls it from GBIF rather than
creating it by hand.

## Sourcing, and what the status field means

Every record carries a `sources` array. The build reads it:

| `sources` | Stored status | Shown in the app as |
|---|---|---|
| empty `[]` | `UNVERIFIED` | "project-curated and not yet attached to a published source" |
| one or more citations | `VERIFIED` | "recorded with a named source" |

This is the same rule the pest and disease content follows: nothing claims
verification it does not have. A record with an empty list is not a mistake to
fix later in the database, it is the honest state until a source exists.

Add citations as objects, for example:

```json
"sources": [
  {
    "citation": "ICAR-Indian Institute of Horticulture, rooftop cultivation of container crops, 2024",
    "url": "https://example.org/iihp-rooftop-container-crops"
  }
]
```

Cite only work that actually states what the record claims. If a source covers
the species generally but not the specific figure, say so in the citation
rather than implying it does.

## What this data must not contain

Watering and treatment language stays qualitative. No column stores a measured
volume, a dilution, a dose or a spray recipe, and
`mobile/test/rooftop_content_test.dart` fails the build if one appears. Bands
like `watering_band: low` and checks like "moist to the depth of the top few
centimetres" are the intended form. Application rates need label-backed
sources and belong in the treatment content, which already requires a verified
dosage.

Toxicity notes point at the recorded `toxicity_status` and never advise
ingestion or treatment.

## Adding a genus

Rooftop species are mostly already in the worklist. If one is missing, add the
genus to the most fitting group in `target_genera.json`:

| Rooftop use | Group in `target_genera.json` |
|---|---|
| edibles and herbs | `vegetables`, `spices_and_condiments` |
| foliage and succulents | `houseplants_and_succulents` |
| flowering ornamentals | `ornamentals` |
| groundcover and turf | `cereals_and_grasses`, `wild_native_and_weedy` |
| trees and shrubs for shade or screening | `trees_and_forestry` |

`medicinal_and_aromatic` covers the strongly scented herbs that do well in
containers, including curry leaf and tulsi.

## Versions

Adding the `plant_rooftop` table took the knowledge base to `schema_version` 2
and `data_release` 2026.10.0. The app reads both from the bundle's `meta`
table, so an older APK that receives a newer bundle sees a higher version
rather than silently missing the section. The repository method is gated on the
table existing, so an older bundle opened by newer code reads as "no rooftop
data" rather than throwing.

## Scope

This is siting reference content, not a design guide. It does not cover
structural loading of a roof, waterproofing, drainage falls, or irrigation
design, and nothing here should be read as approving a specific structure for
a specific load. The bundled visual model is unchanged: these species are
knowledge-base records, not model classes.
