# PlantDoctor – Science-fair demo

## The question

*How accurately can a simple, rule-based, on-device image-analysis app tell a
healthy-looking plant from a plant with visible stress signs?*

## The method

1. **Synthetic test set.** A generator draws realistic leaves (ellipse shapes,
   gradients, veins, blur, darkening) with a seeded random stream. Each case
   belongs to one of 7 conditions:

   | label | meaning | expected |
   |---|---|---|
   | `healthy` | clean green leaves | healthy |
   | `spotting` | brown speckles on leaves | affected |
   | `chlorosis` | yellowing throughout | affected |
   | `diseased` | brown lesions + yellowing | affected |
   | `dark` | photo shot too dark | affected |
   | `blurry` | out-of-focus photo | healthy (un-readable) |
   | `no_plant` | frame with no plant | rejected |

2. **Benchmark.** 7 labels × 6 seeds = **42 cases**. Each is run through the
   **same `AnalysisEngine`** the app uses for real photos. Nothing is
   pre-computed or tuned after the fact – the numbers are live measurements.

3. **Decision rule.** "Affected" is reported when the experimental Health Index
   is below 70. `no_plant` cases instead check the rejections ("no plant
   detected").

4. **Metrics.** Accuracy, precision, recall, F1, a 2×2 confusion matrix,
   accuracy per photo condition (clear / blurry / dark / occlusion), which
   cases were right and which were wrong, and average inference time.

## Why this is honest

- The synthetic set is built from clearly visible symptoms, yet the app still
  reports its misses (false negatives) out loud.
- The species-identification module is never scored here, because morphology
  alone cannot confirm species – the app says "uncertain" instead.
- The Health Index is openly described as experimental, with its component
  weights documented.

## Reproduce it live

Open the app → **Science fair demo** → **Run the benchmark**. The Experiment
Lab page additionally measures one healthy vs one diseased leaf side by side.

## What it can't tell you

This benchmark measures the app's *internal honesty and responsiveness* on a
generated set. It is **not** evidence about real-world accuracy: real photos
vary enormously (light, species, distance). Real-world validation would require
a curated photo dataset – see `docs/limitations.md`.