# PlantDoctor – Testing

## Unit / integration tests

All tests are ground-truth tests against the **synthetic sample generator**,
which is deterministic per `(seed, effect)` – the same label always produces the
same image, so assertions are reproducible.

```bash
cd mobile
flutter test
```

| group | proves |
| --- | --- |
| healthy leaf | plant detected, green fraction high, index ≥ 70 |
| chlorosis / diseased / spotting | symptom signals measured, causes produced, index ≤ 75 |
| dark / blurry / no-plant | quality gate flags `tooDark` / `tooBlurry` / `plantNotDetected` |
| classifier honesty | always `uncertain`, confidence never above 0.42 |
| multi-image | unused photos (no plant) excluded from summary |
| determinism | same seed+effect ⇒ byte-identical PNG |
| storage round-trip | scan & plant CRUD + attach + notes via `sqflite_common_ffi` |
| education content | tip-of-day deterministic + rotates; all 10 required subjects present; topics resolve by id |

## Manual test checklist

1. **Cold start** – disclaimer dialog shows once when enabled; works offline.
2. **Scan flow** – add up to 4 photos; swap/remove; subject dropdown; analyse.
3. **Quality gate** – dark/blurry photos produce the warning banner.
4. **Results** – identity guess + uncertainty badge, health ring, evidence
   overlay matches tiles, causes, care card, plant info, follow-up sheet.
5. **Save** – history entry appears; "Also save to My Plants" links it.
6. **My Plants** – detail page shows notes + health history rows.
7. **Learn** – all 12 plant cards open detail pages.
8. **Science fair** – Run the benchmark; metrics + confusion matrix render;
   Experiment Lab shows the healthy-vs-diseased table.
9. **Settings** – disclaimer toggle takes effect next cold start; science-fair
   extras switch affects the demo timing card.
10. **Home tip** – "Plant tip of the day" card shows a tip and changes daily.
11. **Learn topics** – all 10 science cards open detail pages with sourced text.

## Instrumentation

`AnalyzeService` records `inference_ms` and image count into
`measuredMetrics`; the science-fair screen shows average inference time under
"Engineering details".