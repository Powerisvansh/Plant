enum PlantProblemCategory {
  fungal,
  bacterial,
  viral,
  pest,
  waterRoots,
  environment,
  nutrition,
}

extension PlantProblemCategoryLabel on PlantProblemCategory {
  String get label => switch (this) {
    PlantProblemCategory.fungal => 'Fungal',
    PlantProblemCategory.bacterial => 'Bacterial',
    PlantProblemCategory.viral => 'Viral',
    PlantProblemCategory.pest => 'Pests',
    PlantProblemCategory.waterRoots => 'Water & roots',
    PlantProblemCategory.environment => 'Environment',
    PlantProblemCategory.nutrition => 'Nutrition',
  };
}

enum PlantProblemUrgency { routine, prompt, urgent }

extension PlantProblemUrgencyLabel on PlantProblemUrgency {
  String get label => switch (this) {
    PlantProblemUrgency.routine => 'Monitor and prevent',
    PlantProblemUrgency.prompt => 'Act promptly',
    PlantProblemUrgency.urgent => 'Urgent help',
  };
}

enum PlantTreatmentType {
  environment,
  sanitation,
  physical,
  biological,
  registeredProduct,
  professionalCare,
}

extension PlantTreatmentTypeLabel on PlantTreatmentType {
  String get label => switch (this) {
    PlantTreatmentType.environment => 'Environment',
    PlantTreatmentType.sanitation => 'Sanitation',
    PlantTreatmentType.physical => 'Physical control',
    PlantTreatmentType.biological => 'Biological control',
    PlantTreatmentType.registeredProduct => 'Registered product',
    PlantTreatmentType.professionalCare => 'Professional care',
  };
}

class PlantTreatment {
  const PlantTreatment({
    required this.type,
    required this.title,
    required this.steps,
  });

  final PlantTreatmentType type;
  final String title;
  final List<String> steps;
}

class PlantHealthEntry {
  const PlantHealthEntry({
    required this.id,
    required this.title,
    required this.scientificName,
    required this.category,
    required this.urgency,
    required this.summary,
    required this.symptoms,
    required this.causes,
    required this.lookAlikes,
    required this.firstAid,
    required this.treatments,
    required this.prevention,
    required this.escalation,
    required this.safetyNote,
    required this.references,
    this.relatedIds = const [],
  });

  final String id;
  final String title;
  final String scientificName;
  final PlantProblemCategory category;
  final PlantProblemUrgency urgency;
  final String summary;
  final List<String> symptoms;
  final List<String> causes;
  final List<String> lookAlikes;
  final List<String> firstAid;
  final List<PlantTreatment> treatments;
  final List<String> prevention;
  final List<String> escalation;
  final String safetyNote;
  final List<String> references;
  final List<String> relatedIds;

  String get searchableText {
    final parts = <String>[
      id,
      title,
      scientificName,
      category.label,
      summary,
      ...symptoms,
      ...causes,
      ...lookAlikes,
    ];
    return parts.join(' ').toLowerCase();
  }
}
