import '../models/analysis_models.dart';

/// UI formatting helpers shared across screens.
String subjectLabel(ImageSubjectType subject) => switch (subject) {
      ImageSubjectType.wholePlant => 'Whole plant',
      ImageSubjectType.leaf => 'Leaf close-up',
      ImageSubjectType.affectedArea => 'Affected area',
      ImageSubjectType.stemFruit => 'Stem / fruit',
      ImageSubjectType.unknown => 'General',
    };

String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

String gradeLabel(int index) {
  if (index >= 85) return 'Excellent';
  if (index >= 70) return 'Good';
  if (index >= 55) return 'Needs attention';
  if (index >= 35) return 'Concerning';
  return 'Poor';
}