#!/usr/bin/env python
"""Run the bundled TFLite classifier over real sampled leaf photos.

Mirrors the app's own preprocessing exactly (``plant_model.dart``):
160x160 linear resize, RGB, float32, values left in 0..255 because the
exported model has normalisation baked in.

Purpose: confirm the shipped model actually recognises real photographs, and
check whether it catches the cases the pixel engine mis-screened.
"""
import json
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

import numpy as np
import tensorflow as tf
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SAMPLES = Path("/tmp/realplants")
MODEL = REPO / "mobile/assets/models/plantdoctor_plants.tflite"
LABELS = REPO / "mobile/assets/models/plantdoctor_plants.labels.json"
SIZE = 160

labels_doc = json.loads(LABELS.read_text())
classes = [c["class_label"] for c in labels_doc["classes"]]
threshold = float(labels_doc.get("unknown_threshold", 0.60))
def preprocess(path: Path) -> np.ndarray:
    """Match toModelInput(): RGB, 0..255 floats, no normalisation."""
    im = Image.open(path).convert("RGB").resize((SIZE, SIZE), Image.BILINEAR)
    return np.asarray(im, dtype=np.float32).reshape(1, SIZE, SIZE, 3)


def main() -> int:
    entries = json.loads((SAMPLES / "manifest.json").read_text())
    interp = tf.lite.Interpreter(model_path=str(MODEL))
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()[0]

    rows, correct, named = [], 0, 0
    for e in entries:
        interp.set_tensor(inp["index"], preprocess(SAMPLES / e["file"]))
        interp.invoke()
        probs = interp.get_tensor(out["index"])[0]
        top = int(np.argmax(probs))
        p = float(probs[top])
        predicted = classes[top]
        above = p >= threshold

        # Does the model's crop agree with the photo's true crop?
        true_crop = e["true_class"].split("___")[0].lower()
        pred_crop = predicted.split("___")[0].lower()
        crop_ok = true_crop in pred_crop or pred_crop in true_crop

        # Does the predicted condition match (healthy vs not)?
        true_healthy = bool(e["expect_healthy"])
        pred_healthy = predicted.endswith("healthy")
        cond_ok = true_healthy == pred_healthy

        if crop_ok:
            correct += 1
        if above:
            named += 1

        rows.append(
            f"{'HEALTHY ' if true_healthy else 'DISEASED'} {e['true_class']}\n"
            f"    predicted  : {predicted}  ({p:.1%})"
            f"{'  [named]' if above else '  [under 45% floor -> uncertain]'}\n"
            f"    crop match : {'YES' if crop_ok else 'no '}"
            f"   healthy/diseased match: {'YES' if cond_ok else 'no'}"
        )

    # ------------------------------------------------ out-of-distribution check
    # A model that names a species for something it has never seen is worse than
    # useless here, so this is checked explicitly rather than assumed.
    oov_dir = SAMPLES / "oov"
    oov_rows, oov_named = [], 0
    if oov_dir.exists():
        for f in sorted(oov_dir.glob("*.jpg")):
            interp.set_tensor(inp["index"], preprocess(f))
            interp.invoke()
            probs = interp.get_tensor(out["index"])[0]
            top = int(np.argmax(probs))
            p = float(probs[top])
            above = p >= threshold
            if above:
                oov_named += 1
            oov_rows.append(
                f"{f.name:20} -> {classes[top]}  ({p:.1%})"
                f"{'  [NAMED - overconfident]' if above else '  [uncertain - correct]'}")

    report = "\n".join(rows)
    print(report)
    print("\n" + "=" * 60)
    print(f"crop correct      : {correct}/{len(entries)}")
    print(f"named a species   : {named}/{len(entries)} (threshold {threshold:.0%})")
    print(f"left uncertain    : {len(entries) - named}/{len(entries)}")
    if oov_rows:
        print("\nOUT-OF-DISTRIBUTION (must NOT be named):")
        for r in oov_rows:
            print(f"  {r}")
        print(f"  overconfident   : {oov_named}/{len(oov_rows)}")
        (SAMPLES / "MODEL_RESULTS.txt").write_text(
            report + "\n\nOOV:\n" + "\n".join(oov_rows))
    else:
        (SAMPLES / "MODEL_RESULTS.txt").write_text(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())