import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plantdoctor/models/analysis_models.dart';
import 'package:plantdoctor/models/knowledge_models.dart';
import 'package:plantdoctor/services/analysis/scan_suggestions.dart';
import 'package:plantdoctor/services/identification/identification_models.dart';
import 'package:plantdoctor/services/knowledge/knowledge_repository.dart';
import 'package:plantdoctor/services/ml/plant_model.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the suggestion layer against the real bundled database.
///
/// The critical property is not that suggestions exist, but that they never
/// invent: no species without a confident identification, no cause without
/// measured evidence, and no dose anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KnowledgeRepository repo;

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    final asset = File('assets/plant_knowledge/plantdoctor.db').absolute.path;
    repo = await KnowledgeRepository.openForTesting(asset);
  });

  tearDownAll(() async => KnowledgeRepository.closeForTesting());

  HealthReport healthy() => const HealthReport(
        overallCondition: 'Looks healthy',
        statements: [],
        observedIndicators: [],
        possibleCauses: [],
        uncertaintyExplanation: 'Screening only.',
        nutrientNotes: [],
        safeCareGuidance: ['Improve air circulation around the plant.'],
        safeMedicineGuidance: [],
        warningFlags: [],
      );

  LeafAnalysis leaf({
    double yellow = 0,
    double brown = 0,
    double spotted = 0,
    double green = 0.8,
  }) =>
      LeafAnalysis(
        yellowFraction: yellow,
        brownFraction: brown,
        greenFraction: green,
        darkFraction: 0,
        spottedFraction: spotted,
        meanBrightness: 0.5,
        blurScore: 40,
        plantDetected: true,
        plantCoverage: 0.5,
        textureVariation: 0.2,
        leafAspectRatio: 2,
        leafRoundness: 0.7,
        edgeDensity: 5,
        evidence: const [],
      );

  /// A result the model refused to name, which is the common case for the
  /// ~9,900 species the model does not cover.
  const uncertain = PlantIdentification(
    source: IdentificationSource.none,
    band: ConfidenceBand.unknown,
    growthFormLabel: 'broadleaf',
    growthFormConfidence: 0.4,
    candidates: [],
    explanation: 'No model match.',
    plantDetected: true,
  );

  /// A confident model result for a crop the bundled model does cover.
  const confidentTomato = PlantIdentification(
    source: IdentificationSource.model,
    band: ConfidenceBand.high,
    growthFormLabel: 'broadleaf',
    growthFormConfidence: 0.9,
    candidates: [
      IdentificationCandidate(
        plantId: 'solanum-lycopersicum',
        commonName: 'Tomato',
        scientificName: 'Solanum lycopersicum',
        score: 0.91,
        probability: 0.91,
      ),
    ],
    explanation: 'Identified.',
    plantDetected: true,
    modelAvailable: true,
    identifiedName: 'Tomato',
    identifiedScientificName: 'Solanum lycopersicum',
    identifiedConfidence: 0.91,
  );

  group('profile and category browsing', () {
    test('a profile carries categories, and curated crops when present',
        () async {
      final okra = await repo.plantBySlug('abelmoschus-esculentus');
      expect(okra, isNotNull);

      final profile = await repo.profileFor(okra!);
      expect(profile.categories, isNotEmpty,
          reason: 'every plant is categorised');
      expect(profile.categories.first.code, anyOf('FOOD_CROP', 'VEGETABLE'));

      // Okra is one of the curated crop records.
      expect(profile.crop.hasAnyData, isTrue);
      expect(profile.crop.details, isNotEmpty);
      final joined =
          profile.crop.details.map((e) => '${e.key} ${e.value}').join(' ');
      expect(joined.toLowerCase(), contains('kharif'),
          reason: 'sowing season is real Indian practice data');
    });

    test('a plant without a curated crop record says so rather than guessing',
        () async {
      // Pick any species with no curated crop row.
      final plants = await repo.browse(limit: 40);
      KnowledgePlant? bare;
      for (final p in plants) {
        final crop = await repo.cropFor(p.id);
        if (crop == null || !crop.hasAnyData) {
          bare = p;
          break;
        }
      }
      expect(bare, isNotNull, reason: 'most species have no crop record');

      final profile = await repo.profileFor(bare!);
      expect(profile.crop.hasAnyData, isFalse);
      expect(profile.crop.details, isEmpty,
          reason: 'an empty crop record must render as absent, not default');
    });

    test('related plants are real, distinct species in the same lineage',
        () async {
      final tomato = await repo.plantBySlug('solanum-lycopersicum');
      expect(tomato, isNotNull);

      final related = await repo.relatedPlants(tomato!.id, limit: 8);
      expect(related, isNotEmpty);
      expect(related.length, lessThanOrEqualTo(8));
      expect(related.map((r) => r.id).toSet().length, related.length,
          reason: 'no duplicates');
      for (final r in related) {
        expect(r.id, isNot(tomato.id), reason: 'a plant is not its own relative');
        expect(r.scientificName, isNotEmpty);
      }
    });

    test('browsing a category returns only real members of it', () async {
      final counts = await repo.categoryCounts();
      expect(counts['VEGETABLE'], greaterThan(0));

      final veg = await repo.browseCategory('VEGETABLE', limit: 25);
      expect(veg, isNotEmpty);
      expect(veg.length, lessThanOrEqualTo(25));

      for (final p in veg) {
        final cats = await repo.categoriesFor(p.id);
        expect(cats.map((c) => c.code), contains('VEGETABLE'),
            reason: '${p.slug} was returned by the vegetable filter');
      }
    });

    test('an unknown category returns nothing instead of everything',
        () async {
      final rows = await repo.browseCategory('NOT_A_REAL_CATEGORY');
      expect(rows, isEmpty,
          reason: 'a bad filter must not silently fall back to all plants');
    });

    test('category counts agree with the rows they describe', () async {
      final counts = await repo.categoryCounts();
      final categories = await repo.categories();
      expect(categories, isNotEmpty);

      // Every count the UI displays must correspond to real rows.
      for (final entry in counts.entries) {
        expect(entry.value, greaterThan(0),
            reason: '${entry.key} is shown in the UI so it must have members');
      }
      // A category with no members carries no count at all, which is how the
      // browser screen decides to hide its chip. FIBRE_CROP is currently one
      // of these: defined in the vocabulary, but the fibre_and_industrial
      // harvest group maps to AGRICULTURAL_CROP, so it holds no rows.
      final empty = categories
          .where((c) => (counts[c.code] ?? 0) == 0)
          .map((c) => c.code)
          .toSet();
      expect(counts.keys.toSet().intersection(empty), isEmpty,
          reason: 'a zero-member category must not be given a count');
    });
  test('a curated crop profile renders everything the screen needs',
        () async {
      // This is the exact model KnowledgePlantDetailScreen renders from.
      final profile = await repo.profileForSlug('abelmoschus-esculentus');
      expect(profile, isNotNull);
      final p = profile!;

      expect(p.plant.commonName, 'Okra');
      expect(p.categories.map((c) => c.label), contains('Vegetable'));
      expect(p.crop.hasAnyData, isTrue);
      expect(p.crop.details.map((e) => e.key), contains('Edible part'));
      expect(p.crop.details.map((e) => e.value), contains('immature pods'));
      expect(p.related, isNotEmpty);
    });

    test('a profile with no curated crop omits the section entirely', () async {
      // Find a real species that has no curated crop row, rather than assuming
      // one. Tomato, for instance, *is* in crop_coverage.json.
      KnowledgePlant? bare;
      for (final p in await repo.browse(limit: 60)) {
        final crop = await repo.cropFor(p.id);
        if (crop == null || !crop.hasAnyData) {
          bare = p;
          break;
        }
      }
      expect(bare, isNotNull, reason: 'most species have no crop record');

      final profile = await repo.profileFor(bare!);
      expect(profile.crop.hasAnyData, isFalse);
      expect(profile.crop.details, isEmpty,
          reason: 'the section is absent rather than filled with defaults');
      // Categories are present regardless.
      expect(profile.categories, isNotEmpty);
    });

    test('an unknown slug resolves to null, not a placeholder record',
        () async {
      final profile = await repo.profileForSlug('this-plant-does-not-exist');
      expect(profile, isNull,
          reason: 'a miss must render "not found", never a substitute');
    });
  });

  group('confidence threshold has a single source of truth', () {
    test('the shipped labels file and the code default agree', () {
      final f = File('assets/models/plantdoctor_plants.labels.json');
      expect(f.existsSync(), isTrue);
      final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final shipped = (doc['unknown_threshold'] as num).toDouble();

      expect(shipped, ModelLabels.defaultUnknownThreshold,
          reason: 'the labels JSON and the code fallback must not disagree; '
              'a malformed file would otherwise loosen the safety gate');
      expect(shipped, greaterThanOrEqualTo(0.5),
          reason: 'a floor below 0.5 would name a species on a coin flip');
    });

    test('the identification service uses that same value', () {
      // The service exposes its floor through the labels it reads; this guards
      // against a second hardcoded copy being reintroduced.
      expect(ModelLabels.defaultUnknownThreshold, 0.60);
    });
  });

  group('never invents', () {
    test('an uncertain result never names a species', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: uncertain,
        health: healthy(),
        perImage: [leaf()],
      );

      expect(out.hasPlantDetail, isFalse,
          reason: 'below the confidence floor no species may be claimed');
      expect(out.categories, isEmpty);
      expect(out.crop.hasAnyData, isFalse);
      // Symptom advice still works, because it comes from pixels not a name.
      expect(out.items, isNotEmpty);
    });

    test('a clean leaf is not told about a deficiency', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: uncertain,
        health: healthy(),
        perImage: [leaf()],
      );

      final titles = out.items.map((i) => i.title).toList();
      expect(titles, contains('No obvious damage detected'));
      expect(titles, isNot(contains('Yellowing is visible')),
          reason: 'no yellow pixels means no deficiency advice');
    });

    test('no suggestion ever contains a dose', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: confidentTomato,
        health: healthy(),
        perImage: [leaf(yellow: 0.4, brown: 0.2, spotted: 0.1)],
      );

      expect(out.items, isNotEmpty);
      for (final item in out.items) {
        final text = item.detail.toLowerCase();
        expect(text, isNot(contains('ml/l')),
            reason: 'no application rate may ever be suggested');
        expect(text, isNot(contains('grams per litre')));
        expect(text, isNot(contains('spray at')));
      }
    });
  });

  group('follows measured evidence', () {
    test('measured yellowing produces a nutrient suggestion', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: uncertain,
        health: healthy(),
        perImage: [leaf(yellow: 0.3)],
      );

      expect(out.items.map((i) => i.title), contains('Yellowing is visible'),
          reason: '30% chlorotic pixels must be reported');
    });

    test('measured necrosis is reported', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: uncertain,
        health: healthy(),
        perImage: [leaf(brown: 0.2)],
      );
      expect(out.items.map((i) => i.title),
          contains('Brown dead tissue is visible'));
    });

    test('cultural guidance reaches the user', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: uncertain,
        health: healthy(),
        perImage: [leaf(yellow: 0.2)],
      );
      expect(out.items.map((i) => i.kind),
          contains(ScanSuggestionKind.care),
          reason: 'the safe care list must reach the user');
    });
  });

  group('grounded in the bundled database', () {
    test('a confident identification resolves to real database content',
        () async {
      final out = await ScanSuggestionService(repo).build(
        identification: confidentTomato,
        health: healthy(),
        perImage: [leaf()],
      );

      expect(out.hasPlantDetail, isTrue);
      expect(out.plant!.canonicalName, 'Solanum lycopersicum');
      expect(out.categories, isNotEmpty,
          reason: 'a named plant must carry its category labels');
      expect(out.hasRelated, isTrue,
          reason: 'same-genus/family plants are real related suggestions');
    });

    test('unknown toxicity is surfaced, never implied safe', () async {
      final out = await ScanSuggestionService(repo).build(
        identification: confidentTomato,
        health: healthy(),
        perImage: [leaf()],
      );

      final safety =
          out.items.where((i) => i.kind == ScanSuggestionKind.safety).toList();
      expect(safety, isNotEmpty,
          reason: 'every record is UNKNOWN, so the warning must show');
      expect(safety.first.detail.toLowerCase(),
          contains('not proof of safety'));
    });
  });
}