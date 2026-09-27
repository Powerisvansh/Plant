class ConditionReference {
  const ConditionReference({
    required this.id,
    required this.publisher,
    required this.title,
    required this.url,
  });

  final String id;
  final String publisher;
  final String title;
  final String url;
}

class PlantCondition {
  const PlantCondition({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.category,
    required this.symptoms,
    required this.likelyCauses,
    required this.lookAlikes,
    required this.prevention,
    required this.culturalTreatment,
    required this.treatmentTags,
    required this.escalation,
    required this.urgentWarning,
    required this.referenceIds,
  });

  final String id;
  final String commonName;
  final String scientificName;
  final String category;
  final String symptoms;
  final String likelyCauses;
  final String lookAlikes;
  final String prevention;
  final String culturalTreatment;
  final List<String> treatmentTags;
  final String escalation;
  final String urgentWarning;
  final List<String> referenceIds;
}
