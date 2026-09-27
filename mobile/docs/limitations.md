# PlantDoctor – Limitations

These are honest, documented limits of the app. Read them before trusting a
result.

## 1. Not a diagnosis

The Health Index, condition labels and cause suggestions are **visual-only
screening hints**. Many stresses look alike (yellowing can be water, light,
nutrients or age). The app says "hypothesis to verify", not "your plant has X".

## 2. Rule-based vision ≠ deep learning

The engine uses HSV bands and connected components. It is fast, private and
explainable, but less robust than a model trained on large photo datasets:

- Unusual species, strong lighting, glass reflections or heavy texture can
  confuse the green/yellow/brown bands.
- "Yellow" covers lime-green healthy cultivars (some plants *are* yellow).
- Very wide shots with tiny leaves reduce measurement reliability
  (`plantCoverage` is low).

## 3. Identification is capped by design

Species-level confidence never exceeds 0.42 and is *always reported as
uncertain*. That means the app will not confidently name your rare houseplant.
It gives a coarse growth-form suggestion and a ranked list of common candidates
to compare against.

## 4. The science-fair benchmark is not real-world validation

The demo measures the engine on **synthetic seeded leaves**. It demonstrates
internal consistency and honesty, not accuracy on real photographs. Real-world
accuracy would need a curated, ground-truthed photo dataset, which is out of
scope for this project.

## 5. Health Index is experimental

Components and weights are documented but are a design choice, not an
established scale. Real validation (does a lower index predict worse plant
outcomes?) has not been performed.

## 6. Storage & privacy

Everything is local: SQLite + files under the app documents directory. If the
app is uninstalled or data is cleared, saved plants, history and photos are
gone. There is no backup or export yet.

## 7. Platform

Currently Android-first (min SDK 24). The iOS folder is scaffolded but
unverified. Desktop/web builds are not configured.

## 8. Content

Care advice in the Learn section is curated general guidance, not species
science. Always cross-check with reliable regional sources.