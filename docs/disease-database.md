# Disease database

## What is stored

25 disease records, one per PlantVillage disease class, linked to their host
plants through `plant_diseases`. Each record carries:

- name, slug, pathogen name, pathogen type (fungus / bacterium / virus / oomycete)
- description, visual symptoms, favourable conditions, transmission
- prevention and management notes
- verification status, last-verified date, source id

Example (`Tomato early blight`, id 19):

| Field | Value |
| --- | --- |
| Pathogen | *Alternaria solani* (fungus) |
| Description | Common fungal foliar disease of tomato; begins on older lower leaves and progresses upward. |
| Visual symptoms | Dark brown lesions on older leaves with concentric target-like rings and a yellow halo |
| Favourable conditions | Warm humid weather (24-29 C) with alternating wet and dry periods |
| Transmission | Soil and debris-borne; spores dispersed by wind and rain splash |
| Prevention | Rotation, staking for airflow, mulching to stop soil splash, balanced nutrition |
| Management | Sanitation and airflow first; fungicides where the disease recurs annually |
| Source | APS Common Names of Plant Diseases (facts: names, pathogens) |

## Coverage

| Crop | Diseases |
| --- | --- |
| Apple | scab, black rot, cedar apple rust |
| Cherry | powdery mildew |
| Corn | gray leaf spot, common rust, northern corn leaf blight |
| Grape | black rot, esca, leaf blight |
| Orange | citrus greening |
| Peach | bacterial spot |
| Pepper | bacterial spot |
| Potato | early blight, late blight |
| Squash | powdery mildew |
| Strawberry | leaf scorch |
| Tomato | bacterial spot, early blight, late blight, leaf mould, Septoria leaf spot, spider mites, target spot, yellow leaf curl virus, mosaic virus |

This mirrors the model's 38 classes exactly. It is **not** a general plant
pathology reference: there are no disease records for the other ~3,900 species
in the plant database.

## Verification status

All 25 records are `UNVERIFIED`. The names and pathogen identities come from
APS's Common Names of Plant Diseases, but the symptom and management text is
project-curated and has not been expert-reviewed. The app displays the status.

## What the app does and does not claim

The model can *predict* one of these 25 disease classes for the 14 crops, and
then the app retrieves the matching record for reference. The app:

- shows the model's ranked candidates, not a single forced answer
- labels the result as visual screening
- shows the disease record with its verification status
- does not recommend a pesticide, and contains no dosage

Two spots are easy to confuse and are worth stating plainly:

**Deficiencies and stresses are general reference, not per-plant matches.**
`nutrient_deficiencies` (12 rows) and `environmental_stresses` (8 rows) are
plant-independent. The app labels them "General reference" and notes that
yellowing leaves alone do not identify a deficiency.

**Pests are linked to plants** (7 pest records via `plant_pests`) but come from
the same curated source and carry the same unverified status.

## Adding diseases

Insert into `diseases`, link via `plant_diseases`, and add a `provenance` row
naming the source. `insert_diseases()` in `knowledge/scripts/build_sqlite.py`
is the pattern to follow. Do not add a disease without a citable source; an
empty disease list is better than an unsourced one.
