# Model

## What this model is

A **crop and condition screener**, not a species identifier.

| Property | Value |
| --- | --- |
| Architecture | MobileNetV3Small + global average pooling + dense (softmax) |
| Input | 160 x 160 x 3, RGB, values left in 0..255 |
| Classes | 38 crop/condition combinations |
| Crops | 14 (apple, blueberry, cherry, corn, grape, orange, peach, pepper, potato, raspberry, soybean, squash, strawberry, tomato) |
| Parameters | ~1.1 M in the TFLite build |
| Model size | 1,102.6 KB (`plantdoctor_plants.tflite`) |
| Runtime | on-device, via `tflite_flutter`; no network |
| Average inference | 7.7 ms per image, measured on this machine's CPU |

## Measured performance

From `ml/metrics/evaluation_report.json`, produced by
`ml/scripts/evaluate_model.py` against the held-out test split
(8,146 images, never used for training or validation):

| Metric | Value |
| --- | --- |
| Top-1 accuracy | 0.9018 |
| Top-5 accuracy | 0.9915 |
| Macro F1 | 0.8905 |
| Weighted F1 | 0.9024 |

The same numbers are embedded in
`mobile/assets/models/plantdoctor_plants.labels.json` under `metrics`, and the
test `mobile/test/model_bundle_test.dart` fails if they are missing or
improvable, so the app cannot ship without measured figures.

### Class-level spread

Healthy classes and visually distinct diseases score very high; classes that
look alike are the weak ones. This is expected and is why the app shows a
ranked list rather than one confident answer.

Weakest classes on the test split:

| F1 | Precision | Recall | Support | Class |
| --- | --- | --- | --- | --- |
| 0.656 | 0.621 | 0.695 | 210 | Tomato - Target Spot |
| 0.694 | 0.955 | 0.545 | 77 | Corn - Gray leaf spot |
| 0.716 | 0.613 | 0.861 | 252 | Tomato - Two-spotted spider mite |
| 0.743 | 0.828 | 0.673 | 150 | Tomato - Early blight |

Strongest classes include Corn - Common rust (F1 0.994), Squash - Powdery
mildew (0.996), Grape - healthy (0.992) and Corn - healthy (0.991).

### Confidence threshold

The shipped `unknown_threshold` is **0.60**. The rejection trade-off on the
test split:

| Threshold | Rejected | Accuracy on kept |
| --- | --- | --- |
| 0.30 | 1.1% | 0.9083 |
| 0.50 | 8.4% | 0.9405 |
| **0.60** | **13.8%** | **0.9594** |
| 0.80 | 27.2% | 0.9836 |

Below the threshold the app reports the identification as uncertain and shows
the ranked candidates without naming a plant. This is the mechanism that
prevents the old "wrong plant every time" behaviour.

## Preprocessing contract

The exported model has MobileNetV3's `include_preprocessing=True`, so it
rescales internally. Input tensors must therefore carry **raw 0..255 values**,
not 0..1.

This was verified empirically, not assumed: feeding 0..1 produced degenerate
predictions (0/40 correct on `Apple___Apple_scab`, saturating to unrelated
classes), while feeding 0..255 with the training decode pipeline produced
correct predictions. `toModelInput` in `mobile/lib/services/ml/plant_model.dart`
keeps 0..255 and a test asserts it.

## Scope limits

- The model recognises **plants from the 14 crops above and nothing else**.
- It does not identify the 3,918 species in the knowledge database.
- PlantVillage images are single leaves on plain backgrounds. Field photos,
  whole plants, fruit, flowers, seedlings and multiple plants are out of
  distribution and accuracy on them is not measured.
- It cannot tell two individuals of a species apart and does not estimate
  disease severity.
- For anything outside these crops the app says so rather than guessing. There
  is no fallback species name anywhere in the codebase.

## How to rebuild

```bash
cd ml
./.venv/bin/python scripts/train_model.py \
  --max-per-class 400 --epochs 10 --fine-tune-epochs 4 \
  --unfreeze-layers 20 --batch-size 48 --threads 4
./.venv/bin/python scripts/evaluate_model.py
./.venv/bin/python scripts/export_tflite.py
cp export/plantvillage.tflite ../mobile/assets/models/plantdoctor_plants.tflite
cd .. && ./.venv/bin/python ml/scripts/build_model_labels.py
```

Training used a frozen-base phase then a fine-tune of the top 20 base layers
at 1e-5. The fine-tune phase did not beat the frozen phase, so the best
checkpoint is the frozen-epoch-10 model at 0.9040 validation accuracy.
