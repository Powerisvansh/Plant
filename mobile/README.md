# PlantDoctor

**Understand your plants. Protect their health.**

PlantDoctor is an offline-first Android app that gives *AI-assisted, visual-only*
hints about plant health. Take 1–4 photos of a plant and it screens leaf colour,
spots, damage and shape – entirely on the device. It also identifies the likely
plant family from leaf shape (honestly labelled as a guess), suggests care
steps, tracks plants over time, and includes a built-in, reproducible
science-fair demo so the accuracy claims can be verified live.

> **Important:** PlantDoctor is a screening tool, not a laboratory diagnosis.
> Everything it says is a hypothesis to verify.

## What it does

| Feature | Notes |
| --- | --- |
| Photo check-up | Camera or gallery, 1–4 photos per scan |
| Quality gate | Warns on dark / blurry / no-plant / obstructed photos |
| Health screening | Measures yellow (chlorosis), brown (necrosis), irregular spots, coverage – with on-photo evidence boxes |
| Health Index (0–100) | Experimental software metric with documented weights; **not** a standard |
| Identification | Morphology-based guess of growth-form (monocot / broadleaf / succulent / vine / fern) + ranked species suggestions, confidence capped so it never claims certainty it can't have |
| Care & plant info | Local curated guide for 12 common plants |
| Learn | Plant-science topics (photosynthesis, nutrition, diseases, pests, water stress, soil, how the analysis works, AI limits) + plant catalogue |
| Daily tip | A rotating, verified plant-care tip on Home |
| My Plants | Save plants and follow their health history over time |
| History | Timeline of every saved check-up with photos and notes |
| Science fair demo | 42 labelled synthetic cases analysed live with the same engine; real accuracy / precision / recall / F1 / confusion matrix, plus an Experiment Lab |
| Privacy | Runs fully offline. Photos are stored locally and never uploaded. |

## Architecture

- **Flutter 3.47+ / Android-first** (min SDK 24). Fully local, no backend.
- **Pure-Dart vision** with the `image` package:
  - HSV tile classification (green / yellow / brown / dark)
  - connected-component leaf detection and damage clustering
  - Laplacian-variance blur metric, mean-luminance darkness metric
- **Storage:** SQLite (`sqflite`) for scans & plants, `SharedPreferences` for settings, image files under the app documents directory.
- **Honesty by design:** species confidence is capped at 0.42 (below the 0.45
  certainty threshold), the index is called "experimental", and the science-fair
  demo can only fail honestly.

See [`docs/architecture.md`](docs/architecture.md), [`docs/ai-model.md`](docs/ai-model.md),
and [`docs/limitations.md`](docs/limitations.md) for details.

**Legal documents** (owner: Vansh Dhiman · brand: VanshDev):
[Privacy Policy](docs/legal/PRIVACY_POLICY.md),
[Terms & Conditions](docs/legal/TERMS_AND_CONDITIONS.md),
[AI Disclaimer](docs/legal/AI_DISCLAIMER.md),
[Data Policy](docs/legal/DATA_POLICY.md).

## Getting started

Requirements: Flutter 3.47+, Android SDK (API 34+). See [`docs/setup.md`](docs/setup.md).

```bash
cd mobile
flutter pub get
flutter run                # on a connected Android device
flutter test               # engine ground-truth + education tests
flutter build apk --release
```

The release APK is produced at `build/app/outputs/flutter-apk/app-release.apk`
(≈57 MB; includes the `image` package analysis toolkit).

## Repository layout

```
mobile/
  lib/
    core/          constants, theme, formatting helpers
    models/        analysis + scan data models
    services/      analysis engine, classifier, plant DB, storage, science fair
    state/         ChangeNotifier controllers
    screens/       home, scan, my plants, learn, history, settings, science fair
    widgets/       health ring, stat cards, evidence overlay, ...
  test/            synthetic ground-truth + honesty tests
  tool/            code generation helpers
  docs/            this project's documentation
```

## License

Educational project. Data about plants is curated from commonly-known care
guidance and is provided "as is".