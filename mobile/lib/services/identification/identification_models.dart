/// Identification contract for PlantDoctor.
///
/// Two very different things are deliberately kept apart:
///
///  * **Model-backed identification** - a trained classifier produced class
///    probabilities for the photo. Only this can name a *species*.
///  * **Morphology-only screening** - the pure-Dart leaf-shape rules. This can
///    describe a *growth form* and rank look-alikes, but it must never be
///    presented as a species identification.
///
/// The previous implementation blurred the two and surfaced a single species
/// name (frequently "Snake Plant") even when the evidence was a coarse leaf
/// shape. That behaviour is removed here and cannot be reintroduced without
/// also editing this file.
library;

/// How much trust a result deserves.
enum ConfidenceBand {
  high,
  moderate,
  low,
  unknown;

  String get label => switch (this) {
        ConfidenceBand.high => 'High confidence',
        ConfidenceBand.moderate => 'Moderate confidence',
        ConfidenceBand.low => 'Low confidence',
        ConfidenceBand.unknown => 'Unknown',
      };

  /// Probability thresholds are only applied to *calibrated model output*.
  /// Morphology scores never reach [ConfidenceBand.high].
  static ConfidenceBand fromProbability(double probability) {
    if (probability >= 0.80) return ConfidenceBand.high;
    if (probability >= 0.55) return ConfidenceBand.moderate;
    if (probability > 0.0) return ConfidenceBand.low;
    return ConfidenceBand.unknown;
  }
}

/// Where an identification came from.
enum IdentificationSource {
  /// A trained on-device model produced the ranking.
  model,

  /// Leaf-shape rules only - growth form, not species.
  morphology,

  /// Nothing usable was detected.
  none;

  String get label => switch (this) {
        IdentificationSource.model => 'Image model',
        IdentificationSource.morphology => 'Leaf-shape screening',
        IdentificationSource.none => 'No result',
      };
}

/// One ranked candidate.
class IdentificationCandidate {
  const IdentificationCandidate({
    required this.plantId,
    required this.commonName,
    required this.scientificName,
    required this.score,
    this.probability,
    this.morphologyOnly = true,
  });

  /// Local knowledge-base slug, or a model class label when unmatched.
  final String plantId;
  final String commonName;
  final String scientificName;

  /// Model probability when available, otherwise the morphology similarity.
  final double score;

  /// True probability, only present for model-backed candidates.
  final double? probability;

  /// True when this is a shape-based look-alike rather than a model output.
  final bool morphologyOnly;

  String get displayScore =>
      probability != null ? '${(probability! * 100).round()}%' : '';
}

/// Final, honest identification result for a scan.
class PlantIdentification {
  const PlantIdentification({
    required this.source,
    required this.band,
    required this.growthFormLabel,
    required this.growthFormConfidence,
    required this.candidates,
    required this.explanation,
    this.identifiedName,
    this.identifiedScientificName,
    this.identifiedConfidence,
    this.conflictingEvidence = false,
    this.plantDetected = true,
    this.qualityInsufficient = false,
    this.modelAvailable = false,
  });

  final IdentificationSource source;
  final ConfidenceBand band;

  /// e.g. 'elongated-leaved (monocot-like) plant'.
  final String growthFormLabel;
  final double growthFormConfidence;

  /// Top-K candidates (K <= 5). For [IdentificationSource.morphology] these are
  /// explicitly labelled look-alikes and carry no species claim.
  final List<IdentificationCandidate> candidates;

  /// Human-readable explanation of what the app actually knows.
  final String explanation;

  /// Species name - **only** ever set from a model-backed result.
  final String? identifiedName;
  final String? identifiedScientificName;
  final double? identifiedConfidence;

  /// Multiple photos pointed at different answers.
  final bool conflictingEvidence;

  /// Whether a plant was found at all (non-plant photos are rejected).
  final bool plantDetected;

  /// Photo quality was too poor to screen.
  final bool qualityInsufficient;

  /// Whether an on-device model was actually loaded.
  final bool modelAvailable;

  bool get hasSpeciesIdentification =>
      source == IdentificationSource.model && identifiedName != null;

  /// Below the certainty threshold, or not a model result at all.
  bool get uncertain =>
      !hasSpeciesIdentification ||
      (identifiedConfidence ?? 0) < 0.45 ||
      band == ConfidenceBand.low ||
      band == ConfidenceBand.unknown;

  /// What may be shown as "the plant" in the UI. Never a species name unless a
  /// model produced it.
  String get displayName {
    if (hasSpeciesIdentification) return identifiedName!;
    if (!plantDetected) return 'No plant detected';
    return '$growthFormLabel (type not confirmed)';
  }

  String get displayScientificName =>
      hasSpeciesIdentification ? (identifiedScientificName ?? '') : '';

  /// Name used when saving to history / My Plants.
  String get recordName => hasSpeciesIdentification
      ? identifiedName!
      : (plantDetected ? '$growthFormLabel (unconfirmed)' : 'Unidentified');

  String get recordScientific => displayScientificName;

  /// Look-alikes to show as "possibilities", never as an answer.
  List<IdentificationCandidate> get possibilities => hasSpeciesIdentification
      ? const []
      : candidates.take(3).toList(growable: false);

  static const PlantIdentification none = PlantIdentification(
    source: IdentificationSource.none,
    band: ConfidenceBand.unknown,
    growthFormLabel: 'unknown plant type',
    growthFormConfidence: 0,
    candidates: [],
    explanation: 'No clearly visible plant was found, so identification was '
        'not possible.',
    plantDetected: false,
  );
}
