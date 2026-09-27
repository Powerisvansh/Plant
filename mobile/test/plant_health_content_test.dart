import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plantdoctor/models/plant_health_models.dart';
import 'package:plantdoctor/screens/learn/learn_screen.dart';
import 'package:plantdoctor/screens/learn/plant_health_guide_screen.dart';
import 'package:plantdoctor/services/condition_content.dart';
import 'package:plantdoctor/services/plant_database.dart';
import 'package:plantdoctor/services/plant_health_content.dart';

void main() {
  group('PlantDatabase browser features', () {
    test('database includes many common plants and supports category filters', () {
      expect(PlantDatabase.all.length, greaterThan(2000));
      expect(PlantDatabase.categories, isNotEmpty);
      expect(PlantDatabase.search('tomato').length, greaterThan(0));
      expect(PlantDatabase.search('tomato', category: 'vegetable').length, greaterThan(0));
      expect(PlantDatabase.search('unknown plant').length, equals(0));
    });

    test('plant detail data includes care, disease reasons and medicine guidance', () {
      final extra = PlantDatabase.extraFor('tomato');
      expect(extra, isNotNull);
      expect(extra!.careSummary, isNotEmpty);
      expect(extra.commonDiseases, isNotEmpty);
      expect(extra.sicknessReasons, isNotEmpty);
      expect(extra.medicineGuidance, isNotEmpty);
      expect(
        extra.medicineGuidance.any((item) => item.contains('No exact dosage')),
        isTrue,
      );
    });

    test('disease-by-plant index is searchable and populated', () {
      final diseaseIndex = PlantDatabase.diseaseByPlantIndex();
      expect(diseaseIndex, isNotEmpty);
      expect(diseaseIndex.any((entry) => entry.plantId == 'tomato'), isTrue);
      final tomatoDiseases = PlantDatabase.diseaseByPlant('tomato');
      expect(tomatoDiseases, isNotEmpty);
      expect(PlantDatabase.searchDiseaseByPlant('leaf spot'), isNotEmpty);
      expect(PlantDatabase.searchDiseaseByPlant('unknown disease').isEmpty, isTrue);
    });
  });

  group('PlantHealthContent', () {
    test('covers every major problem category comprehensively', () {
      expect(PlantHealthContent.all.length, greaterThanOrEqualTo(25));
      expect(
        PlantHealthContent.all.map((entry) => entry.category).toSet(),
        PlantProblemCategory.values.toSet(),
      );
    });

    test('entry identifiers are stable and unique', () {
      final ids = PlantHealthContent.all.map((entry) => entry.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id), isTrue);
        expect(PlantHealthContent.byId(id), isNotNull);
      }
    });

    test('every guide contains complete actionable information', () {
      for (final entry in PlantHealthContent.all) {
        expect(entry.title.trim(), isNotEmpty, reason: entry.id);
        expect(entry.scientificName.trim(), isNotEmpty, reason: entry.id);
        expect(entry.summary.trim().length, greaterThan(30), reason: entry.id);
        expect(entry.symptoms, isNotEmpty, reason: entry.id);
        expect(entry.causes, isNotEmpty, reason: entry.id);
        expect(entry.lookAlikes, isNotEmpty, reason: entry.id);
        expect(entry.firstAid, isNotEmpty, reason: entry.id);
        expect(entry.treatments, isNotEmpty, reason: entry.id);
        expect(entry.prevention, isNotEmpty, reason: entry.id);
        expect(entry.escalation, isNotEmpty, reason: entry.id);
        expect(
          entry.safetyNote.trim().length,
          greaterThan(30),
          reason: entry.id,
        );
        expect(entry.references, isNotEmpty, reason: entry.id);

        for (final treatment in entry.treatments) {
          expect(treatment.title.trim(), isNotEmpty, reason: entry.id);
          expect(treatment.steps, isNotEmpty, reason: entry.id);
        }
      }
    });

    test('related guides and category guidance resolve', () {
      for (final entry in PlantHealthContent.all) {
        for (final relatedId in entry.relatedIds) {
          expect(
            PlantHealthContent.byId(relatedId),
            isNotNull,
            reason: '${entry.id} links to missing $relatedId',
          );
        }
      }
      for (final category in PlantProblemCategory.values) {
        expect(
          PlantHealthContent.categoryGuidance[category.label],
          isNotEmpty,
          reason: category.name,
        );
      }
      expect(PlantHealthContent.quickReferenceIds, isNotEmpty);
      for (final entryId in PlantHealthContent.quickReferenceIds.keys) {
        expect(PlantHealthContent.byId(entryId), isNotNull, reason: entryId);
      }
      for (final conditionId in PlantHealthContent.quickReferenceIds.values) {
        expect(
          ConditionContent.byId(conditionId),
          isNotNull,
          reason: 'quick reference links to missing $conditionId',
        );
      }
    });

    test('search matches titles, symptoms and multiple terms', () {
      expect(
        PlantHealthContent.search('spider mites').map((entry) => entry.id),
        contains('spider-mites'),
      );
      expect(
        PlantHealthContent.search('webbing').map((entry) => entry.id),
        contains('spider-mites'),
      );
      for (final spelling in ['gray mold', 'mold', 'grey mould']) {
        expect(
          PlantHealthContent.search(spelling).map((entry) => entry.id),
          contains('grey-mould'),
          reason: spelling,
        );
      }
      expect(
        PlantHealthContent.search('yellow leaves').map((entry) => entry.id),
        isNotEmpty,
      );
      for (final example in [
        'white powder',
        'yellow leaves',
        'wilting',
        'spots',
      ]) {
        expect(PlantHealthContent.search(example), isNotEmpty, reason: example);
      }
      expect(
        PlantHealthContent.search('a condition that cannot exist').isEmpty,
        isTrue,
      );
    });

    test('category filtering stays within the selected category', () {
      final results = PlantHealthContent.search(
        '',
        category: PlantProblemCategory.viral,
      );
      expect(results, isNotEmpty);
      expect(
        results.every((entry) => entry.category == PlantProblemCategory.viral),
        isTrue,
      );
    });

    test('content contains no pesticide quantities or mixing recipes', () {
      final content = [
        ...PlantHealthContent.emergencySteps,
        ...PlantHealthContent.medicineSafety,
        ...PlantHealthContent.categoryGuidance.values,
        for (final entry in PlantHealthContent.all) ...[
          entry.title,
          entry.scientificName,
          entry.summary,
          ...entry.symptoms,
          ...entry.causes,
          ...entry.lookAlikes,
          ...entry.firstAid,
          for (final treatment in entry.treatments) ...[
            treatment.title,
            ...treatment.steps,
          ],
          ...entry.prevention,
          ...entry.escalation,
          entry.safetyNote,
          ...entry.references,
        ],
      ].join(' ');
      final quantityPatterns = [
        RegExp(
          r'\b\d+(?:\.\d+)?\s*(?:ml|l|g|kg|oz|lb|fl\.?\s*oz|tsp|tbsp|quarts?|gallons?|pints?|parts?)\b',
          caseSensitive: false,
        ),
        RegExp(
          r'\b(?:one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:millilit(?:re|er)s?|lit(?:re|er)s?|grams?|kilograms?|ounces?|pounds?|fluid\s+ounces?|teaspoons?|tablespoons?|quarts?|gallons?|pints?)\b',
          caseSensitive: false,
        ),
        RegExp(r'\b\d+(?:\.\d+)?\s*(?:%|percent)\b', caseSensitive: false),
        RegExp(r'\b\d+\s*:\s*\d+\b'),
        RegExp(r'\b\d+\s*/\s*\d+\b'),
      ];

      for (final pattern in quantityPatterns) {
        expect(
          pattern.hasMatch(content),
          isFalse,
          reason: 'quantity matched ${pattern.pattern}',
        );
      }
    });
  });

  testWidgets('guide screen searches and opens medicine safety', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PlantHealthGuideScreen()));

    expect(
      find.text('Find the cause before choosing the medicine'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'spider mites');
    await tester.pump();
    expect(find.text('Emergency first aid'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Spider mites'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Spider mites'), findsOneWidget);
    expect(find.text('Powdery mildew'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plant medicine safety'));
    await tester.pumpAndSettle();

    expect(find.text('Using plant medicine safely'), findsOneWidget);
  });

  testWidgets(
    'detail shows safety and navigates to scoped source and related guides',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PlantHealthGuideScreen()),
      );
      await tester.enterText(find.byType(TextField), 'spider mites');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Spider mites'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Spider mites'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('First aid now'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('First aid now'), findsOneWidget);
      expect(find.text('Read plant medicine safety'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Open source reference'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Optional host-specific source: Spider mites'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open source reference'));
      await tester.pumpAndSettle();
      expect(find.text('Possible symptoms'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Sources'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Copy source link'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Related problems'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Thrips'));
      await tester.pumpAndSettle();
      expect(find.text('Thrips'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('First aid now'), findsOneWidget);
    },
  );

  testWidgets('learn screen opens the plant health guide', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LearnScreen()));

    expect(find.text('Sick plant & medicine guide'), findsOneWidget);
    await tester.tap(find.text('Sick plant & medicine guide'));
    await tester.pumpAndSettle();

    expect(
      find.text('Find the cause before choosing the medicine'),
      findsOneWidget,
    );
  });
}
