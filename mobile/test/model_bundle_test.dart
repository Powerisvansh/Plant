import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plantdoctor/models/knowledge_models.dart';
import 'package:plantdoctor/services/ml/plant_model.dart';

/// These tests guard the two contracts that silently destroy the model when
/// they break: the preprocessing the interpreter was exported with, and the
/// mapping from a model class to a real plant record.
void main() {
  test('bundled model and labels are both present', () {
    expect(File('assets/models/plantdoctor_plants.tflite').existsSync(),
        isTrue,
        reason: 'the TFLite model must ship inside the APK');
    expect(File('assets/models/plantdoctor_plants.labels.json').existsSync(),
        isTrue);
    expect(File('assets/plant_knowledge/plantdoctor.db').existsSync(), isTrue,
        reason: 'the knowledge base must ship inside the APK');
  });

  test('labels carry measured metrics, not placeholders', () {
    final json = File('assets/models/plantdoctor_plants.labels.json')
        .readAsStringSync();
    // Decoding through the real model service keeps this in step with the app.
    final labels = ModelLabels.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(labels.classes.length, 38);
    expect(labels.metrics['top1_accuracy'], isNotNull,
        reason: 'metrics must come from evaluate_model.py, not be invented');
    expect(labels.metrics['top1_accuracy'] as double, greaterThan(0.8));
    expect(labels.inputSize, 160);
    expect(labels.unknownThreshold, greaterThan(0.0));
  });

  test('every class resolves to a real plant and reports its true scope', () {
    final labels = ModelLabels.fromJson(
      jsonDecode(File('assets/models/plantdoctor_plants.labels.json')
              .readAsStringSync()) as Map<String, dynamic>,
    );
    for (final c in labels.classes) {
      expect(c.plantSlug, isNotNull,
          reason: '${c.classLabel} has no plant_slug; it must link to a real '
              'record instead of guessing a species');
      expect(c.scientificName, isNotNull);
      expect(c.plantSlug, isNotEmpty);
    }
    expect(labels.classes.map((c) => c.classLabel).toSet().length, 38,
        reason: 'class labels must be unique so indices map 1:1');
  });

  test('healthy and diseased variants share one plant slug', () {
    final labels = ModelLabels.fromJson(
      jsonDecode(File('assets/models/plantdoctor_plants.labels.json')
              .readAsStringSync()) as Map<String, dynamic>,
    );
    final byCrop = <String, Set<String>>{};
    for (final c in labels.classes) {
      byCrop.putIfAbsent(c.crop, () => {}).add(c.plantSlug!);
    }
    byCrop.forEach((crop, slugs) {
      expect(slugs.length, 1,
          reason: '$crop maps to $slugs; all its conditions must be the same '
              'plant species');
    });
    expect(byCrop.keys.length, 14,
        reason: 'PlantVillage covers 14 crops; the app must not imply more');
  });

  test('toModelInput keeps raw 0..255 values', () {
    final image = img.Image(width: 8, height: 8);
    img.fill(image, color: img.ColorRgb8(10, 200, 30));
    final input = toModelInput(image, 4);
    expect(input.length, 4 * 4 * 3);
    // The exported MobileNetV3 has include_preprocessing=True, which rescales
    // internally. Feeding already-normalised 0..1 values was measured to break
    // predictions, so this asserts the un-normalised contract explicitly.
    expect(input[0], closeTo(10, 1));
    expect(input[1], closeTo(200, 1));
    expect(input[2], closeTo(30, 1));
  });

  test('a KnowledgePlant keeps unknown toxicity distinct from safe', () {
    const unknown = KnowledgePlant(
      id: 1,
      slug: 'example',
      canonicalName: 'Example example',
      scientificName: 'Example example',
      authorship: '',
      family: 'Exampleaceae',
      genus: 'Example',
      taxonomicStatus: 'ACCEPTED',
      toxicityStatus: 'UNKNOWN',
      verificationStatus: 'UNVERIFIED',
    );
    expect(unknown.toxicityKnown, isFalse,
        reason: 'UNKNOWN must never be presented as safe');
    expect(unknown.displayName, isNotEmpty);
  });
}
