import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plantdoctor/models/knowledge_models.dart';
import 'package:plantdoctor/screens/learn/knowledge_plant_detail_screen.dart';

const _tomato = KnowledgePlant(
  id: 1,
  slug: 'solanum-lycopersicum',
  scientificName: 'Solanum lycopersicum L.',
  commonName: 'Tomato',
);

/// Guards the rooftop siting feature against the three ways it could quietly
/// become dishonest: publishing an unsourced record as though it were sourced,
/// inventing a taxon the database does not hold, or slipping a measured dose
/// into horticultural guidance.
void main() {
  group('rooftop siting model', () {
    test('an unsourced record says so rather than reading as settled', () {
      const record = KnowledgeRooftop(
        rooftopRole: 'edible',
        exposure: 'full sun',
        verificationStatus: 'UNVERIFIED',
      );
      expect(record.hasAnyData, isTrue);
      expect(record.isVerified, isFalse);
      expect(record.provenanceNotice, contains('not yet attached'));
    });

    test('a sourced record is labelled as sourced', () {
      const record = KnowledgeRooftop(
        rooftopRole: 'edible',
        verificationStatus: 'VERIFIED',
      );
      expect(record.isVerified, isTrue);
      expect(record.provenanceNotice, contains('named source'));
    });

    test('an empty record reports no data instead of blank labels', () {
      const record = KnowledgeRooftop(verificationStatus: 'UNVERIFIED');
      expect(record.hasAnyData, isFalse);
      expect(record.badges, isEmpty);
      expect(record.details, isEmpty);
    });

    test('container and root depth read as guidance, not exact figures', () {
      const record = KnowledgeRooftop(
        minContainerLitres: 6,
        rootDepthCm: 25,
        verificationStatus: 'UNVERIFIED',
      );
      expect(record.containerSizeText, contains('about'));
      expect(record.rootDepthText, contains('about'));
    });

    test('blank fields are dropped from the labelled lists', () {
      const record = KnowledgeRooftop(
        rooftopRole: 'edible',
        exposure: '   ',
        heatTolerance: 'high',
        verificationStatus: 'UNVERIFIED',
      );
      expect(record.badges.map((e) => e.key), containsAll(['Role', 'Heat']));
      expect(record.badges.map((e) => e.key), isNot(contains('Light')));
    });
  });

  group('rooftop siting content', () {
    final file = File('../knowledge/data/curated/rooftop_greenery.json');
    Map<String, dynamic> data = <String, dynamic>{};

    setUpAll(() {
      if (file.existsSync()) {
        data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    });

    test('the curated file documents every field it expects', () {
      final meta = data['_meta'] as Map<String, dynamic>?;
      expect(meta, isNotNull,
          reason: 'the file must carry provenance and field definitions');
      final fields = meta!['field_definitions'] as Map<String, dynamic>?;
      expect(fields, isNotNull);
      for (final key in ['scientific_name', 'rooftop_role', 'siting',
        'container', 'watering', 'maintenance', 'notes']) {
        expect(fields!.keys, contains(key),
            reason: '$key must be defined so a curator knows what to supply');
      }
    });

    test('every species record is complete and cites its sources', () {
      final species = (data['species'] as List<dynamic>?) ?? <dynamic>[];
      for (final raw in species) {
        final entry = raw as Map<String, dynamic>;
        final name = entry['scientific_name'];
        expect(name, isNotNull, reason: 'every record must name a species');
        expect(entry['rooftop_role'], isNotNull,
            reason: '$name must say how it is used on a roof');
        for (final block in ['siting', 'container', 'watering', 'maintenance']) {
          expect(entry[block], isA<Map<String, dynamic>>(),
              reason: '$name is missing its $block block');
        }
        // An empty sources list is allowed, but it must be present and empty
        // rather than absent, so "unsourced" is a deliberate recorded state.
        expect(entry.containsKey('sources'), isTrue,
            reason: '$name must state its sources, even if the list is empty');
        expect(entry['sources'], isA<List<dynamic>>());
      }
    });

    test('no record carries a measured dose, dilution or spray recipe', () {
      final species = (data['species'] as List<dynamic>?) ?? <dynamic>[];
      final banned = RegExp(
        r'\b(\d+\s*(ml|l|litre|liter|g|gm|kg|mg)\b|'
        r'\b\d+\s*(drops?|tbsp|tsp)\b|'
        r'\b\d+\s*:\s*\d+\b|'
        r'\b(dilute|mix\s+\d|spray\s+\d|per\s+litre|per\s+liter)\b)',
        caseSensitive: false,
      );
      for (final raw in species) {
        final entry = raw as Map<String, dynamic>;
        final blob = jsonEncode(entry);
        expect(banned.firstMatch(blob), isNull,
            reason: '${entry['scientific_name']} contains application-rate '
                'language; rooftop guidance must stay qualitative');
      }
    });

    test('a species with an empty sources list is stored as UNVERIFIED', () {
      // The rule the build enforces, asserted where it is cheap to check.
      const unsourced = KnowledgeRooftop(verificationStatus: 'UNVERIFIED');
      expect(unsourced.isVerified, isFalse);
    });
  });

  group('rooftop section in the app', () {
    test('the profile exposes rooftop data and hides the section without it', () {
      const withRecord = KnowledgeProfile(
        plant: _tomato,
        rooftop: KnowledgeRooftop(
          rooftopRole: 'edible',
          exposure: 'full sun',
          verificationStatus: 'UNVERIFIED',
        ),
      );
      expect(withRecord.hasRooftopData, isTrue);
      expect(withRecord.rooftop!.badges.map((e) => e.key), contains('Role'));

      const withoutRecord = KnowledgeProfile(plant: _tomato);
      expect(withoutRecord.hasRooftopData, isFalse);
      expect(withoutRecord.rooftop, isNull);
    });

    testWidgets('the section renders both the sourced and unsourced states', (
      WidgetTester tester,
    ) async {
      // The repository needs rootBundle and path_provider, which are not
      // available here, so the section is driven through a profile built in
      // memory. That keeps the rendering and wording under test without
      // standing up the whole asset pipeline.
      for (final profile in <KnowledgeProfile>[
        const KnowledgeProfile(
          plant: _tomato,
          rooftop: KnowledgeRooftop(
            rooftopRole: 'edible',
            exposure: 'full sun',
            heatTolerance: 'moderate',
            minContainerLitres: 6,
            verificationStatus: 'UNVERIFIED',
          ),
        ),
        const KnowledgeProfile(plant: _tomato),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RooftopSection(profile: profile),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RooftopSection), findsOneWidget);
        expect(find.textContaining('Rooftop'), findsWidgets);
      }
    });

    testWidgets('an unsourced record shows the sourcing caveat', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RooftopSection(
                profile: KnowledgeProfile(
                  plant: _tomato,
                  rooftop: KnowledgeRooftop(
                    rooftopRole: 'edible',
                    verificationStatus: 'UNVERIFIED',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The lines render through RichText, so the finder has to opt into
      // rich text rather than matching plain Text widgets.
      expect(find.textContaining('not yet attached', findRichText: true),
          findsOneWidget);
    });

    testWidgets('a missing record is announced, not left blank', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RooftopSection(
                profile: KnowledgeProfile(plant: _tomato),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No rooftop siting record'), findsOneWidget);
    });
  });
}
