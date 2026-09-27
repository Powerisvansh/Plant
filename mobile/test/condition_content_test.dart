import 'package:flutter_test/flutter_test.dart';
import 'package:plantdoctor/services/condition_content.dart';

void main() {
  group('ConditionContent', () {
    test('contains the complete condition guide', () {
      expect(ConditionContent.conditions, hasLength(24));
      expect(
        ConditionContent.conditions.map((condition) => condition.id),
        containsAll([
          'powdery-mildew',
          'downy-mildew',
          'bacterial-leaf-spot',
          'mosaic-virus',
          'spider-mites',
          'water-stress',
          'blossom-end-rot',
        ]),
      );
    });

    test('condition ids are unique and kebab-case', () {
      final ids = ConditionContent.conditions.map((condition) => condition.id);
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        ids.every((id) => RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)),
        isTrue,
      );
    });

    test('every condition has complete content and valid references', () {
      for (final condition in ConditionContent.conditions) {
        expect(condition.commonName, isNotEmpty, reason: condition.id);
        expect(condition.scientificName, isNotEmpty, reason: condition.id);
        expect(condition.symptoms, isNotEmpty, reason: condition.id);
        expect(condition.likelyCauses, isNotEmpty, reason: condition.id);
        expect(condition.lookAlikes, isNotEmpty, reason: condition.id);
        expect(condition.prevention, isNotEmpty, reason: condition.id);
        expect(condition.culturalTreatment, isNotEmpty, reason: condition.id);
        expect(condition.escalation, isNotEmpty, reason: condition.id);
        expect(condition.urgentWarning, isNotEmpty, reason: condition.id);
        expect(condition.treatmentTags, isNotEmpty, reason: condition.id);
        expect(
          ConditionContent.referencesFor(condition),
          isNotEmpty,
          reason: condition.id,
        );
      }
    });

    test('categories cover biological, pest, and environmental causes', () {
      final categories = ConditionContent.conditions
          .map((condition) => condition.category)
          .toSet();
      expect(
        categories,
        containsAll([
          'Fungal',
          'Bacterial',
          'Viral',
          'Pest',
          'Physiological',
          'Abiotic',
          'Nutrient',
        ]),
      );
    });
  });
}
