import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:plantdoctor/models/analysis_models.dart';
import 'package:plantdoctor/services/analysis/analysis_engine.dart';
import 'package:plantdoctor/services/identification/plant_classifier.dart';
import 'package:plantdoctor/services/synthetic_samples.dart';

void main() {
  LeafAnalysis measure(img.Image im) => AnalysisEngine.analyzeSingle(im);
  ImageQualityReport quality(img.Image im) => AnalysisEngine.checkQuality(im);

  group('Synthetic ground truth @ AnalysisEngine', () {
    test('healthy leaf: detected as plant, healthy grade', () {
      final im = SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.healthy);
      final a = measure(im);
      final idx = AnalysisEngine.computeIndex([a]);
      expect(a.plantDetected, isTrue);
      expect(a.greenFraction, greaterThan(0.10));
      expect(idx.score, greaterThanOrEqualTo(70));
      expect(idx.grade, anyOf(HealthGrade.excellent, HealthGrade.good));
    });

    test('chlorosis leaf: yellow indicators detected, lower index', () {
      final im = SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.chlorosis);
      final a = measure(im);
      final idx = AnalysisEngine.computeIndex([a]);
      expect(a.yellowFraction, greaterThan(0.03));
      expect(idx.score, lessThanOrEqualTo(75));
    });

    test('diseased leaf: brown/spot indicators detected', () {
      final im = SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.diseased);
      final a = measure(im);
      expect(a.brownFraction + a.spottedFraction, greaterThan(0.02),
          reason: 'brown damage should be measurable');
      final report = AnalysisEngine.assess([a]);
      expect(report.possibleCauses, isNotEmpty);
      expect(report.safeCareGuidance, isNotEmpty,
          reason: 'disease screening should include concrete care steps');
      expect(report.safeMedicineGuidance, isNotEmpty,
          reason: 'treatment results should include label-safe medicine warnings');
      expect(report.warningFlags, isNotEmpty,
          reason: 'the app should warn when treatment or dosage is uncertain');
    });

    test('spotting leaf: spotting measured', () {
      final im = SyntheticSamples.leaf(seed: 22, effect: SymptomEffect.spotting);
      final a = measure(im);
      expect(a.spottedFraction, greaterThan(0.005));
    });

    test('dark image: dark fraction high and quality flags dark', () {
      final im = SyntheticSamples.leaf(
        seed: 11,
        effect: SymptomEffect.diseased,
        darkness: 0.15,
      );
      final q = quality(im);
      final a = measure(im);
      expect(q.issues, contains(QualityIssue.tooDark));
      expect(a.darkFraction, greaterThan(0.4));
    });

    test('blurry image: quality flags blurry', () {
      final im = SyntheticSamples.leaf(
        seed: 11,
        effect: SymptomEffect.healthy,
        blur: true,
      );
      final q = quality(im);
      expect(q.issues, contains(QualityIssue.tooBlurry));
    });

    test('no-plant scene: flagged plantNotDetected', () {
      final im = SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.noPlant);
      final q = quality(im);
      final a = measure(im);
      expect(q.issues, contains(QualityIssue.plantNotDetected));
      expect(a.plantDetected, isFalse);
    });

    test('healthy leaf quality is usable', () {
      final im = SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.healthy);
      final q = quality(im);
      expect(q.usable, isTrue);
      expect(q.issues, isEmpty);
    });
  });

  group('PlantClassifier honesty', () {
    test('returns candidates and may be uncertain, never inflated', () {
      final im = SyntheticSamples.leaf(seed: 33, effect: SymptomEffect.healthy);
      final a = measure(im);
      final result = PlantClassifier.classify([a]);
      expect(result.groupLabel, isNotEmpty);
      expect(result.uncertain, isTrue,
          reason: 'morphology alone must not confirm a species');
      for (final c in result.candidates) {
        expect(c.confidence, lessThanOrEqualTo(0.42));
      }
    });
  });

  group('Multi-image combine', () {
    test('assess uses only plant-bearing photos', () {
      final healthy = measure(
        SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.healthy),
      );
      final bad = measure(
        SyntheticSamples.leaf(seed: 11, effect: SymptomEffect.noPlant),
      );
      final report = AnalysisEngine.assess([healthy, bad]);
      expect(report.statements.first, contains('Based on 1 of 2 photo(s)'));
    });
  });

  test('synthetic samples are deterministic per seed', () {
    final a = SyntheticSamples.leaf(seed: 7, effect: SymptomEffect.diseased);
    final b = SyntheticSamples.leaf(seed: 7, effect: SymptomEffect.diseased);
    expect(img.encodePng(a), img.encodePng(b));
  });
}