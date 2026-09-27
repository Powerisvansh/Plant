# DEVELOPMENT STATUS

_Last updated: 2026-09-24 (session 2)_

## Done

2. **Education content added**: `models/education_models.dart` +
   `services/education_content.dart` – 10 verified plant-science Learn topics
   (photosynthesis, nutrition, diseases, pests, water stress, soil, care, how
   the analysis works, AI limits, plant biology), a deterministic per-day
   Home "tip of the day" (10 tips), Learn topic detail screen, and the Home
   hero renamed to the spec's **SCAN PLANT** with a secondary "Upload a photo
   instead" action.
3. **Release APK verified**: `flutter build apk --release` succeeds →
   `build/app/outputs/flutter-apk/app-release.apk` (57.1 MB, package
   `com.plantdoctor.plantdoctor`, label "PlantDoctor", `CAMERA` permission).
4. **Tests**: 17/17 pass (12 engine/storage + 5 new education tests).
   `flutter analyze` – 0 issues.

## Done (from session 1)

- **Environment**: Flutter 3.47.5 + Dart 3.13.4, Android SDK (API 34/35/36),
  Java 21 configured. `flutter doctor` clean (except: no KVM → no emulator,
  no Linux desktop toolchain, no connected device).
- **Project scaffold**: `flutter create --platforms android,ios` at `mobile/`.
- **Core analysis engine** (`services/analysis/analysis_engine.dart`):
  HSV tile classifier, connected-component plant detection, damage/spot
  detection, blur + darkness quality gate, symptom fingerprint, plant-relative
  experimental Health Index, evidence regions.
- **Identification** (`plant_classifier.dart`): growth-form + species rules
  with an enforced 0.42 honesty cap (always `uncertain` for species).
- **Curated plant DB**: 12 entries (tomato, basil, mint, pothos, snake plant,
  spider plant, jade, rosemary, thyme, lemon, lettuce, boston fern).
- **Synthetic samples**: seeded, deterministic generator + facade for the
  7 benchmark conditions.
- **Science fair service**: 42-case live benchmark + Experiment Lab compare.
- **Storage**: SQLite (`scans`, `plants`), settings via SharedPreferences,
  photo files under `scans/<id>/`.
- **UI (complete pass, analyzer-clean)**:
  - App entry + theme + provider wiring + disclaimer gate.
  - Shell: Home / My Plants / Learn / History / Settings.
  - Scan flow: capture (camera+gallery, up to 4, subject tags), processing,
    full result screen (quality warnings, identification w/ uncertainty,
    health ring, evidence overlay, causes, care, plant info, follow-up,
    save to history + save to My Plants).
  - My Plants list + detail (notes, history, delete).
  - Learn catalogue + plant detail.
  - History + scan detail (notes, delete).
  - Settings (+ science-fair extras toggle).
  - Science fair demo + Experiment Lab.
- **Docs**: README, architecture, testing, science-fair, ai-model, limitations,
  setup.
- **Android manifest**: `CAMERA` permission, app label "PlantDoctor".
- **App icon**: custom leaf-on-green launcher icons generated to all mipmap
  buckets (`tool/generate_assets.dart`).
- **DB robustness**: `ScanRecord.fromMap` now tolerates both raw JSON strings
  and decoded lists (fixes sqflite/sqflite-ffi read-back difference).

## Verified

- `flutter pub get` – resolves.
- `flutter analyze --no-pub` – **0 issues**.
- `flutter test` – **17/17 pass** (ground-truth engine + classifier honesty +
  multi-image combine + determinism + storage round-trip + education content).
- `flutter build apk --release` – **verified**: 57.1 MB APK built at
  `build/app/outputs/flutter-apk/app-release.apk`.

## Remaining / roadblocks

- **No device/emulator**: on-device manual testing not possible on this machine
  (no KVM; sudo required for desktop toolchain). User must run:
  `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev`
  or connect a physical Android device (`adb devices` then
  `adb install build/app/outputs/flutter-apk/app-release.apk`).
- **Optional stretch**: iOS verification, export/backup, real-photo calibration.