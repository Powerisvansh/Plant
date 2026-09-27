import '../../core/constants.dart';
import '../../models/analysis_models.dart';
import '../plant_database.dart';

/// A ranked identification suggestion.
class PlantCandidate {
  const PlantCandidate(this.plantId, this.commonName, this.scientificName, this.confidence);

  final String plantId;
  final String commonName;
  final String scientificName;
  final double confidence;
}

/// The honest output of identification: a morphology-based suggestion, never
/// a confirmed species.
class PlantCategoryResult {
  const PlantCategoryResult({
    required this.groupLabel,
    required this.groupConfidence,
    required this.candidates,
    required this.uncertain,
    required this.explanation,
  });

  final String groupLabel;
  final double groupConfidence;
  final List<PlantCandidate> candidates;
  final bool uncertain;
  final String explanation;

  /// Falls back to 'Unknown' when nothing could be determined.
  String get bestName => uncertain && candidates.isEmpty ? 'Unknown plant' : best?.commonName ?? 'Unknown plant';

  String get bestScientific =>
      uncertain && candidates.isEmpty ? '' : best?.scientificName ?? '';

  double get bestConfidence => best?.confidence ?? 0;

  PlantCandidate? get best =>
      candidates.isEmpty ? null : candidates.reduce((a, b) => a.confidence >= b.confidence ? a : b);
}

/// Rule-based morphological classifier.
///
/// It turns visual measurements (leaf shape, edge density, coverage) into a
/// *coarse* growth-form suggestion (monocot-like, succulent-like, ...).
/// Species-level confidence is deliberately capped: leaf appearance alone
/// cannot confirm a species, and the app says so.
class PlantClassifier {
  PlantClassifier._();

  static PlantCategoryResult classify(List<LeafAnalysis> images) {
    final active = images.where((a) => a.plantDetected).toList();
    if (active.isEmpty) {
      return const PlantCategoryResult(
        groupLabel: 'Not enough evidence',
        groupConfidence: 0,
        candidates: [],
        uncertain: true,
        explanation:
            'No clearly visible plant was found, so identification was not '
            'possible.',
      );
    }

    double mean(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    final aspect = mean(active.map((a) => a.leafAspectRatio).toList());
    final roundness = mean(active.map((a) => a.leafRoundness).toList());
    final edge = mean(active.map((a) => a.edgeDensity).toList());
    final coverage = mean(active.map((a) => a.plantCoverage).toList());
    final green = mean(active.map((a) => a.greenFraction).toList());

    // Growth-form scores from the visual rules (range 0..1).
    final groups = <String, double>{};

    double monocot = 0;
    if (aspect > 2.6) {
      monocot = (0.45 + (aspect - 2.6) * 0.25).clamp(0.0, 0.85);
      if (roundness < 0.35) monocot += 0.1;
      monocot = monocot.toDouble();
    }
    if (monocot > 0) groups['monocot'] = monocot;

    final broadleaf = _bell(aspect, 1.1, 2.8) * 0.5 +
        _bell(roundness, 0.3, 0.8) * 0.25;
    if (broadleaf > 0.2) groups['broadleaf'] = broadleaf.clamp(0.0, 0.6).toDouble();

    final succulent = (roundness > 0.55 ? (0.3 + roundness * 0.4) : 0.0) +
        (edge < 25 ? 0.15 : 0.0);
    if (succulent > 0.2) groups['succulent'] = succulent.clamp(0.0, 0.8).toDouble();

    final viny = _bell(aspect, 1.0, 1.9) * 0.3 +
        (edge > 30 ? 0.25 : 0.0) +
        (roundness > 0.5 ? 0.15 : 0.0);
    if (viny > 0.2) groups['vine'] = viny.clamp(0.0, 0.55).toDouble();

    final fern = _bell(aspect, 1.3, 3.4) * 0.25 + (edge > 40 ? 0.4 : 0.0);
    if (fern > 0.2) groups['fern'] = fern.clamp(0.0, 0.6).toDouble();

    final shrub = (coverage > 0.35 ? 0.25 : 0.0) +
        (green > 0.4 ? 0.1 : 0.0);
    if (shrub > 0.2) groups['shrub'] = shrub.clamp(0.0, 0.4);

    // Rank groups.
    final ordered = groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ordered.isEmpty) {
      return const PlantCategoryResult(
        groupLabel: 'Plant type unclear',
        groupConfidence: 0,
        candidates: [],
        uncertain: true,
        explanation:
            'The leaf shape features were not decisive enough to assign a '
            'plant type. Try a close-up of a whole leaf.',
      );
    }

    final topGroup = ordered.first;
    final topGroups = ordered.take(2).map((e) => e.key).toSet();

    final candidates = <PlantCandidate>[];
    // Deliberate honesty cap: leaf morphology cannot confirm a species from
    // a phone photo, so no species-level suggestion ever exceeds 42%.
    const speciesCap = 0.42;
    for (final plant in PlantDatabase.all) {
      final overlap = plant.morphologyTags.where(topGroups.contains).length;
      if (overlap == 0) continue;
      final bestTagScore = plant.morphologyTags
          .where(topGroups.contains)
          .map((t) => groups[t] ?? 0)
          .reduce((a, b) => a > b ? a : b);
      final confidence = (bestTagScore + (overlap - 1) * 0.08)
          .clamp(0.0, speciesCap)
          .toDouble();
      candidates.add(PlantCandidate(
        plant.id,
        plant.commonName,
        plant.scientificName,
        confidence,
      ));
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    final bestConfidence = candidates.isEmpty ? 0.0 : candidates.first.confidence;
    final uncertain =
        bestConfidence < AppConstants.identificationUncertaintyThreshold;

    final explanation = uncertain
        ? 'The leaf shape matches a *${topGroupLabel(topGroup.key)}* growth '
              'form, but there is not enough evidence to confirm a specific '
              'species. These are possibilities to check against the actual '
              'plant.'
        : 'The leaf appearance is most consistent with a '
              '*${topGroupLabel(topGroup.key)}* plant. The name below is an '
              'informed guess, not a confirmed identification.';

    return PlantCategoryResult(
      groupLabel: topGroupLabel(topGroup.key),
      groupConfidence: topGroup.value,
      candidates: candidates.take(4).toList(),
      uncertain: uncertain,
      explanation: explanation,
    );
  }

  /// A tent-shaped scoring curve peaking around [peak].
  static double _bell(double v, double lo, double hi) {
    if (v <= lo || v >= hi) return 0;
    final mid = (lo + hi) / 2;
    final width = (hi - lo) / 2;
    return (1 - ((v - mid).abs() / width)).clamp(0.0, 1.0);
  }

  static String topGroupLabel(String key) => switch (key) {
        'monocot' => 'elongated-leaved (monocot-like)',
        'broadleaf' => 'broad-leaved',
        'succulent' => 'succulent-like',
        'vine' => 'vining',
        'fern' => 'fern-like',
        'shrub' => 'shrub-like',
        _ => 'unknown',
      };
}