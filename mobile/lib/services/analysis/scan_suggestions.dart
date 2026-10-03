import '../../models/analysis_models.dart';
import '../identification/identification_models.dart';
import '../../models/knowledge_models.dart';
import '../knowledge/knowledge_repository.dart';

/// Turns one scan into concrete next steps, grounded in the bundled database.
///
/// This is the layer between "a model said this is a tomato" and "here is what
/// to do about it". Three rules govern everything here:
///
///  * **Never invent a species.** If the model stayed below its confidence
///    floor, no species is named and suggestions are limited to what the image
///    itself measured.
///  * **Never invent a cause.** Suggestions follow the *measured* colour and
///    damage fractions, so a leaf with no yellowing is not told about nitrogen.
///  * **Never invent a dose.** Cultivated advice appears only for species that
///    have a real curated crop record.
class ScanSuggestionService {
  ScanSuggestionService(this.repo);

  final KnowledgeRepository repo;

  /// Builds the suggestion set for a scan result.
  Future<ScanSuggestions> build({
    required PlantIdentification identification,
    required HealthReport health,
    required List<LeafAnalysis> perImage,
  }) async {
    final items = <ScanSuggestion>[];

    // 1. Species-grounded suggestions, only when a species was actually named.
    KnowledgePlant? plant;
    var crop = const KnowledgeCrop();
    List<KnowledgePlant> related = const [];
    List<({String code, String label})> categories = const [];

    if (identification.identifiedName != null) {
      plant = await repo.plantByScientificName(
              identification.identifiedScientificName ??
                  identification.identifiedName!) ??
          (identification.candidates.isEmpty
              ? null
              : await repo.plantBySlug(identification.candidates.first.plantId));
      if (plant != null) {
        categories = await repo.categoriesFor(plant.id);
        crop = await repo.cropFor(plant.id) ?? const KnowledgeCrop();
        related = await repo.relatedPlants(plant.id, limit: 6);

        if (categories.isNotEmpty) {
          items.add(ScanSuggestion(
            title: 'What kind of plant this is',
            detail: categories.map((c) => c.label).join(' · '),
            kind: ScanSuggestionKind.identification,
          ));
        }
        for (final row in crop.details) {
          items.add(ScanSuggestion(
            title: row.key,
            detail: row.value,
            kind: ScanSuggestionKind.cultivation,
          ));
        }
      }
    }

    // 2. Symptom-driven suggestions, always available because they come from
    //    the pixels rather than from an identification.
    items.addAll(_symptomSuggestions(health, perImage));

    // 3. Safety. UNKNOWN toxicity is the honest state for every record, and it
    //    must never be read as "safe".
    if (plant != null && !plant.toxicityKnown) {
      items.add(ScanSuggestion(
        title: 'Do not use this medicinally on this evidence',
        detail: 'Toxicity status for ${plant.displayName} is unknown. '
            'Absence from a toxic list is not proof of safety.',
        kind: ScanSuggestionKind.safety,
      ));
    }

    return ScanSuggestions(
      items: items,
      plant: plant,
      crop: crop,
      related: related,
      categories: categories,
    );
  }

  /// Suggestions derived only from measured image evidence.
  List<ScanSuggestion> _symptomSuggestions(
      HealthReport health, List<LeafAnalysis> perImage) {
    if (perImage.isEmpty) return const [];
    final yellow = perImage.map((a) => a.yellowFraction).reduce((a, b) => a > b ? a : b);
    final brown = perImage.map((a) => a.brownFraction).reduce((a, b) => a > b ? a : b);
    final spotted =
        perImage.map((a) => a.spottedFraction).reduce((a, b) => a > b ? a : b);
    final out = <ScanSuggestion>[];

    if (yellow >= 0.10) {
      out.add(ScanSuggestion(
        title: 'Yellowing is visible',
        detail: 'About ${(yellow * 100).round()}% of the frame reads as '
            'chlorotic. Check nitrogen and iron supply, and confirm the oldest '
            'leaves are affected first before changing anything.',
        kind: ScanSuggestionKind.symptom,
      ));
    }
    if (brown >= 0.05) {
      out.add(ScanSuggestion(
        title: 'Brown dead tissue is visible',
        detail: 'About ${(brown * 100).round()}% of the frame reads as necrosis. '
            'Remove the worst affected material and inspect for early blight or '
            'scorch-type damage.',
        kind: ScanSuggestionKind.symptom,
      ));
    }
    if (spotted >= 0.03) {
      out.add(ScanSuggestion(
        title: 'Discrete spotting pattern detected',
        detail: 'Roughly ${(spotted * 100).round()}% of the frame is isolated '
            'non-green islands inside green tissue, the pattern leaf spot '
            'diseases produce. Isolate the plant and check the underside.',
        kind: ScanSuggestionKind.symptom,
      ));
    }
    if (out.isEmpty) {
      out.add(ScanSuggestion(
        title: 'No obvious damage detected',
        detail: 'The visible leaf area is largely green with no distinct '
            'lesions in this photo. That is a photo-level observation, not a '
            'health certificate.',
        kind: ScanSuggestionKind.symptom,
      ));
    }

    // Cultural controls come before any chemical, matching the project's fixed
    // retrieval order.
    for (final step in health.safeCareGuidance.take(3)) {
      out.add(ScanSuggestion(
        title: 'Start here',
        detail: step,
        kind: ScanSuggestionKind.care,
      ));
    }
    return out;
  }
}

/// One piece of advice, with the evidence it rests on.
class ScanSuggestion {
  const ScanSuggestion({
    required this.title,
    required this.detail,
    required this.kind,
  });

  final String title;
  final String detail;
  final ScanSuggestionKind kind;
}

enum ScanSuggestionKind { identification, cultivation, symptom, care, safety }

/// Everything a scan can offer, ready to render.
class ScanSuggestions {
  const ScanSuggestions({
    required this.items,
    this.plant,
    this.crop = const KnowledgeCrop(),
    this.related = const [],
    this.categories = const [],
  });

  final List<ScanSuggestion> items;
  final KnowledgePlant? plant;
  final KnowledgeCrop crop;
  final List<KnowledgePlant> related;
  final List<({String code, String label})> categories;

  bool get hasPlantDetail => plant != null;
  bool get hasRelated => related.isNotEmpty;
}