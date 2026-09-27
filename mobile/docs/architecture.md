# PlantDoctor – Architecture

## Overview

PlantDoctor is a Flutter application that runs a deterministic, rule-based
image-analysis pipeline on the device. There is no server component; photos and
results live in the app's own storage.

```
User photo(s)
   │  image_picker / camera
   ▼
ImageFiles (copy original into scans/<id>/)
   │
   ▼
AnalyzeService.analyze()
   ├─ decode + AnalysisEngine.prepare()  (≤640px working copy, JPEG)
   ├─ AnalysisEngine.checkQuality()      (blur, brightness, plant presence)
   ├─ AnalysisEngine.analyzeSingle()     (tile classify → plant mask → measures)
   ├─ AnalysisEngine.assess()            (symptom fingerprint, causes)
   ├─ AnalysisEngine.computeIndex()      (experimental Health Index)
   └─ PlantClassifier.classify()         (growth-form guess + capped species)
   │
   ▼
AnalysisBundle → AnalysisResultScreen
   └─ save → HistoryController / PlantsController → AppDatabase (SQLite)
```

## Layers

### `lib/core`
- `constants.dart` – app constants and storage keys.
- `theme/app_theme.dart` – Material 3 nature theme (colours, cards, buttons).
- `formats.dart` – display helpers (percentages, subject labels, grades).

### `lib/models`
- `analysis_models.dart` – `LeafAnalysis` (per-image measures), `HealthReport`
  (statements + ranked `CauseCandidate`s), `HealthIndex`, `ImageQualityReport`,
  `EvidenceRegion`.
- `scan_models.dart` – `ScanRecord` (persisted check-up), `SavedPlant`,
  `FollowUpContext`, `AnalysisBundle`, science-fair result types.

### `lib/services`
- `analysis/analysis_engine.dart` – the core engine (details below).
- `analysis/analyze_service.dart` – orchestration; reads files, produces a
  bundle, records timing.
- `identification/plant_classifier.dart` – morphology heuristics.
- `education_content.dart` – curated Learn topics + rotating Home "tip of the
  day" (deterministic per day-of-year).
- `plant_database.dart` – 12 curated plant care entries.
- `synthetic_samples.dart` – reproducible synthetic leaves (seeded), used by
  tests, the science-fair demo and the experiment lab.
- `science_fair_service.dart` – benchmark runner + experiment comparisons.
- `image_files.dart` – where photos are stored.
- `storage/app_database.dart` – SQLite schema/open for `scans` and `plants`.
- `storage/settings_service.dart` – `SharedPreferences` persistence.

### `lib/state`
- `providers.dart` – `SettingsController`, `HistoryController`,
  `PlantsController`. Constructed in `main.dart`, exposed via `provider`.

### `lib/screens` / `lib/widgets`
- Tab shell (Home / My Plants / Learn / History / Settings), scan flow,
  results, science-fair screens, and reusable components
  (`HealthRing`, `StatCard`, `EvidenceOverlay`, `EmptyState`, …).
- Learn = science topics (photosynthesis, nutrition, diseases, pests, water
  stress, soil, care, how the analysis works, AI limits) + plant catalogue.
- Home = hero "SCAN PLANT" card, science-fair entry, daily tip, recent scans.

## The analysis engine (`analysis_engine.dart`)

1. **prepare** – resize to ≤ `analysisMaxDimension` (640) with average
   downsampling, encode JPEG ~88.
2. **quality** – Laplacian-variance blur score (computed on a nearest-neighbour
   downscale so edges survive); mean-luminance brightness; plant-presence.
   Thresholds: too-dark < 0.16 brightness, too-blurry < 14 blur score.
3. **tile classify** – HSV on a coarse grid; bands:
   - dark `v < 0.20`
   - yellow/lime `h ∈ [40, 90]`, `s ≥ 0.22`, `v ≥ 0.33`
   - green `h ∈ [90, 170]`
   - brown `h ≤ 42 ∨ h ≥ 330`, `s ≥ 0.12`, `v ∈ [0.05, 0.52]`
4. **plant detection** – connected components (4-connectivity) of non-dark
   vegetation tiles; components that survive size/shape heuristics form the
   plant mask. `plantCoverage` = plant tile fraction of the frame.
5. **damage/spot** – interior non-green tiles with green neighbours count as
   spots/lesions (yellow needs 3 of 4 orthogonal green neighbours; brown/none
   needs 2).
6. **measures** per image → `LeafAnalysis` (fractions, aspect ratio, roundness,
   edge density, texture variation, evidence regions).
7. **assess** – combines plant-relative shares of yellow/brown/spot into an
   overall condition and a ranked, honest symptom fingerprint.
8. **computeIndex** – plant-relative Health Index:

   | component | weight | definition (clamped 0–1) |
   |---|---|---|
   | Color condition | 25% | `1 − (yellow/coverage)/0.45` |
   | Visible damage | 30% | `1 − ((yellow+brown+spot)/coverage)/0.40` |
   | Spot area | 20% | `1 − (spot/coverage)/0.25` |
   | Leaf integrity | 15% | `coverage/0.70` |
   | Texture | 10% | `1 − textureVariation/120` |

   Grade bands: ≥85 excellent, ≥70 good, ≥55 needs attention, ≥35 concerning,
   else poor. "Affected" for the benchmark is `< 70`.

9. **identification** – growth-form groups from aspect ratio / roundness /
   edge density / coverage; species suggestions scored from curated morphology
   tags, **capped at 0.42** (below the 0.45 uncertainty threshold), so the app
   always reports species-level uncertainty honestly.

## Storage

- **Document directory**
  - `scans/<scanId>/original_<i>.<ext>` – imported photos
  - `scans/<scanId>/working_<i>.jpg` – ≤640px working copies used for display
- **SQLite** (db `plantdoctor.db`):
  - `scans(id, created_at, thumb_path, image_paths, image_subjects,
    plant_guess, scientific_guess, id_confidence, id_uncertain,
    health_index, condition, indicators, causes, follow_up, notes,
    saved_plant_id)`
  - `plants(id, name, species, created_at, notes, health_index, photo)`
- **SharedPreferences** – `show_disclaimers`, `science_fair_mode`.

## Concurrency

Analysis runs on the UI isolate: it is fast (small downscaled images) and
avoids `dart:ui` transfer barriers. The science-fair benchmark runs the full
engine across 42 small synthetic cases in well under a second.