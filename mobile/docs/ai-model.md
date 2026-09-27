# PlantDoctor – The AI model (honesty edition)

PlantDoctor deliberately does **not** use a deep-learning model trained on a
photo dataset. It uses a transparent, deterministic, rule-based pipeline so
that:

1. **Every output is explainable** – the evidence boxes and component weights
   above each measurement say exactly *why* a score looks the way it does.
2. **It cannot overstate itself** – there is no confident-sounding network
   producing a "94% sure this is an X" line. Uncertainty is enforced in code.
3. **It runs fully offline** on modest phones with no model download.

## What the "AI" actually is

### 1. Vision (pure Dart, `image` package)

- **HSV tile labelling** – classify each coarse grid cell as green, yellow/
  lime, brown or dark using fixed hue/saturation/value bands.
- **Plant detection** – connected components of vegetation tiles → plant mask.
- **Measurement** – yellow/brown/dark/coverage fractions, spot & lesion area
  (interior non-green on green background), texture variation,
  Laplacian-variance sharpness, brightness.
- Everything is computed from raw pixel statistics.

### 2. Health reasoning (rule engine)

A small symptom-fingerprint heuristic maps measured signals to ranked, honest
hypotheses ("Possible nutrient-related stress", "Possible fungal-like leaf
symptoms", …). Each hypothesis carries a confidence and a "verify me"
explanation, and supports nutrient notes.

### 3. Identification (morphology heuristics)

Leaf aspect ratio, roundness, edge density and coverage vote on growth-form
groups (monocot-like, broadleaf, succulent, vine, fern). Species suggestions
are looked up from curated morphology tags.

**The honesty cap:** any species-level confidence is `min(score, 0.42)`.
Because the uncertainty threshold is 0.45, the app *always* reports
`uncertain = true` for species – which is the scientifically correct statement
for morphology-only identification from a phone photo.

## The experimental Health Index

Scores 0–100 from five plant-relative components (weights in
`docs/architecture.md`). It is a **software metric**, not a diagnosis. It is
labelled experimental in the UI and its limits are printed in the science-fair
demo.

## Why not tflite / cloud?

| approach | this app |
| --- | --- |
| privacy | photos never leave the device |
| cost | zero |
| explainability | every signal is traceable |
| honesty | cannot hallucinate a convincing-but-wrong disease |
| data | no training set needed, no licensing issues |

## Known limits of the approach

See [`docs/limitations.md`](docs/limitations.md).