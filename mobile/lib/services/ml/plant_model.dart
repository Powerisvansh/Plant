import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device classifier loader (TensorFlow Lite).
///
/// The model plus its label file are produced by `ml/export_tflite.py` and
/// shipped under `assets/models/`. When the assets are missing - unit tests, or
/// a build before a model release - [isAvailable] stays false and the app falls
/// back to the (clearly labelled) leaf-shape screening instead. Nothing is
/// faked: with no model the app says the species is unknown.
class PlantModelService {
  PlantModelService._(this.labels, this._interpreter);

  final ModelLabels labels;
  final Interpreter _interpreter;

  static PlantModelService? _instance;
  static bool _attempted = false;
  static Object? lastError;

  static const String modelAsset = 'assets/models/plantdoctor_plants.tflite';
  static const String labelsAsset =
      'assets/models/plantdoctor_plants.labels.json';

  static PlantModelService? get instance => _instance;
  static bool get isAvailable => _instance != null;

  /// Loads the model once per process.
  static Future<PlantModelService?> load({bool forceReload = false}) async {
    if (_attempted && !forceReload) return _instance;
    _attempted = true;
    try {
      final rawLabels = await rootBundle.loadString(labelsAsset);
      final labels =
          ModelLabels.fromJson(jsonDecode(rawLabels) as Map<String, dynamic>);
      final interpreter = await Interpreter.fromAsset(modelAsset);
      _instance = PlantModelService._(labels, interpreter);
      lastError = null;
    } catch (error) {
      lastError = error;
      _instance = null;
    }
    return _instance;
  }

  /// Releases the interpreter (used by tests).
  static void dispose() {
    _instance?._interpreter.close();
    _instance = null;
    _attempted = false;
  }

  /// Runs inference and returns the raw probability vector.
  List<double> classify(img.Image image) {
    final size = labels.inputSize;
    final input = toModelInput(image, size).reshape([1, size, size, 3]);
    final classCount = labels.classes.length;
    final output = List<double>.filled(classCount, 0).reshape([1, classCount]);
    _interpreter.run(input, output);
    final row = (output.first as List).cast<num>().map((v) => v.toDouble());
    final values = row.toList(growable: false);
    // Some exports emit logits; detect an obviously un-normalised vector.
    final sum = values.fold<double>(0, (a, b) => a + b);
    final looksLikeProbabilities =
        values.every((v) => v >= 0 && v <= 1) && (sum - 1).abs() < 0.05;
    return looksLikeProbabilities ? values : softmax(values);
  }

  /// Top-K predictions, highest first.
  List<ModelPrediction> topK(img.Image image, {int k = 5}) {
    final probabilities = classify(image);
    final ranked = <ModelPrediction>[];
    for (var i = 0; i < probabilities.length; i++) {
      ranked.add(ModelPrediction(i, probabilities[i]));
    }
    ranked.sort((a, b) => b.probability.compareTo(a.probability));
    return ranked.take(k).toList(growable: false);
  }

  ModelClass classFor(int index) => labels.classes[index];
}

/// One classifier output.
class ModelPrediction {
  const ModelPrediction(this.index, this.probability);
  final int index;
  final double probability;

  ModelClass? get classInfo {
    final service = PlantModelService.instance;
    if (service == null || index >= service.labels.classes.length) return null;
    return service.labels.classes[index];
  }
}


/// Parsed `plantdoctor_plants.labels.json`.
class ModelLabels {
  const ModelLabels({
    required this.modelKey,
    required this.version,
    required this.architecture,
    required this.inputSize,
    required this.trainedOn,
    required this.classes,
    required this.metrics,
    required this.unknownThreshold,
  });

  final String modelKey;
  final String version;
  final String architecture;
  final int inputSize;
  final String trainedOn;
  final List<ModelClass> classes;

  /// Real measured metrics recorded by `ml/evaluate_model.py`.
  final Map<String, double> metrics;

  /// Below this top-1 probability the app reports "no supported plant
  /// identified" instead of forcing the photo into a known class.
  final double unknownThreshold;

  static ModelLabels fromJson(Map<String, dynamic> json) {
    final rawClasses = (json['classes'] as List?) ?? const [];
    return ModelLabels(
      modelKey: json['model_key'] as String? ?? 'unknown',
      version: json['version'] as String? ?? '0',
      architecture: json['architecture'] as String? ?? 'unknown',
      inputSize: (json['input_size'] as num?)?.toInt() ?? 224,
      trainedOn: json['trained_on'] as String? ?? 'unknown',
      classes: rawClasses
          .map((c) => ModelClass.fromJson(c as Map<String, dynamic>))
          .toList(growable: false),
      metrics: ((json['metrics'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      ),
      unknownThreshold:
          (json['unknown_threshold'] as num?)?.toDouble() ?? 0.35,
    );
  }
}

/// One trained class: a crop (and optionally a health condition).
class ModelClass {
  const ModelClass({
    required this.index,
    required this.classLabel,
    required this.crop,
    required this.condition,
    required this.healthy,
    this.plantSlug,
    this.scientificName,
  });

  final int index;
  final String classLabel;
  final String crop;
  final String? condition;
  final bool healthy;

  /// Slug of the matching row in the bundled knowledge database, when known.
  final String? plantSlug;
  final String? scientificName;

  static ModelClass fromJson(Map<String, dynamic> json) => ModelClass(
        index: (json['index'] as num).toInt(),
        classLabel: json['class_label'] as String? ?? '',
        crop: json['crop'] as String? ?? '',
        condition: json['condition'] as String?,
        healthy: json['healthy'] as bool? ?? false,
        plantSlug: json['plant_slug'] as String?,
        scientificName: json['plant_scientific_name'] as String?,
      );
}

/// Numerically stable softmax (used when a model exports logits).
List<double> softmax(List<double> logits) {
  if (logits.isEmpty) return const [];
  final maxLogit = logits.reduce(math.max);
  final exps = logits.map((v) => math.exp(v - maxLogit)).toList();
  final sum = exps.reduce((a, b) => a + b);
  if (sum <= 0) return List<double>.filled(logits.length, 0);
  return exps.map((v) => v / sum).toList(growable: false);
}

/// Converts a prepared image into the float32 input tensor the model expects
/// (values stay in 0..255 - normalisation is baked into the exported model).
Float32List toModelInput(img.Image image, int size) {
  final resized = img.copyResize(
    image,
    width: size,
    height: size,
    interpolation: img.Interpolation.linear,
  );
  final buffer = Float32List(size * size * 3);
  var i = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final pixel = resized.getPixel(x, y);
      buffer[i++] = pixel.r.toDouble();
      buffer[i++] = pixel.g.toDouble();
      buffer[i++] = pixel.b.toDouble();
    }
  }
  return buffer;
}
