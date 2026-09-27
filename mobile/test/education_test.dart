import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plantdoctor/models/education_models.dart';
import 'package:plantdoctor/services/education_content.dart';

void main() {
  group('EducationContent', () {
    test('tip of the day is deterministic per date', () {
      final a = EducationContent.tipOfDay(DateTime(2026, 9, 24, 12));
      final b = EducationContent.tipOfDay(DateTime(2026, 9, 24, 20));
      expect(a.title, b.title);
    });

    test('tip rotates across days', () {
      final seen = <String>{};
      for (var day = 1; day <= 12; day++) {
        seen.add(EducationContent.tipOfDay(DateTime(2026, 9, day)).title);
      }
      expect(seen.length, greaterThan(6),
          reason: 'tips should rotate, not repeat constantly');
    });

    test('learn topics cover the required science-fair subjects', () {
      final titles = EducationContent.topics.map((t) => t.id).toSet();
      expect(titles, containsAll([
        'photosynthesis',
        'plant_biology',
        'nutrition',
        'diseases',
        'pests',
        'water_stress',
        'soil',
        'plant_care',
        'how_analysis_works',
        'ai_limits',
      ]));
    });

    test('every topic resolves by id and has content', () {
      for (final topic in EducationContent.topics) {
        final found = EducationContent.byId(topic.id);
        expect(found, isNotNull, reason: '${topic.id} must resolve');
        expect(topic.sections, isNotEmpty,
            reason: '${topic.id} should have sections');
      }
    });

    test('LearnTopic is an immutable record-based model', () {
      const topic = LearnTopic(
        id: 'x',
        title: 'X',
        subtitle: 'S',
        icon: Icons.eco,
        color: Colors.green,
        sections: [('H', 'B')],
      );
      expect(topic.intro, 'B');
    });
  });
}