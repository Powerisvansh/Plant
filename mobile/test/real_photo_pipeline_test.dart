import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:plantdoctor/models/analysis_models.dart';
import 'package:plantdoctor/services/analysis/analysis_engine.dart';

/// Runs the app's real on-device analysis engine over REAL photographs sampled
/// from the PlantVillage training set.
///
/// These are genuine leaf photos with known ground truth, not the synthetic
/// images the unit tests use, so this exercises the same decode -> downscale ->
/// quality gate -> pixel measurement path a camera capture takes.
void main() {
  const dir = '/tmp/realplants';

  late List<dynamic> entries;

  setUpAll(() {
    final f = File('$dir/manifest.json');
    expect(f.existsSync(), isTrue,
        reason: 'sample the dataset first; see the tool that does it');
    entries = (jsonDecode(f.readAsStringSync()) as List<dynamic>);
  });

  test('the sample set contains both healthy and diseased plants', () {
    expect(entries, isNotEmpty, reason: 'no images were sampled');
    final healthy = entries.where((e) => e['expect_healthy'] == true).length;
    final diseased = entries.length - healthy;
    expect(healthy, greaterThan(0));
    expect(diseased, greaterThan(0),
        reason: 'a set with no diseased leaf proves nothing');
  });

  test('every sampled photo passes the quality gate as a plant photo', () {
    var plantDetected = 0;
    final rejects = <String>[];

    for (final e in entries) {
      final file = File('$dir/${e['file']}');
      expect(file.existsSync(), isTrue, reason: '${e['file']} must be on disk');
      final decoded = img.decodeImage(file.readAsBytesSync());
      expect(decoded, isNotNull, reason: '${e['file']} must decode');

      final prepared = AnalysisEngine.prepare(decoded!);
      final report = AnalysisEngine.checkQuality(prepared);
      if (report.issues.contains(QualityIssue.plantNotDetected)) {
        rejects.add('${e['file']}: no plant detected');
      } else {
        plantDetected++;
      }
    }

    // PlantVillage photos are leaves on plain backgrounds, so the gate should
    // accept them. If it rejects most, the gate is mis-tuned for real photos.
    expect(rejects, isEmpty,
        reason: 'real leaf photos must not be refused by the quality gate');
    expect(plantDetected, entries.length);
  });

  test('diseased leaves measurably differ from healthy leaves', () {
    double avgDamage(List<dynamic> rows) {
      final values = <double>[];
      for (final e in rows) {
        final decoded =
            img.decodeImage(File('$dir/${e['file']}').readAsBytesSync());
        if (decoded == null) continue;
        final a = AnalysisEngine.analyzeSingle(AnalysisEngine.prepare(decoded));
        values.add(a.damagedFraction);
      }
      values.sort();
      return values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    }

    final healthy = entries.where((e) => e['expect_healthy'] == true).toList();
    final diseased = entries.where((e) => e['expect_healthy'] == false).toList();

    final healthyDamage = avgDamage(healthy);
    final diseasedDamage = avgDamage(diseased);

    // ignore: avoid_print
    print('avg damaged fraction  healthy=${healthyDamage.toStringAsFixed(3)}  '
        'diseased=${diseasedDamage.toStringAsFixed(3)}');

    expect(diseasedDamage, greaterThan(healthyDamage),
        reason: 'brown and spotted tissue must measure higher on a diseased leaf');
  });

  test('documents why a pixel-level foliage gate cannot fix overconfidence', () {
    // Measured across the sample set, so the numbers behind this judgement are
    // on record rather than assumed:
    //
    //   real leaf photos : plantCoverage 0.197 .. 0.970, and the most diseased
    //                      one (Potato___Early_blight) has greenFraction 0.008 --
    //                      almost no green at all.
    //   synthetic shape  : plantCoverage 0.176
    //
    // A coverage floor in the narrow band between 0.176 and 0.197 happens to
    // separate these particular samples, but it sits *below* the coverage of
    // every real photo in the set and only 0.02 above the synthetic one. That
    // is not a margin worth shipping: a legitimate photo of a small, distant
    // leaf would be refused. A green-fraction floor is worse -- it would reject
    // the badly diseased real leaf outright.
    //
    // Conclusion recorded here: only a classifier retrained with negatives can
    // fix the overconfidence, so no pixel threshold is applied.
    final covs = <double>[];
    final greens = <double>[];
    for (final e in entries) {
      final decoded =
          img.decodeImage(File('$dir/${e['file']}').readAsBytesSync());
      final a = AnalysisEngine.analyzeSingle(
          AnalysisEngine.prepare(decoded!));
      covs.add(a.plantCoverage);
      greens.add(a.greenFraction);
    }

    final oov = File('$dir/oov/fake_leaf.jpg');
    expect(oov.existsSync(), isTrue, reason: 'the OOV sample must exist');
    final fake = AnalysisEngine.analyzeSingle(AnalysisEngine.prepare(
        img.decodeImage(oov.readAsBytesSync())!));

    final lowestReal = covs.reduce(min);
    // The margin is real but far too narrow to be safe in production.
    expect(fake.plantCoverage, lessThan(lowestReal));
    expect(lowestReal - fake.plantCoverage, lessThan(0.05),
        reason: 'any coverage floor that excludes the synthetic shape would '
            'sit within 5 points of the sparsest real leaf photo');
    expect(greens.reduce(min), lessThan(0.10),
        reason: 'a green floor would reject a genuinely diseased real leaf');
  });

  test('measurements stay inside physical bounds for every photo', () {
    for (final e in entries) {
      final decoded =
          img.decodeImage(File('$dir/${e['file']}').readAsBytesSync());
      final a = AnalysisEngine.analyzeSingle(
          AnalysisEngine.prepare(decoded!));
      final name = '${e['file']}';
      for (final v in [
        a.yellowFraction,
        a.brownFraction,
        a.greenFraction,
        a.spottedFraction,
        a.plantCoverage,
        a.meanBrightness,
      ]) {
        expect(v, inInclusiveRange(0.0, 1.0),
            reason: '$name produced an out-of-range fraction');
      }
      expect(a.damagedFraction, inInclusiveRange(0.0, 1.0));
      expect(a.plantDetected, isTrue, reason: '$name should register as a plant');
    }
  });
test('writes a per-image breakdown of every sampled photo', () {
    final out = StringBuffer();
    for (final e in entries) {
      final decoded =
          img.decodeImage(File('$dir/${e['file']}').readAsBytesSync());
      final prepared = AnalysisEngine.prepare(decoded!);
      final a = AnalysisEngine.analyzeSingle(prepared);
      final health = AnalysisEngine.assess([a]);
      out.writeln(
          '${e['expect_healthy'] == true ? "HEALTHY " : "DISEASED"} '
          '${e['true_class']}\n'
          '    damaged=${a.damagedFraction.toStringAsFixed(3)} '
          'yellow=${a.yellowFraction.toStringAsFixed(3)} '
          'brown=${a.brownFraction.toStringAsFixed(3)} '
          'spotted=${a.spottedFraction.toStringAsFixed(3)}\n'
          '    verdict="${health.overallCondition}"');
    }
    File('/tmp/realplants/RESULTS.txt').writeAsStringSync(out.toString());
    expect(out.toString(), isNotEmpty);
  });

  test('the health report never claims a disease on its own authority',
      () {
    for (final e in entries) {
      final decoded =
          img.decodeImage(File('$dir/${e['file']}').readAsBytesSync());
      final a = AnalysisEngine.analyzeSingle(
          AnalysisEngine.prepare(decoded!));
      final health = AnalysisEngine.assess([a]);

      expect(health.uncertaintyExplanation, isNotEmpty,
          reason: 'a screening result must always state its uncertainty');
      expect(health.safeMedicineGuidance, isNotEmpty,
          reason: 'medicine guidance must carry the safety framing');
      for (final text in [...health.safeMedicineGuidance, ...health.statements]) {
        expect(text.toLowerCase(), isNot(contains('cure')),
            reason: 'no claim of curing anything');
      }
    }
  });
}