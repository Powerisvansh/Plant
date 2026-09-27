import 'dart:ui';

/// What kind of subject a captured photo is meant to show.
enum ImageSubjectType { wholePlant, leaf, affectedArea, stemFruit, unknown }

/// A single problem found during image-quality screening.
enum QualityIssue {
  tooDark,
  tooBlurry,
  plantNotDetected,
  tooSmall,
  extremeObstruction;

  String get label => switch (this) {
        tooDark => 'Image is too dark',
        tooBlurry => 'Image appears blurry',
        plantNotDetected => 'No clear plant detected',
        tooSmall => 'Resolution is too small',
        extremeObstruction => 'Image is severely obstructed',
      };
}

/// Result of an image-quality gate. Analysis still proceeds, but the user is
/// warned when [usable] is false.
class ImageQualityReport {
  const ImageQualityReport({
    required this.usable,
    required this.issues,
    required this.brightness,
    required this.blurScore,
  });

  final bool usable;
  final List<QualityIssue> issues;
  final double brightness; // 0.0 .. 1.0 mean luminance
  final double blurScore; // variance of Laplacian (higher = sharper)

  String get summary {
    if (issues.isEmpty) return 'Image quality is good.';
    return issues.map((e) => e.label).join(', ');
  }
}

/// A bounding region that contributed to the screening, used to draw visual
/// evidence on top of the photo.
class EvidenceRegion {
  const EvidenceRegion({
    required this.rect,
    required this.kind,
    required this.score,
  });

  final Rect rect;
  final String kind; // 'yellow' | 'brown' | 'spot' | 'leaf-area' | 'damage'
  final double score; // 0.0 .. 1.0 severity contribution
}

/// Numerical measurements extracted from a single image by the analysis engine.
class LeafAnalysis {
  const LeafAnalysis({
    required this.yellowFraction,
    required this.brownFraction,
    required this.greenFraction,
    required this.darkFraction,
    required this.spottedFraction,
    required this.meanBrightness,
    required this.blurScore,
    required this.plantDetected,
    required this.plantCoverage,
    required this.textureVariation,
    required this.leafAspectRatio,
    required this.leafRoundness,
    required this.edgeDensity,
    required this.evidence,
  });

  final double yellowFraction;
  final double brownFraction;
  final double greenFraction;
  final double darkFraction;
  final double spottedFraction;
  final double meanBrightness;
  final double blurScore;
  final bool plantDetected;
  final double plantCoverage; // fraction of frame occupied by plant pixels
  final double textureVariation; // local contrast in leaf areas
  final double leafAspectRatio;
  final double leafRoundness;
  final double edgeDensity; // boundary/vein frequency, used by the classifier
  final List<EvidenceRegion> evidence;

  /// Combined fraction of the frame that looks damaged/discoloured.
  double get damagedFraction =>
      (yellowFraction + brownFraction + spottedFraction).clamp(0.0, 1.0);
}

/// A ranked possible cause produced by symptom fingerprinting.
/// It is a *screening* hypothesis, never a confirmed diagnosis.
class CauseCandidate {
  const CauseCandidate({
    required this.label,
    required this.confidence,
    required this.explanation,
    required this.nutrients,
  });

  final String label;
  final double confidence; // how strongly visible symptoms match this pattern
  final String explanation;
  final List<String> nutrients; // relevant nutrients to investigate, if any

  String get confidenceLabel => '${(confidence * 100).round()}% match';
}

/// Health screening output combining symptoms from all analysed images.
class HealthReport {
  const HealthReport({
    required this.overallCondition,
    required this.statements,
    required this.observedIndicators,
    required this.possibleCauses,
    required this.uncertaintyExplanation,
    required this.nutrientNotes,
    required this.safeCareGuidance,
    required this.safeMedicineGuidance,
    required this.warningFlags,
  });

  final String overallCondition; // e.g. "Needs attention"
  final List<String> statements; // highlighted observations
  final List<String> observedIndicators;
  final List<CauseCandidate> possibleCauses;
  final String uncertaintyExplanation;
  final List<String> nutrientNotes;
  final List<String> safeCareGuidance;
  final List<String> safeMedicineGuidance;
  final List<String> warningFlags;

  bool get isHealthy =>
      overallCondition == 'Looks healthy' || overallCondition == 'Healthy';
}

/// PlantDoctor Health Index: an experimental software metric based purely on
/// visible image characteristics. It is NOT a scientific/medical standard.
class HealthIndex {
  const HealthIndex({
    required this.score,
    required this.grade,
    required this.components,
  });

  final int score; // 0..100
  final HealthGrade grade;
  final Map<String, double> components; // named component -> weight used

  HealthGrade get classification => grade;
}

enum HealthGrade { excellent, good, needsAttention, concerning, poor }