/// Read models for the bundled offline knowledge base.
///
/// Every field is nullable on purpose. The database ships with real taxonomy
/// for thousands of species but with genuinely empty treatment, toxicity and
/// safety tables. These models represent that honestly: a null field becomes an
/// explicit "not verified" state in the UI rather than a blank space or,
/// worse, an invented value.
library;

/// One row of the `plants` table plus its joined names.
class KnowledgePlant {
  const KnowledgePlant({
    required this.id,
    required this.slug,
    required this.scientificName,
    this.commonName,
    this.canonicalName,
    this.genus,
    this.species,
    this.family,
    this.orderName,
    this.className,
    this.phylum,
    this.kingdom,
    this.authorship,
    this.taxonomicStatus,
    this.description,
    this.identificationFeatures,
    this.growthHabit,
    this.plantHeight,
    this.toxicityStatus,
    this.verificationStatus,
    this.lastVerified,
    this.vernacularNames = const [],
  });

  final int id;
  final String slug;
  final String scientificName;
  final String? commonName;
  final String? canonicalName;
  final String? genus;
  final String? species;
  final String? family;
  final String? orderName;
  final String? className;
  final String? phylum;
  final String? kingdom;
  final String? authorship;
  final String? taxonomicStatus;
  final String? description;
  final String? identificationFeatures;
  final String? growthHabit;
  final String? plantHeight;
  final String? toxicityStatus;
  final String? verificationStatus;
  final String? lastVerified;
  final List<String> vernacularNames;

  /// Best available display name. Falls back to the scientific name rather than
  /// to a placeholder, because a species with no common name is still a real
  /// record and its binomial is the correct thing to show.
  String get displayName =>
      (commonName != null && commonName!.trim().isNotEmpty)
          ? commonName!.trim()
          : scientificName;

  bool get hasCommonName =>
      commonName != null && commonName!.trim().isNotEmpty;

  /// `UNKNOWN` is treated as unknown, never as safe.
  bool get toxicityKnown =>
      toxicityStatus != null &&
      const {'NON_TOXIC_REPORTED', 'TOXIC', 'POTENTIALLY_TOXIC'}
          .contains(toxicityStatus!.trim().toUpperCase());

  String get toxicityDisplay =>
      toxicityStatus == null || toxicityStatus!.trim().isEmpty
          ? 'Unknown'
          : toxicityStatus!.trim();

  String? get familyLine {
    final parts = <String>[
      if (kingdom != null && kingdom!.isNotEmpty) kingdom!,
      if (phylum != null && phylum!.isNotEmpty) phylum!,
      if (className != null && className!.isNotEmpty) className!,
      if (orderName != null && orderName!.isNotEmpty) orderName!,
      if (family != null && family!.isNotEmpty) family!,
      if (genus != null && genus!.isNotEmpty) genus!,
    ];
    return parts.isEmpty ? null : parts.join(' \u203a ');
  }

  factory KnowledgePlant.fromRow(
    Map<String, Object?> row, {
    List<String> vernacularNames = const [],
  }) =>
      KnowledgePlant(
        id: row['id']! as int,
        slug: (row['slug'] as String?) ?? '',
        scientificName: (row['scientific_name'] as String?) ?? '',
        commonName: row['common_name'] as String?,
        canonicalName: row['canonical_name'] as String?,
        genus: row['genus'] as String?,
        species: row['species'] as String?,
        family: row['family'] as String?,
        orderName: row['order_name'] as String?,
        className: row['class_name'] as String?,
        phylum: row['phylum'] as String?,
        kingdom: row['kingdom'] as String?,
        authorship: row['authorship'] as String?,
        taxonomicStatus: row['taxonomic_status'] as String?,
        description: row['description'] as String?,
        identificationFeatures: row['identification_features'] as String?,
        growthHabit: row['growth_habit'] as String?,
        plantHeight: row['plant_height'] as String?,
        toxicityStatus: row['toxicity_status'] as String?,
        verificationStatus: row['verification_status'] as String?,
        lastVerified: row['last_verified'] as String?,
        vernacularNames: vernacularNames,
      );
}

/// A trait row from `plant_characteristics` (trait/value pairs).
class KnowledgeTrait {
  const KnowledgeTrait(this.trait, this.value);
  final String trait;
  final String value;
}

/// A `plant_distribution` row.
class KnowledgeDistribution {
  const KnowledgeDistribution(this.region, this.kind);
  final String region;
  final String? kind;
}

/// A `plant_growth` row. Every field is nullable because the table ships empty.
class KnowledgeGrowth {
  const KnowledgeGrowth({
    this.growthHabit,
    this.plantHeight,
    this.climate,
    this.temperatureRange,
    this.soilType,
    this.soilPh,
    this.waterRequirement,
    this.sunlightRequirement,
    this.humidity,
    this.growingSeason,
    this.sowingSeason,
    this.floweringSeason,
    this.fruitingSeason,
    this.harvestPeriod,
    this.growthDuration,
    this.propagation,
    this.cultivationInformation,
  });

  final String? growthHabit;
  final String? plantHeight;
  final String? climate;
  final String? temperatureRange;
  final String? soilType;
  final String? soilPh;
  final String? waterRequirement;
  final String? sunlightRequirement;
  final String? humidity;
  final String? growingSeason;
  final String? sowingSeason;
  final String? floweringSeason;
  final String? fruitingSeason;
  final String? harvestPeriod;
  final String? growthDuration;
  final String? propagation;
  final String? cultivationInformation;

  /// True when at least one agronomic field has actually been sourced.
  bool get hasAnyData => <String?>[
        growthHabit, plantHeight, climate, temperatureRange, soilType, soilPh,
        waterRequirement, sunlightRequirement, humidity, growingSeason,
        sowingSeason, floweringSeason, fruitingSeason, harvestPeriod,
        growthDuration, propagation, cultivationInformation,
      ].any((v) => v != null && v.trim().isNotEmpty);

  /// Which labelled fields can be shown, in display order.
  List<MapEntry<String, String?>> get labelled => <MapEntry<String, String?>>[
        MapEntry('Growth habit', growthHabit),
        MapEntry('Height', plantHeight),
        MapEntry('Climate', climate),
        MapEntry('Temperature range', temperatureRange),
        MapEntry('Soil type', soilType),
        MapEntry('Soil pH', soilPh),
        MapEntry('Water requirement', waterRequirement),
        MapEntry('Sunlight', sunlightRequirement),
        MapEntry('Humidity', humidity),
        MapEntry('Growing season', growingSeason),
        MapEntry('Sowing season', sowingSeason),
        MapEntry('Flowering season', floweringSeason),
        MapEntry('Fruiting season', fruitingSeason),
        MapEntry('Harvest period', harvestPeriod),
        MapEntry('Growth duration', growthDuration),
        MapEntry('Propagation', propagation),
        MapEntry('Cultivation', cultivationInformation),
      ].where((e) => e.value != null && e.value!.trim().isNotEmpty).toList();

  factory KnowledgeGrowth.fromRow(Map<String, Object?> row) => KnowledgeGrowth(
        growthHabit: row['growth_habit'] as String?,
        plantHeight: row['plant_height'] as String?,
        climate: row['climate'] as String?,
        temperatureRange: row['temperature_range'] as String?,
        soilType: row['soil_type'] as String?,
        soilPh: row['soil_ph'] as String?,
        waterRequirement: row['water_requirement'] as String?,
        sunlightRequirement: row['sunlight_requirement'] as String?,
        humidity: row['humidity'] as String?,
        growingSeason: row['growing_season'] as String?,
        sowingSeason: row['sowing_season'] as String?,
        floweringSeason: row['flowering_season'] as String?,
        fruitingSeason: row['fruiting_season'] as String?,
        harvestPeriod: row['harvest_period'] as String?,
        growthDuration: row['growth_duration'] as String?,
        propagation: row['propagation'] as String?,
        cultivationInformation: row['cultivation_information'] as String?,
      );
}

/// A disease from the `diseases` table, joined to a plant via `plant_diseases`.
class KnowledgeDisease {
  const KnowledgeDisease({
    required this.id,
    required this.name,
    this.slug,
    this.pathogenName,
    this.pathogenKind,
    this.description,
    this.symptoms,
    this.visualSymptoms,
    this.earlySymptoms,
    this.advancedSymptoms,
    this.favorableConditions,
    this.transmission,
    this.prevention,
    this.management,
    this.severity,
    this.verificationStatus,
    this.lastVerified,
    this.symptoms_ = const [],
  });

  final int id;
  final String name;
  final String? slug;
  final String? pathogenName;
  final String? pathogenKind;
  final String? description;
  final String? symptoms;
  final String? visualSymptoms;
  final String? earlySymptoms;
  final String? advancedSymptoms;
  final String? favorableConditions;
  final String? transmission;
  final String? prevention;
  final String? management;
  final String? severity;
  final String? verificationStatus;
  final String? lastVerified;
  final List<KnowledgeSymptom> symptoms_;

  bool get isVerified =>
      (verificationStatus ?? '').trim().toUpperCase() == 'VERIFIED';

  factory KnowledgeDisease.fromRow(Map<String, Object?> row) =>
      KnowledgeDisease(
        id: row['id']! as int,
        name: (row['name'] as String?) ?? 'Unnamed condition',
        slug: row['slug'] as String?,
        pathogenName: row['pathogen_name'] as String?,
        pathogenKind: row['pathogen_kind'] as String?,
        description: row['description'] as String?,
        symptoms: row['symptoms'] as String?,
        visualSymptoms: row['visual_symptoms'] as String?,
        earlySymptoms: row['early_symptoms'] as String?,
        advancedSymptoms: row['advanced_symptoms'] as String?,
        favorableConditions: row['favorable_conditions'] as String?,
        transmission: row['transmission'] as String?,
        prevention: row['prevention'] as String?,
        management: row['management'] as String?,
        severity: row['severity'] as String?,
        verificationStatus: row['verification_status'] as String?,
        lastVerified: row['last_verified'] as String?,
      );
}

/// A `disease_symptoms` / `pest_symptoms` row.
class KnowledgeSymptom {
  const KnowledgeSymptom(this.symptom, this.plantPart, [this.stage]);
  final String symptom;
  final String? plantPart;
  final String? stage;
}

/// A pest from the `pests` table.
class KnowledgePest {
  const KnowledgePest({
    required this.id,
    required this.name,
    this.slug,
    this.scientificName,
    this.appearance,
    this.feedingBehavior,
    this.damageSymptoms,
    this.lifeStages,
    this.prevention,
    this.management,
    this.severity,
    this.verificationStatus,
    this.lastVerified,
    this.symptoms = const [],
  });

  final int id;
  final String name;
  final String? slug;
  final String? scientificName;
  final String? appearance;
  final String? feedingBehavior;
  final String? damageSymptoms;
  final String? lifeStages;
  final String? prevention;
  final String? management;
  final String? severity;
  final String? verificationStatus;
  final String? lastVerified;
  final List<KnowledgeSymptom> symptoms;

  bool get isVerified =>
      (verificationStatus ?? '').trim().toUpperCase() == 'VERIFIED';

  factory KnowledgePest.fromRow(Map<String, Object?> row) => KnowledgePest(
        id: row['id']! as int,
        name: (row['name'] as String?) ?? 'Unnamed pest',
        slug: row['slug'] as String?,
        scientificName: row['scientific_name'] as String?,
        appearance: row['appearance'] as String?,
        feedingBehavior: row['feeding_behavior'] as String?,
        damageSymptoms: row['damage_symptoms'] as String?,
        lifeStages: row['life_stages'] as String?,
        prevention: row['prevention'] as String?,
        management: row['management'] as String?,
        severity: row['severity'] as String?,
        verificationStatus: row['verification_status'] as String?,
        lastVerified: row['last_verified'] as String?,
      );
}

/// A `nutrient_deficiencies` row.
class KnowledgeDeficiency {
  const KnowledgeDeficiency({
    required this.id,
    required this.nutrient,
    this.slug,
    this.symbol,
    this.description,
    this.visualSigns,
    this.affectedParts,
    this.similarConditions,
    this.soilFactors,
    this.correctionGuidance,
    this.verificationStatus,
  });

  final int id;
  final String nutrient;
  final String? slug;
  final String? symbol;
  final String? description;
  final String? visualSigns;
  final String? affectedParts;
  final String? similarConditions;
  final String? soilFactors;
  final String? correctionGuidance;
  final String? verificationStatus;

  factory KnowledgeDeficiency.fromRow(Map<String, Object?> row) =>
      KnowledgeDeficiency(
        id: row['id']! as int,
        nutrient: (row['nutrient'] as String?) ?? 'Unnamed nutrient',
        slug: row['slug'] as String?,
        symbol: row['symbol'] as String?,
        description: row['description'] as String?,
        visualSigns: row['visual_signs'] as String?,
        affectedParts: row['affected_parts'] as String?,
        similarConditions: row['similar_conditions'] as String?,
        soilFactors: row['soil_factors'] as String?,
        correctionGuidance: row['correction_guidance'] as String?,
        verificationStatus: row['verification_status'] as String?,
      );
}

/// An `environmental_stresses` row.
class KnowledgeStress {
  const KnowledgeStress({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.visualSigns,
    this.similarConditions,
    this.correctionGuidance,
    this.verificationStatus,
  });

  final int id;
  final String name;
  final String? slug;
  final String? description;
  final String? visualSigns;
  final String? similarConditions;
  final String? correctionGuidance;
  final String? verificationStatus;

  factory KnowledgeStress.fromRow(Map<String, Object?> row) => KnowledgeStress(
        id: row['id']! as int,
        name: (row['name'] as String?) ?? 'Unnamed stress',
        slug: row['slug'] as String?,
        description: row['description'] as String?,
        visualSigns: row['visual_signs'] as String?,
        similarConditions: row['similar_conditions'] as String?,
        correctionGuidance: row['correction_guidance'] as String?,
        verificationStatus: row['verification_status'] as String?,
      );
}

/// A treatment row. The table ships empty, so this model exists to carry the
/// label-gated fields and to let the UI say "unavailable" without inventing.
class KnowledgeTreatment {
  const KnowledgeTreatment({
    required this.id,
    required this.name,
    this.slug,
    this.treatmentType,
    this.description,
    this.applicationMethod,
    this.frequency,
    this.timing,
    this.recommendedDosage,
    this.dosageUnit,
    this.waterVolume,
    this.preHarvestInterval,
    this.waitingPeriod,
    this.safetyPrecautions,
    this.protectiveEquipment,
    this.labelPageReference,
    this.labelUrl,
    this.lastVerified,
    this.verificationStatus,
  });

  final int id;
  final String name;
  final String? slug;
  final String? treatmentType;
  final String? description;
  final String? applicationMethod;
  final String? frequency;
  final String? timing;
  final String? recommendedDosage;
  final String? dosageUnit;
  final String? waterVolume;
  final String? preHarvestInterval;
  final String? waitingPeriod;
  final String? safetyPrecautions;
  final String? protectiveEquipment;
  final String? labelPageReference;
  final String? labelUrl;
  final String? lastVerified;
  final String? verificationStatus;

  /// A dosage is only ever shown when the label evidence is complete. This is
  /// the app-side mirror of the label gate in the database views.
  bool get hasLabelBackedDosage =>
      (recommendedDosage != null && recommendedDosage!.trim().isNotEmpty) &&
      (labelUrl != null && labelUrl!.trim().isNotEmpty) &&
      (labelPageReference != null && labelPageReference!.trim().isNotEmpty) &&
      (lastVerified != null && lastVerified!.trim().isNotEmpty);

  /// The dosage line, or the exact wording used when it cannot be given.
  String? get dosageDisplay {
    if (!hasLabelBackedDosage) return null;
    final unit = dosageUnit == null || dosageUnit!.trim().isEmpty
        ? ''
        : ' ${dosageUnit!.trim()}';
    return '$recommendedDosage$unit';
  }

  factory KnowledgeTreatment.fromRow(Map<String, Object?> row) =>
      KnowledgeTreatment(
        id: row['id']! as int,
        name: (row['name'] as String?) ?? 'Unnamed treatment',
        slug: row['slug'] as String?,
        treatmentType: row['treatment_type'] as String?,
        description: row['description'] as String?,
        applicationMethod: row['application_method'] as String?,
        frequency: row['frequency'] as String?,
        timing: row['timing'] as String?,
        recommendedDosage: row['recommended_dosage'] as String?,
        dosageUnit: row['dosage_unit'] as String?,
        waterVolume: row['water_volume'] as String?,
        preHarvestInterval: row['pre_harvest_interval'] as String?,
        waitingPeriod: row['waiting_period'] as String?,
        safetyPrecautions: row['safety_precautions'] as String?,
        protectiveEquipment: row['protective_equipment'] as String?,
        labelPageReference: row['label_page_reference'] as String?,
        labelUrl: row['label_url'] as String?,
        lastVerified: row['last_verified'] as String?,
        verificationStatus: row['verification_status'] as String?,
      );
}

/// A registered source row, for the "Sources" section of a plant.
class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.name,
    this.sourceKey,
    this.kind,
    this.organization,
    this.url,
    this.license,
    this.attribution,
    this.version,
    this.retrievedAt,
  });

  final int id;
  final String name;
  final String? sourceKey;
  final String? kind;
  final String? organization;
  final String? url;
  final String? license;
  final String? attribution;
  final String? version;
  final String? retrievedAt;

  factory KnowledgeSource.fromRow(Map<String, Object?> row) => KnowledgeSource(
        id: row['id']! as int,
        name: (row['name'] as String?) ?? 'Unnamed source',
        sourceKey: row['source_key'] as String?,
        kind: row['kind'] as String?,
        organization: row['organization'] as String?,
        url: row['url'] as String?,
        license: row['license'] as String?,
        attribution: row['attribution'] as String?,
        version: row['version'] as String?,
        retrievedAt: row['retrieved_at'] as String?,
      );
}

/// The complete retrieved profile for one plant, as the specification's
/// knowledge-retrieval step requires: profile, diseases, pests, deficiencies,
/// growth, toxicity, treatments, prevention and sources - in one call, so the
/// detail screen never has to guess at a missing section.
class KnowledgeProfile {
  const KnowledgeProfile({
    required this.plant,
    this.traits = const [],
    this.distribution = const [],
    this.growth,
    this.diseases = const [],
    this.pests = const [],
    this.deficiencies = const [],
    this.stresses = const [],
    this.treatments = const [],
    this.sources = const [],
    this.toxicityStatus,
    this.toxicityWarning,
    this.hasCultivationData = false,
  });

  final KnowledgePlant plant;
  final List<KnowledgeTrait> traits;
  final List<KnowledgeDistribution> distribution;
  final KnowledgeGrowth? growth;
  final List<KnowledgeDisease> diseases;
  final List<KnowledgePest> pests;
  final List<KnowledgeDeficiency> deficiencies;
  final List<KnowledgeStress> stresses;
  final List<KnowledgeTreatment> treatments;
  final List<KnowledgeSource> sources;
  final String? toxicityStatus;
  final String? toxicityWarning;
  final bool hasCultivationData;

  /// True when a label-verified dosage exists. Drives the exact wording
  /// "Verified dosage information is unavailable." when it does not.
  bool get hasVerifiedDosage =>
      treatments.any((t) => t.hasLabelBackedDosage);

  /// The banner shown when no verified dosage can be given. Never a substitute
  /// dose, never a typical range.
  String get dosageUnavailableNotice =>
      'Verified dosage information is unavailable. No label-verified treatment '
      'record exists for this plant in this release. Start with cultural and '
      'physical controls, and consult a local agricultural advisory service.';

  String get toxicityNotice =>
      'Toxicity status: $toxicityStatusText. Do not consume or use medicinally '
      'without independent verification.';

  String get toxicityStatusText {
    final value = toxicityStatus?.trim();
    if (value == null || value.isEmpty) return 'Unknown';
    return value;
  }
}
