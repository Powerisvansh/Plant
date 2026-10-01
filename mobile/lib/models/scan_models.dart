import 'dart:convert';

import '../services/identification/identification_models.dart';
import '../services/identification/identification_service.dart';
import 'analysis_models.dart';

/// Everything the analysis pipeline produced for one scan (1-4 photos).
class ScanAnalysis {
  const ScanAnalysis({
    required this.perImage,
    required this.health,
    required this.aggregateIndex,
    required this.identification,
    required this.measuredMetrics,
    required this.inferenceMillis,
  });

  /// Analysis for each input image, in order.
  final List<LeafAnalysis> perImage;

  /// Combined health assessment across all images.
  final HealthReport health;

  /// Aggregated experimental health index.
  final HealthIndex aggregateIndex;

  /// Identification result. A species name is present only when the bundled
  /// on-device model produced it; otherwise this is growth-form screening.
  final PlantIdentification identification;

  /// Time measurements (for science-fair dashboard).
  final Map<String, num> measuredMetrics;

  final int inferenceMillis;
}

/// Context answered by the user in the follow-up form (optional).
class FollowUpContext {
  const FollowUpContext({
    this.location,
    this.watering,
    this.problemTimeline,
  });

  final String? location;
  final String? watering;
  final String? problemTimeline;

  Map<String, String> toDisplay() => {
        'Where the plant is': ?location,
        'Watering frequency': ?watering,
        'Problem noticed': ?problemTimeline,
      };
}

/// A single saved scan in the local history database.
class ScanRecord {
  ScanRecord({
    required this.id,
    required this.createdAt,
    required this.thumbPath,
    required this.imagePaths,
    required this.imageSubjects,
    required this.plantGuess,
    required this.scientificGuess,
    required this.identificationConfidence,
    required this.identificationUncertain,
    required this.healthIndex,
    required this.overallCondition,
    required this.observedIndicators,
    required this.causeLabels,
    required this.followUp,
    required this.notes,
    required this.savedPlantId,
  });

  final String id;
  final DateTime createdAt;
  final String thumbPath;
  final List<String> imagePaths;
  final List<String> imageSubjects;
  final String plantGuess;
  final String scientificGuess;
  final double identificationConfidence;
  final bool identificationUncertain;
  final int healthIndex;
  final String overallCondition;
  final List<String> observedIndicators;
  final List<String> causeLabels;
  final String? followUp;
  final String notes;
  final String? savedPlantId;

  Map<String, dynamic> toMap() => {
        'id': id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'thumb_path': thumbPath,
        'image_paths': imagePaths,
        'image_subjects': imageSubjects,
        'plant_guess': plantGuess,
        'scientific_guess': scientificGuess,
        'id_confidence': identificationConfidence,
        'id_uncertain': identificationUncertain ? 1 : 0,
        'health_index': healthIndex,
        'condition': overallCondition,
        'indicators': observedIndicators,
        'causes': causeLabels,
        'follow_up': followUp,
        'notes': notes,
        'saved_plant_id': savedPlantId,
      };

  factory ScanRecord.fromMap(Map<String, dynamic> m) {
    List<String> strList(Object? v) {
      if (v == null) return <String>[];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) {
        if (v.isEmpty) return <String>[];
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      }
      return <String>[];
    }
    return ScanRecord(
      id: m['id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      thumbPath: m['thumb_path'] as String? ?? '',
      imagePaths: strList(m['image_paths']),
      imageSubjects: strList(m['image_subjects']),
      plantGuess: m['plant_guess'] as String? ?? 'Unknown plant',
      scientificGuess: m['scientific_guess'] as String? ?? '',
      identificationConfidence: (m['id_confidence'] as num?)?.toDouble() ?? 0,
      identificationUncertain: (m['id_uncertain'] as int? ?? 0) == 1,
      healthIndex: m['health_index'] as int? ?? 0,
      overallCondition: m['condition'] as String? ?? 'Unknown',
      observedIndicators: strList(m['indicators']),
      causeLabels: strList(m['causes']),
      followUp: m['follow_up'] as String?,
      notes: m['notes'] as String? ?? '',
      savedPlantId: m['saved_plant_id'] as String?,
    );
  }
}

/// A named plant the user keeps in "My Plants".
class SavedPlant {
  SavedPlant({
    required this.id,
    required this.name,
    required this.species,
    required this.createdAt,
    required this.notes,
    required this.currentHealthIndex,
    required this.photoPath,
  });

  final String id;
  final String name;
  final String species;
  final DateTime createdAt;
  final String notes;
  final int currentHealthIndex;
  final String photoPath;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'species': species,
        'created_at': createdAt.millisecondsSinceEpoch,
        'notes': notes,
        'health_index': currentHealthIndex,
        'photo': photoPath,
      };

  factory SavedPlant.fromMap(Map<String, dynamic> m) => SavedPlant(
        id: m['id'] as String,
        name: m['name'] as String? ?? 'My plant',
        species: m['species'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        notes: m['notes'] as String? ?? '',
        currentHealthIndex: m['health_index'] as int? ?? 0,
        photoPath: m['photo'] as String? ?? '',
      );
}

/// Reference material about a plant, sourced locally.
class PlantInfo {
  const PlantInfo({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.family,
    required this.origin,
    required this.sunlight,
    required this.water,
    required this.soil,
    required this.temperature,
    required this.growth,
    required this.flowering,
    required this.commonProblems,
    required this.care,
    required this.facts,
    required this.emoji,
    this.morphologyTags = const [],
    this.careSummary = '',
    this.commonDiseases = const [],
    this.sicknessReasons = const [],
    this.medicineGuidance = const [],
  });

  final String id;
  final String commonName;
  final String scientificName;
  final String family;
  final String origin;
  final String sunlight;
  final String water;
  final String soil;
  final String temperature;
  final String growth;
  final String flowering;
  final String commonProblems;
  final String care;
  final List<String> facts;
  final String emoji;
  final List<String> morphologyTags;
  final String careSummary;
  final List<String> commonDiseases;
  final List<String> sicknessReasons;
  final List<String> medicineGuidance;

  String get title => commonName;
}

/// Result of running the science-fair demo benchmark.
class DemoBenchmarkResult {
  const DemoBenchmarkResult({
    required this.samples,
    required this.confusionHealthy,
    required this.confusionAffected,
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.falsePositives,
    required this.falseNegatives,
required this.avgInferenceMs,
        required this.correctExamples,
        required this.incorrectExamples,
        required this.byCondition,
        required this.noPlantSamples,
        required this.noPlantCorrect,
      });

  final int samples;
  final Map<String, int> confusionHealthy; // {'TP','FP','TN','FN'}
  final Map<String, int> confusionAffected;
  final double accuracy;
  final double precision;
  final double recall;
  final double f1;
  final int falsePositives;
  final int falseNegatives;
  final double avgInferenceMs;
  final List<String> correctExamples;
  final List<String> incorrectExamples;

  /// Per image-condition performance (good light, blurry, dark, ...).
  final Map<String, DemoConditionMetric> byCondition;

  /// Non-plant (occlusion) sample counts: how often the app correctly rejects
  /// a frame with no plant in it at all.
  final int noPlantSamples;
  final int noPlantCorrect;
}

class DemoConditionMetric {
  const DemoConditionMetric({
    required this.samples,
    required this.accuracy,
  });

  final int samples;
  final double accuracy;
}

/// One labelled sample used by the science-fair benchmark.
class DemoCase {
  const DemoCase({
    required this.id,
    required this.label, // 'healthy' | 'affected'
    required this.condition, // 'good', 'blurry', 'dark', ...
    required this.seed,
  });

  final String id;
  final String label;
  final String condition;
  final int seed;

  String get displayName => '$id ($condition, $label)';
}

/// A single measured comparison row in the Experiment Lab.
class ExperimentComparison {
  const ExperimentComparison({
    required this.metric,
    required this.healthyValue,
    required this.affectedValue,
  });

  final String metric;
  final String healthyValue;
  final String affectedValue;
}

/// Everything handed to the UI after a successful analysis of 1-4 photos.
class AnalysisBundle {
  const AnalysisBundle({
    required this.perImage,
    required this.health,
    required this.index,
    required this.identification,
    required this.originalPaths,
    required this.workingPaths,
    required this.subjects,
    required this.qualityReports,
    required this.measuredMetrics,
    required this.inferenceMillis,
    this.conditionScreen,
  });

  final List<LeafAnalysis> perImage;
  final HealthReport health;
  final HealthIndex index;

  /// Model-first identification. Species names are only present when the
  /// bundled classifier produced them.
  final PlantIdentification identification;

  /// Crop/condition screening from the same classifier, when a model ran.
  final ModelConditionScreen? conditionScreen;

  /// Paths of the original files the user provided/captured.
  final List<String> originalPaths;

  /// Paths of the reduced-size working copies (used for evidence display).
  final List<String> workingPaths;

  final List<ImageSubjectType> subjects;
  final List<ImageQualityReport> qualityReports;
  final Map<String, num> measuredMetrics;
  final int inferenceMillis;
}