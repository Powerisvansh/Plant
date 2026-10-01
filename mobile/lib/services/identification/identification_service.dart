import '../../models/analysis_models.dart';
import '../ml/plant_model.dart';
import 'identification_models.dart';
import 'plant_classifier.dart';

/// What a scan produced: the plant identification plus (when a model is
/// present) the crop-disease screening that came from the same network.
class IdentificationOutcome {
  const IdentificationOutcome({
    required this.plant,
    required this.condition,
  });

  final PlantIdentification plant;

  /// Non-null only when a trained model produced a crop/condition prediction.
  final ModelConditionScreen? condition;
}

/// A model-based health-condition prediction (PlantVillage crop/disease model).
class ModelConditionScreen {
  const ModelConditionScreen({
    required this.cropName,
    required this.healthy,
    required this.topProbability,
    required this.topK,
    required this.agreement,
    required this.modelKey,
  });

  final String cropName;
  final bool healthy;
  final double topProbability;
  final List<ModelPrediction> topK;

  /// Fraction of photos whose top-1 agreed with the final answer.
  final double agreement;
  final String modelKey;

  String? get conditionName {
    if (topK.isEmpty) return null;
    return topK.first.classInfo?.condition;
  }
}

/// Combines every available evidence source into one honest result.
///
/// Order of authority:
///   1. a trained on-device model (this is the only source allowed to name a
///      species/crop);
///   2. leaf-shape screening (describes a growth form only);
///   3. nothing usable -> "unknown".
class IdentificationService {
  IdentificationService._();

  static double get _unknownFloor => 0.35;

  /// Combines per-image model outputs with the morphology screening.
  ///
  /// [modelResults] is parallel to [perImage]: entry `i` is the top-K list for
  /// photo `i`, or null when the model could not run for that photo.
  static IdentificationOutcome combine({
    required List<LeafAnalysis> perImage,
    required List<ImageQualityReport> qualityReports,
    required List<List<ModelPrediction>?> modelResults,
  }) {
    final anyPlant = perImage.any((a) => a.plantDetected);
    final usable = modelResults.whereType<List<ModelPrediction>>().toList();
    final model = PlantModelService.instance;

    if (!anyPlant && usable.isEmpty) {
      return const IdentificationOutcome(
        plant: PlantIdentification.none,
        condition: null,
      );
    }

    if (model == null || usable.isEmpty) {
      final morphology = PlantClassifier.classify(perImage);
      final explanation = model == null
          ? '${morphology.explanation} No identification model is bundled in '
              'this build, so no species can be named from this photo.'
          : morphology.explanation;
      return IdentificationOutcome(
        plant: PlantIdentification(
          source: morphology.source,
          band: morphology.band,
          growthFormLabel: morphology.growthFormLabel,
          growthFormConfidence: morphology.growthFormConfidence,
          candidates: morphology.candidates,
          explanation: explanation,
          plantDetected: morphology.plantDetected,
          modelAvailable: false,
        ),
        condition: null,
      );
    }

    return _combineModel(model, perImage, usable);
  }

  static IdentificationOutcome _combineModel(
    PlantModelService model,
    List<LeafAnalysis> perImage,
    List<List<ModelPrediction>> modelResults,
  ) {
    final classCount = model.labels.classes.length;
    final averaged = List<double>.filled(classCount, 0);
    for (final result in modelResults) {
      for (final prediction in result) {
        if (prediction.index < classCount) {
          averaged[prediction.index] += prediction.probability;
        }
      }
    }
    for (var i = 0; i < averaged.length; i++) {
      averaged[i] /= modelResults.length;
    }

    final ranked = <ModelPrediction>[];
    for (var i = 0; i < averaged.length; i++) {
      ranked.add(ModelPrediction(i, averaged[i]));
    }
    ranked.sort((a, b) => b.probability.compareTo(a.probability));
    final topK = ranked.take(5).toList(growable: false);
    final best = topK.isEmpty ? null : topK.first;
    final bestClass = best?.classInfo;

    // Multi-photo conflict: do the photos disagree about the crop?
    final perImageTopCrops = modelResults
        .where((r) => r.isNotEmpty)
        .map((r) => r.first.classInfo?.crop)
        .whereType<String>()
        .toSet();
    final finalCrop = bestClass?.crop;
    final agreementCount = modelResults
        .where((r) => r.isNotEmpty && r.first.classInfo?.crop == finalCrop)
        .length;
    final agreement =
        modelResults.isEmpty ? 0.0 : agreementCount / modelResults.length;
    final conflicting = perImageTopCrops.length > 1 &&
        agreement < 0.6 &&
        modelResults.length > 1;

    final threshold = model.labels.unknownThreshold > 0
        ? model.labels.unknownThreshold
        : _unknownFloor;
    final belowThreshold = best == null || best.probability < threshold;

    final band = belowThreshold
        ? ConfidenceBand.unknown
        : ConfidenceBand.fromProbability(best.probability);

    final candidates = topK
        .map((p) => IdentificationCandidate(
              plantId: p.classInfo?.plantSlug ?? p.classInfo?.classLabel ?? '',
              commonName: p.classInfo?.crop ?? 'Unsupported class',
              scientificName: p.classInfo?.scientificName ?? '',
              score: p.probability,
              probability: p.probability,
              morphologyOnly: false,
            ))
        .toList(growable: false);

    final explanation = _explanationFor(
      belowThreshold: belowThreshold,
      conflicting: conflicting,
      photoCount: perImage.length,
    );

    final plant = PlantIdentification(
      source: belowThreshold
          ? IdentificationSource.none
          : IdentificationSource.model,
      band: band,
      growthFormLabel: _growthFormLabel(perImage),
      growthFormConfidence: 0,
      candidates: candidates,
      explanation: explanation,
      identifiedName: belowThreshold ? null : bestClass?.crop,
      identifiedScientificName:
          belowThreshold ? null : bestClass?.scientificName,
      identifiedConfidence: belowThreshold ? null : best.probability,
      conflictingEvidence: conflicting,
      modelAvailable: true,
    );

    final condition = belowThreshold || bestClass == null
        ? null
        : ModelConditionScreen(
            cropName: bestClass.crop,
            healthy: bestClass.healthy,
            topProbability: best.probability,
            topK: topK,
            agreement: agreement,
            modelKey: '${model.labels.modelKey}/${model.labels.version}',
          );

    return IdentificationOutcome(plant: plant, condition: condition);
  }

  static String _explanationFor({
    required bool belowThreshold,
    required bool conflicting,
    required int photoCount,
  }) {
    if (conflicting) {
      return 'The submitted photos point at different plants, so the visual '
          'evidence conflicts. Add another photo of the same plant, or re-shoot '
          'a clear leaf close-up.';
    }
    if (belowThreshold) {
      return 'Plant identification is uncertain: nothing in the trained model '
          'matched this photo closely enough. The ranked candidates are the '
          'closest classes in the model, not a confirmed answer.';
    }
    return 'Identified from image features by the bundled classifier '
        '($photoCount photo${photoCount == 1 ? '' : 's'} combined). Treat it as '
        'a strong hint and confirm with the profile below.';
  }

  static String _growthFormLabel(List<LeafAnalysis> perImage) {
    final morphological = PlantClassifier.classify(perImage);
    return morphological.growthFormLabel;
  }
}
