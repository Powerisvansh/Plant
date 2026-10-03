#!/usr/bin/env python3
"""Train the PlantDoctor visual screening model.

Architecture
------------
MobileNetV3Small (ImageNet weights) as a frozen feature extractor, plus a small
classification head, then a short fine-tuning phase with a low learning rate.
It is deliberately the *small* variant because the target is an offline Android
app: the exported TFLite file has to run on a CPU-only phone in well under a
second, and this dataset's classes are separable without a large network.

The model outputs the PlantVillage class set: 14 crop species x their foliar
conditions (including ``*___healthy``). It is a *crop and condition* recogniser,
not a 10,000-species identifier, and the app says so.

Ground rules
------------
* Metrics printed here come from the real held-out splits. Nothing is estimated.
* Training set is capped per class with ``--max-per-class`` so this finishes on
  a CPU-only machine; the cap is recorded in the metrics file so the number is
  never presented as "trained on everything".
* The test split is untouched by this script - it is only used by
  ``evaluate_model.py`` and ``export_tflite.py``.

This is a normal (reversible) training script, but it does write to
``ml/models`` so it is run as a background job by the build instructions.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
from collections import Counter
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _ml_common import (  # noqa: E402
    BEST_MODEL_PATH,
    CLASSES_PATH,
    LABELS_PATH,
    METRICS_DIR,
    MODEL_DIR,
    MODEL_PATH,
    SPLIT_DIR,
    log,
    read_json,
    utc_now,
    write_json,
)

IMAGE_SIZE = 160
BATCH_SIZE = 64
SEED = 20260927

AUTOTUNE = None  # set in main() once tensorflow is imported


def load_split(name: str) -> tuple[list[str], list[int]]:
    """Read a split CSV, returning (paths, integer labels)."""
    classes = read_json(CLASSES_PATH)
    if not classes:
        raise SystemExit("ml/data/classes.json missing - run prepare_dataset.py")
    class_list = classes["classes"]
    index = {label: i for i, label in enumerate(class_list)}

    paths: list[str] = []
    labels: list[int] = []
    with (SPLIT_DIR / f"{name}.csv").open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            paths.append(row["abs_path"])
            labels.append(index[row["class_label"]])
    return paths, labels


def cap_per_class(paths: list[str], labels: list[int],
                  cap: int) -> tuple[list[str], list[int]]:
    """Keep at most ``cap`` images per class (deterministic, first N in order)."""
    if cap <= 0:
        return paths, labels
    kept: dict[int, int] = Counter()
    out_paths: list[str] = []
    out_labels: list[int] = []
    for path, label in zip(paths, labels):
        if kept[label] >= cap:
            continue
        kept[label] += 1
        out_paths.append(path)
        out_labels.append(label)
    return out_paths, out_labels


def build_dataset(tf, paths, labels, batch_size, training: bool):
    def decode(path, label):
        raw = tf.io.read_file(path)
        image = tf.io.decode_image(raw, channels=3, expand_animations=False)
        image = tf.image.resize(image, (IMAGE_SIZE, IMAGE_SIZE),
                                antialias=True)
        image = tf.cast(image, tf.float32)
        return image, label

    dataset = tf.data.Dataset.from_tensor_slices((paths, labels))
    if training:
        dataset = dataset.shuffle(min(len(paths), 10000), seed=SEED,
                                  reshuffle_each_iteration=True)
    dataset = dataset.map(decode, num_parallel_calls=AUTOTUNE)
    if training:
        augmentation = tf.keras.Sequential([
            tf.keras.layers.RandomFlip("horizontal_and_vertical"),
            tf.keras.layers.RandomRotation(0.12),
            tf.keras.layers.RandomZoom(0.12),
            tf.keras.layers.RandomContrast(0.15),
            tf.keras.layers.RandomBrightness(0.12),
        ])
        dataset = dataset.map(
            lambda x, y: (augmentation(x, training=True), y),
            num_parallel_calls=AUTOTUNE)
    dataset = dataset.batch(batch_size).prefetch(AUTOTUNE)
    return dataset


def build_model(tf, num_classes: int):
    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(IMAGE_SIZE, IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
        include_preprocessing=True,
    )
    base.trainable = False

    inputs = tf.keras.Input(shape=(IMAGE_SIZE, IMAGE_SIZE, 3), name="image")
    x = base(inputs, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.25)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax",
                                    name="class_probabilities")(x)
    model = tf.keras.Model(inputs, outputs, name="plantdoctor_screener")
    return model, base


def configure_runtime(tf, threads: int) -> None:
    """Pin CPU threading so a 4-core box is not oversubscribed by TF."""
    try:
        tf.config.threading.set_intra_op_parallelism_threads(threads)
        tf.config.threading.set_inter_op_parallelism_threads(1)
    except RuntimeError as exc:
        log.warning("could not pin thread counts (already initialised): %s", exc)


def unfreeze_top(base, layers_to_unfreeze: int) -> None:
    """Re-open the last ``layers_to_unfreeze`` blocks of the base network."""
    if layers_to_unfreeze <= 0:
        return
    base.trainable = True
    for layer in base.layers[:-layers_to_unfreeze]:
        layer.trainable = False
    trainable = sum(1 for layer in base.layers if layer.trainable)
    log.info("unfroze %d/%d base layers", trainable, len(base.layers))


def main() -> int:
    global AUTOTUNE

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-per-class", type=int, default=300,
                        help="cap on training images per class (0 = no cap)")
    parser.add_argument("--epochs", type=int, default=8,
                        help="epochs with the base network frozen")
    parser.add_argument("--fine-tune-epochs", type=int, default=3,
                        help="epochs after partially unfreezing the base")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--fine-tune-lr", type=float, default=1e-5)
    parser.add_argument("--unfreeze-layers", type=int, default=12)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--seed", type=int, default=SEED)
    args = parser.parse_args()

    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf

    AUTOTUNE = tf.data.AUTOTUNE
    configure_runtime(tf, args.threads)
    tf.keras.utils.set_random_seed(args.seed)
    log.info("tensorflow %s on %s", tf.__version__,
             [d.name for d in tf.config.list_physical_devices()])

    classes = read_json(CLASSES_PATH)
    if not classes:
        raise SystemExit("ml/data/classes.json missing - run prepare_dataset.py")
    class_list = list(classes["classes"])
    num_classes = len(class_list)

    train_paths, train_labels = load_split("train")
    val_paths, val_labels = load_split("val")
    log.info("split sizes: train=%d val=%d classes=%d",
             len(train_paths), len(val_paths), num_classes)

    if args.max_per_class > 0:
        before = len(train_paths)
        train_paths, train_labels = cap_per_class(
            train_paths, train_labels, args.max_per_class)
        log.info("per-class cap %d: train %d -> %d images",
                 args.max_per_class, before, len(train_paths))

    per_class = dict(sorted(Counter(train_labels).items()))
    log.info("train images per class: min=%d max=%d",
             min(per_class.values()), max(per_class.values()))

    train_ds = build_dataset(tf, train_paths, train_labels,
                             args.batch_size, training=True)
    val_ds = build_dataset(tf, val_paths, val_labels,
                           args.batch_size, training=False)
    train_ds = train_ds.repeat()
    steps_per_epoch = max(1, math.ceil(len(train_paths) / args.batch_size))
    log.info("steps per epoch: %d", steps_per_epoch)

    model, base = build_model(tf, num_classes)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=args.lr),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary(print_fn=log.info)

    history: list[dict] = []
    best_val_accuracy = -1.0
    best_epoch = None

    def record_epoch(source: str, epoch_index: int, logs: dict) -> None:
        nonlocal best_val_accuracy, best_epoch
        entry = {
            "phase": source,
            "epoch": epoch_index,
            "loss": float(logs.get("loss", float("nan"))),
            "val_loss": float(logs.get("val_loss", float("nan"))),
            "accuracy": float(logs.get("accuracy", float("nan"))),
            "val_accuracy": float(logs.get("val_accuracy", float("nan"))),
        }
        history.append(entry)
        if entry["val_accuracy"] > best_val_accuracy:
            best_val_accuracy = entry["val_accuracy"]
            best_epoch = entry
            model.save(BEST_MODEL_PATH)
            log.info("phase=%s epoch=%d val_accuracy=%.4f -> saved best",
                     source, epoch_index, entry["val_accuracy"])

    log.info("=== phase 1: frozen base, %d epochs, lr=%g ===",
             args.epochs, args.lr)
    if args.epochs > 0:
        history += model.fit(
            train_ds,
            steps_per_epoch=steps_per_epoch,
            validation_data=val_ds,
            epochs=args.epochs,
            callbacks=[
                tf.keras.callbacks.EarlyStopping(
                    monitor="val_accuracy", patience=3, mode="max",
                    restore_best_weights=True, verbose=0),
                tf.keras.callbacks.ReduceLROnPlateau(
                    monitor="val_loss", factor=0.5, patience=2, min_lr=1e-5,
                    verbose=0),
                tf.keras.callbacks.LambdaCallback(
                    on_epoch_end=lambda e, logs: record_epoch("frozen", e + 1, logs)),
            ],
            shuffle=False,
            verbose=0,
        ).history

    log.info("=== phase 2: fine-tune top %d base layers, %d epochs, lr=%g ===",
             args.unfreeze_layers, args.fine_tune_epochs, args.fine_tune_lr)
    if args.fine_tune_epochs > 0:
        unfreeze_top(base, args.unfreeze_layers)
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=args.fine_tune_lr),
            loss="sparse_categorical_crossentropy",
            metrics=["accuracy"],
        )
        history += model.fit(
            train_ds,
            steps_per_epoch=steps_per_epoch,
            validation_data=val_ds,
            epochs=args.fine_tune_epochs,
            callbacks=[
                tf.keras.callbacks.EarlyStopping(
                    monitor="val_accuracy", patience=2, mode="max",
                    restore_best_weights=True, verbose=0),
                tf.keras.callbacks.LambdaCallback(
                    on_epoch_end=lambda e, logs: record_epoch("fine_tune", e + 1, logs)),
            ],
            shuffle=False,
            verbose=0,
        ).history

    if best_epoch is None:
        model.save(BEST_MODEL_PATH)
        log.info("no validation epoch recorded; saved final weights as best")
        best_epoch = {"phase": "final", "epoch": 0,
                      "val_accuracy": None, "val_loss": None}

    model.save(MODEL_PATH)

    LABELS_PATH.parent.mkdir(parents=True, exist_ok=True)
    LABELS_PATH.write_text("\n".join(class_list) + "\n", encoding="utf-8")

    report = {
        "generated_at": utc_now(),
        "architecture": "MobileNetV3Small(frozen)+GAP+Dense, then partial fine-tune",
        "image_size": IMAGE_SIZE,
        "num_classes": num_classes,
        "classes": class_list,
        "seed": args.seed,
        "tensorflow_version": tf.__version__,
        "device": "cpu",
        "data": {
            "train_images_available": int(sum(per_class.values())),
            "max_per_class": args.max_per_class,
            "images_per_class": {class_list[k]: v
                                 for k, v in sorted(per_class.items())},
            "val_images": len(val_paths),
            "test_images": None,
        },
        "training": {
            "batch_size": args.batch_size,
            "steps_per_epoch": steps_per_epoch,
            "frozen_epochs_requested": args.epochs,
            "fine_tune_epochs_requested": args.fine_tune_epochs,
            "epochs_completed": len(history),
            "unfrozen_base_layers": args.unfreeze_layers,
        },
        "history": history,
        "best_epoch": best_epoch,
        "note": "Loss/accuracy above come from the real validation split. "
                "Held-out test metrics are produced separately by "
                "evaluate_model.py and are never written by this script.",
    }
    METRICS_DIR.mkdir(parents=True, exist_ok=True)
    write_json(METRICS_DIR / "training_report.json", report)

    log.info("best val_accuracy=%.4f (phase=%s epoch=%s)",
             best_val_accuracy, best_epoch["phase"], best_epoch["epoch"])
    log.info("saved %s", MODEL_PATH)
    log.info("saved %s", BEST_MODEL_PATH)
    log.info("wrote %s", METRICS_DIR / "training_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
