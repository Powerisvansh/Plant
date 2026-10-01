# Offline mode

Everything the app needs to identify a plant and show its record is inside the
APK. There is no network call on the identification path.

## Shipped assets

| Asset | Size | Purpose |
| --- | --- | --- |
| `assets/models/plantdoctor_plants.tflite` | 1,102.6 KB | crop/condition classifier |
| `assets/models/plantdoctor_plants.labels.json` | ~11 KB | 38 classes, real metrics, plant slugs |
| `assets/plant_knowledge/plantdoctor.db` | 6.5 MB | 3,918 plants, 25 diseases, 7 pests, sources |

All three are declared in `mobile/pubspec.yaml`. A test asserts each file
exists, so a build missing one fails rather than silently degrading.

## First launch

`KnowledgeRepository.open()` runs once per process:

1. `rootBundle.load` reads the DB from the APK.
2. The bytes are written to
   `<documents>/plantdoctor_knowledge.db`.
3. A version fingerprint derived from the asset bytes decides whether the
   on-disk copy needs replacing, so an app update refreshes the data
   automatically.
4. The file is opened with `sqflite` **read-only**.

Note the deliberate name difference: the shipped database is
`plantdoctor_knowledge.db`, while the app's own writable database is
`plantdoctor.db`. The read-only knowledge base is never mutated by app writes.

If opening fails, `KnowledgeRepository.lastError` is set and screens show an
explicit "Knowledge base unavailable" state. Identification still works without
it, because the model is independent of the database.

## Where the app is online

None of the following is required for a scan:

- no API calls, no accounts, no sync
- no Google Play ML Kit download; the TFLite model is bundled
- no remote database

PostgreSQL under `server/` exists for optional backend work and is **not** used
by the mobile identification path. It is currently stopped and nothing depends
on it.

## Result assembly

1. Photos are decoded, downscaled to 160x160, quality-gated.
2. `PlantModelService` runs the TFLite interpreter per photo.
3. `IdentificationService` averages the per-photo probability vectors, ranks
   them, and checks whether the photos disagree about the crop.
4. Below `unknown_threshold` (0.60) the result is `IdentificationSource.none`
   and no species is named.
5. Above it, the leading candidate's `plant_slug` opens the profile from the
   local database.

Because the database and model are local, a scan works in airplane mode and in
a field with no signal.

## APK size

The database is the bulk of the payload at 6.5 MB. It is stored uncompressed in
the APK; if size becomes a problem, the standard options are to ship only the
crops the model can actually return as a primary table with the rest fetched by
an optional downloadable pack, or to compress. Both trade away the "everything
is already on the phone" property, so neither was done by default.
