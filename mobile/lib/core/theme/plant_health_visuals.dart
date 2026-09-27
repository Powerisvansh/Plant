import 'package:flutter/material.dart';

import 'app_theme.dart';
import '../../models/plant_health_models.dart';

extension PlantHealthCategoryVisuals on PlantProblemCategory {
  Color get color => switch (this) {
    PlantProblemCategory.fungal => AppColors.amber,
    PlantProblemCategory.bacterial => AppColors.danger,
    PlantProblemCategory.viral => AppColors.warn,
    PlantProblemCategory.pest => AppColors.teal,
    PlantProblemCategory.waterRoots => AppColors.primary,
    PlantProblemCategory.environment => AppColors.inkSoft,
    PlantProblemCategory.nutrition => AppColors.forest,
  };

  Color get textColor => switch (this) {
    PlantProblemCategory.fungal => const Color(0xFF704800),
    PlantProblemCategory.bacterial => const Color(0xFFB3261E),
    PlantProblemCategory.viral => const Color(0xFF93430B),
    PlantProblemCategory.pest => const Color(0xFF00695C),
    PlantProblemCategory.waterRoots => const Color(0xFF1B5E20),
    PlantProblemCategory.environment => const Color(0xFF455A64),
    PlantProblemCategory.nutrition => const Color(0xFF33691E),
  };

  Color get softColor => switch (this) {
    PlantProblemCategory.fungal => const Color(0xFFFFF8E1),
    PlantProblemCategory.bacterial => AppColors.dangerSoft,
    PlantProblemCategory.viral => const Color(0xFFFFF3E0),
    PlantProblemCategory.pest => AppColors.tealSoft,
    PlantProblemCategory.waterRoots => AppColors.primarySoft,
    PlantProblemCategory.environment => const Color(0xFFECEFF1),
    PlantProblemCategory.nutrition => const Color(0xFFF1F8E9),
  };

  IconData get icon => switch (this) {
    PlantProblemCategory.fungal => Icons.coronavirus_outlined,
    PlantProblemCategory.bacterial => Icons.science_outlined,
    PlantProblemCategory.viral => Icons.blur_on_outlined,
    PlantProblemCategory.pest => Icons.bug_report_outlined,
    PlantProblemCategory.waterRoots => Icons.water_drop_outlined,
    PlantProblemCategory.environment => Icons.eco_outlined,
    PlantProblemCategory.nutrition => Icons.science_outlined,
  };
}

extension PlantHealthUrgencyVisuals on PlantProblemUrgency {
  Color get color => switch (this) {
    PlantProblemUrgency.routine => AppColors.teal,
    PlantProblemUrgency.prompt => AppColors.warn,
    PlantProblemUrgency.urgent => AppColors.danger,
  };

  Color get textColor => switch (this) {
    PlantProblemUrgency.routine => const Color(0xFF00695C),
    PlantProblemUrgency.prompt => const Color(0xFF93430B),
    PlantProblemUrgency.urgent => const Color(0xFFB3261E),
  };

  Color get softColor => switch (this) {
    PlantProblemUrgency.routine => AppColors.tealSoft,
    PlantProblemUrgency.prompt => const Color(0xFFFFF3E0),
    PlantProblemUrgency.urgent => AppColors.dangerSoft,
  };
}
