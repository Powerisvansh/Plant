import '../../core/constants.dart';
import '../../models/analysis_models.dart';
import '../../models/scan_models.dart';
import '../plant_database.dart';
import 'identification_models.dart';

/// Rule-based **growth-form** screening.
///
/// This class answers one question only: *what broad kind of leaf shape is
/// this?* (elongated-leaved / broad-leaved / succulent-like / vining /
/// fern-like / shrub-like).
///
/// It deliberately cannot name a species. The previous version of this file
/// scored every plant in the catalogue against leaf shape and surfaced the
/// winner as "the plant" - which is how unrelated photos ended up labelled
/// "Snake Plant". Two things changed:
///
///  1. scoring no longer rewards a plant for having many catalogue tags (the
///     old `+0.08 per extra tag` bonus made multi-tag entries win by
///     construction), and
///  2. the result is a [PlantIdentification] whose species fields stay null.
///     Only a real model result (`IdentificationSource.model`) may name a
///     species.
class PlantClassifier {
  PlantClassifier._();

  /// Minimum similarity before a catalogue entry is even listed as a look-alike.
  static const double _minPossibilityScore = 0.22;

  /// Morphology scores are not probabilities, so they can never be "high".
  static const double _maxMorphologyConfidence = 0.42;

  static PlantIdentification classify(List<LeafAnalysis> images) {
    final active = images.where((a) => a.plantDetected).toList();
    if (active.isEmpty) {
      return PlantIdentification.none;
    }

    double mean(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    final aspect = mean(active.map((a) => a.leafAspectRatio).toList());
    final roundness = mean(active.map((a) => a.leafRoundness).toList());
    final edge = mean(active.map((a) => a.edgeDensity).toList());
    final coverage = mean(active.map((a) => a.plantCoverage).toList());
    final green = mean(active.map((a) => a.greenFraction).toList());

    final groups = <String, double>{};

    double monocot = 0;
    if (aspect > 2.6) {
      monocot = (0.45 + (aspect - 2.6) * 0.25).clamp(0.0, 0.85);
      if (roundness < 0.35) monocot += 0.1;
      monocot = monocot.toDouble();
    }
    if (monocot > 0) groups['monocot'] = monocot;

    final broadleaf =
        _bell(aspect, 1.1, 2.8) * 0.5 + _bell(roundness, 0.3, 0.8) * 0.25;
    if (broadleaf > 0.2) {
      groups['broadleaf'] = broadleaf.clamp(0.0, 0.6).toDouble();
    }

    final succulent = (roundness > 0.55 ? (0.3 + roundness * 0.4) : 0.0) +
        (edge < 25 ? 0.15 : 0.0);
    if (succulent > 0.2) {
      groups['succulent'] = succulent.clamp(0.0, 0.8).toDouble();
    }

    final viny = _bell(aspect, 1.0, 1.9) * 0.3 +
        (edge > 30 ? 0.25 : 0.0) +
        (roundness > 0.5 ? 0.15 : 0.0);
    if (viny > 0.2) groups['vine'] = viny.clamp(0.0, 0.55).toDouble();

    final fern = _bell(aspect, 1.3, 3.4) * 0.25 + (edge > 40 ? 0.4 : 0.0);
    if (fern > 0.2) groups['fern'] = fern.clamp(0.0, 0.6).toDouble();

    final shrub = (coverage > 0.35 ? 0.25 : 0.0) + (green > 0.4 ? 0.1 : 0.0);
    if (shrub > 0.2) groups['shrub'] = shrub.clamp(0.0, 0.4);

    final ordered = groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ordered.isEmpty) {
      return const PlantIdentification(
        source: IdentificationSource.morphology,
        band: ConfidenceBand.unknown,
        growthFormLabel: 'unclear plant type',
        growthFormConfidence: 0,
        candidates: [],
        explanation: 'The leaf-shape measurements were not decisive enough to '
            'describe a plant type. A closer photo of a whole leaf may help.',
      );
    }

    final topGroup = ordered.first;
    final topGroups = ordered.take(2).map((e) => e.key).toList();
    final scored = _scorePlants(groups, topGroups);
    final candidates = scored
        .where((s) => s.score >= _minPossibilityScore)
        .take(3)
        .map((s) => IdentificationCandidate(
              plantId: s.plant.id,
              commonName: s.plant.commonName,
              scientificName: s.plant.scientificName,
              score: s.score,
              morphologyOnly: true,
            ))
        .toList(growable: false);

    final label = growthFormLabel(topGroup.key);
    final confidentEnough = topGroup.value >= 0.35;
    final explanation = confidentEnough
        ? 'Leaf shape reads as a $label. That is a plant *type*, not a '
            'species - PlantDoctor will not name a species from leaf shape '
            'alone. Check the possibilities against the real plant.'
        : 'Leaf shape only loosely suggests a $label, so even the plant type '
            'is uncertain.';

    return PlantIdentification(
      source: IdentificationSource.morphology,
      band: ConfidenceBand.unknown,
      growthFormLabel: label,
      growthFormConfidence: topGroup.value.clamp(0.0, _maxMorphologyConfidence),
      candidates: candidates,
      explanation: explanation,
      modelAvailable: false,
    );
  }

  /// Ranks catalogue plants against the observed growth-form evidence.
  ///
  /// Fair scoring rules (these fix the old "Snake Plant wins everything"):
  ///  * a plant only competes when the *leading* growth form it is tagged with
  ///    actually appears among the observed top groups;
  ///  * the score is a blend of the primary-tag evidence and the *weakest*
  ///    matched tag (a plant cannot win by having one strong tag and several
  ///    unsupported ones);
  ///  * there is no bonus for having more tags in the catalogue.
  static List<_ScoredPlant> _scorePlants(
    Map<String, double> groups,
    List<String> topGroups,
  ) {
    final scored = <_ScoredPlant>[];
    for (final plant in PlantDatabase.all) {
      final tags = plant.morphologyTags;
      if (tags.isEmpty) continue;
      final primary = tags.first;
      final rank = topGroups.indexOf(primary);
      if (rank < 0) continue;

      final matched =
          tags.where(topGroups.contains).map((t) => groups[t] ?? 0.0).toList();
      if (matched.isEmpty) continue;
      final weakest = matched.reduce((a, b) => a < b ? a : b);
      final primaryScore = groups[primary] ?? 0;
      final rankPenalty = rank == 0 ? 1.0 : 0.75;
      final score = ((primaryScore * 0.6) + (weakest * 0.4)) * rankPenalty;
      if (score <= 0) continue;
      scored.add(
          _ScoredPlant(plant, score.clamp(0.0, _maxMorphologyConfidence)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// A tent-shaped scoring curve peaking around the middle of [lo]..[hi].
  static double _bell(double v, double lo, double hi) {
    if (v <= lo || v >= hi) return 0;
    final mid = (lo + hi) / 2;
    final width = (hi - lo) / 2;
    return (1 - ((v - mid).abs() / width)).clamp(0.0, 1.0);
  }

  static String growthFormLabel(String key) => switch (key) {
        'monocot' => 'elongated-leaved (monocot-like)',
        'broadleaf' => 'broad-leaved',
        'succulent' => 'succulent-like',
        'vine' => 'vining',
        'fern' => 'fern-like',
        'shrub' => 'shrub-like',
        _ => 'unclassified',
      };

  /// Confidence ceiling for any purely morphological statement.
  static double get morphologyConfidenceCap => _maxMorphologyConfidence;

  /// Kept for screens that display the uncertainty threshold.
  static double get uncertaintyThreshold =>
      AppConstants.identificationUncertaintyThreshold;
}

class _ScoredPlant {
  _ScoredPlant(this.plant, this.score);
  final PlantInfo plant;
  final double score;
}
