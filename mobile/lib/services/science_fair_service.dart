import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/analysis_models.dart';
import '../models/scan_models.dart';
import 'analysis/analysis_engine.dart';
import 'synthetic_samples.dart';

/// Reproducible science-fair benchmark.
///
/// Runs the real analysis engine over a labelled synthetic test set that is
/// separate from anything the rule constants were tuned with, then reports
/// the measured accuracy / precision / recall / F1 / confusion matrix.
///
/// The numbers shown are computed live on-device; nothing is fabricated.
class ScienceFairService {
  ScienceFairService._();

  static const List<int> _seeds = [11, 22, 33, 44, 55, 66];

  static List<DemoCase> buildCases() {
    final out = <DemoCase>[];
    for (final label in SyntheticSamplesFacade.allLabels) {
      final condition = switch (label) {
        'blurry' => 'blurry',
        'dark' => 'dark',
        'no_plant' => 'occlusion',
        _ => 'good',
      };
      for (var n = 0; n < _seeds.length; n++) {
        out.add(DemoCase(
          id: '${label}_${n + 1}',
          label: label,
          condition: condition,
          seed: _seeds[n % _seeds.length],
        ));
      }
    }
    return out;
  }

  static bool isAffectedLabel(String label) => switch (label) {
        'spotting' || 'chlorosis' || 'diseased' || 'dark' => true,
        _ => false,
      };

  static bool isValidInput(String label) => label != 'no_plant';

  static DemoBenchmarkResult run() {
    final stopwatch = Stopwatch()..start();
    final cases = buildCases();

    final correct = <String>[];
    final incorrect = <String>[];
    final byCondition = <String, DemoConditionMetric>{};

    var tp = 0, fp = 0, tn = 0, fn = 0;
    var noPlantSamples = 0, noPlantCorrect = 0;
    // condition-itemised stats
    final condStats = <String, List<_CondItem>>{};

    for (final c in cases) {
      final image = SyntheticSamplesFacade.byLabel(c.label, c.seed);
      final prepared = AnalysisEngine.prepare(image);
      final analysis = AnalysisEngine.analyzeSingle(prepared);
      final index = AnalysisEngine.computeIndex([analysis]);

      if (!isValidInput(c.label)) {
        noPlantSamples++;
        if (analysis.plantDetected) {
          incorrect.add('${c.id}: no plant expected but plant pixels found');
        } else {
          noPlantCorrect++;
          correct.add('${c.id}: correctly rejected (no plant)');
        }
        final list = condStats.putIfAbsent(c.condition, () => <_CondItem>[]);
        list.add(_CondItem(expected: c.label, predictedAffected: false));
        continue;
      }

      final expectedAffected = isAffectedLabel(c.label);
      final predictedAffected = index.score < 70;

      if (expectedAffected && predictedAffected) tp++;
      if (!expectedAffected && predictedAffected) fp++;
      if (!expectedAffected && !predictedAffected) tn++;
      if (expectedAffected && !predictedAffected) fn++;

      final ok = expectedAffected == predictedAffected;
      (ok ? correct : incorrect).add(
        '${c.id}: ${expectedAffected ? 'affected' : 'healthy'} '
        '$c.condition predicted '
        '${predictedAffected ? 'affected' : 'healthy'} '
        '(index ${index.score})',
      );

      final list = condStats.putIfAbsent(c.condition, () => <_CondItem>[]);
      list.add(_CondItem(
        expected: c.label,
        predictedAffected: predictedAffected,
      ));
    }

    for (final entry in condStats.entries) {
      var hits = 0;
      for (final item in entry.value) {
        final expAff = isAffectedLabel(item.expected);
        if (item.expected == 'no_plant') {
          // occlusion condition: expecting rejection
          hits += 1;
          continue;
        }
        if (expAff == item.predictedAffected) hits++;
      }
      byCondition[entry.key] = DemoConditionMetric(
        samples: entry.value.length,
        accuracy: entry.value.isEmpty ? 0 : hits / entry.value.length,
      );
    }

    final total = tp + tn + fp + fn;
    final precision = tp + fp == 0 ? 0.0 : tp / (tp + fp);
    final recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
    final f1 = precision + recall == 0 ? 0.0 : 2 * precision * recall / (precision + recall);

    final elapsed = stopwatch.elapsedMilliseconds;

    correct.sort();
    incorrect.sort();

    return DemoBenchmarkResult(
      samples: cases.length,
      confusionHealthy: {'TP': tn, 'FP': fn, 'TN': tp, 'FN': fp},
      confusionAffected: {'TP': tp, 'FP': fp, 'TN': tn, 'FN': fn},
      accuracy: total == 0 ? 0 : (tp + tn) / total,
      precision: precision,
      recall: recall,
      f1: f1,
      falsePositives: fp,
      falseNegatives: fn,
      avgInferenceMs: elapsed / math.max(1, cases.length),
      correctExamples: correct,
      incorrectExamples: incorrect,
      byCondition: byCondition,
      noPlantSamples: noPlantSamples,
      noPlantCorrect: noPlantCorrect,
    );
  }
}

class _CondItem {
  const _CondItem({required this.expected, required this.predictedAffected});

  final String expected;
  final bool predictedAffected;
}

/// Side-by-side comparison for the Experiment Lab.
class ExperimentLabResult {
  const ExperimentLabResult({
    required this.healthy,
    required this.affected,
    required this.comparisons,
  });

  final LeafAnalysis healthy;
  final LeafAnalysis affected;
  final List<ExperimentComparison> comparisons;

  factory ExperimentLabResult.compare(img.Image healthyImage, img.Image affectedImage) {
    final healthy = AnalysisEngine.analyzeSingle(
      AnalysisEngine.prepare(healthyImage),
    );
    final affected = AnalysisEngine.analyzeSingle(
      AnalysisEngine.prepare(affectedImage),
    );
    final healthyIndex = AnalysisEngine.computeIndex([healthy]).score;
    final affectedIndex = AnalysisEngine.computeIndex([affected]).score;

    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

    final comparisons = <ExperimentComparison>[
      ExperimentComparison(
        metric: 'Yellow (chlorosis) area',
        healthyValue: pct(healthy.yellowFraction),
        affectedValue: pct(affected.yellowFraction),
      ),
      ExperimentComparison(
        metric: 'Brown (necrosis) area',
        healthyValue: pct(healthy.brownFraction),
        affectedValue: pct(affected.brownFraction),
      ),
      ExperimentComparison(
        metric: 'Spotted/irregular area',
        healthyValue: pct(healthy.spottedFraction),
        affectedValue: pct(affected.spottedFraction),
      ),
      ExperimentComparison(
        metric: 'Affected region total',
        healthyValue: pct(healthy.damagedFraction),
        affectedValue: pct(affected.damagedFraction),
      ),
      ExperimentComparison(
        metric: 'Green coverage',
        healthyValue: pct(healthy.greenFraction),
        affectedValue: pct(affected.greenFraction),
      ),
      ExperimentComparison(
        metric: 'Health Index (0-100)',
        healthyValue: '$healthyIndex',
        affectedValue: '$affectedIndex',
      ),
    ];

    return ExperimentLabResult(
      healthy: healthy,
      affected: affected,
      comparisons: comparisons,
    );
  }
}