import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/plant_database.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';

/// In-depth care page for one plant from the built-in catalogue.
class LearnDetailScreen extends StatelessWidget {
  const LearnDetailScreen({super.key, required this.plantId});

  final String plantId;

  @override
  Widget build(BuildContext context) {
    final plant = PlantDatabase.byId(plantId);
    if (plant == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Learn')),
        body: const Center(child: Text('Plant not found.')),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(plant.commonName),
        backgroundColor: AppColors.primarySoft,
        foregroundColor: AppColors.forest,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(plant.emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plant.commonName, style: theme.textTheme.headlineMedium),
                    Text(plant.scientificName,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          fontStyle: FontStyle.italic,
                          color: AppColors.inkSoft,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Family',
                  value: plant.family,
                  icon: Icons.emoji_nature_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Origin',
                  value: plant.origin,
                  icon: Icons.public,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Light',
                  value: plant.sunlight,
                  icon: Icons.light_mode_outlined,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Water',
                  value: plant.water,
                  icon: Icons.water_drop_outlined,
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Temperature',
                  value: plant.temperature,
                  icon: Icons.thermostat_outlined,
                  color: AppColors.warn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'Growth',
                  value: plant.growth,
                  icon: Icons.trending_up_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SectionHeader(title: 'Soil'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(plant.soil, style: theme.textTheme.bodyMedium),
            ),
          ),
          SectionHeader(title: 'Flowering'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(plant.flowering, style: theme.textTheme.bodyMedium),
            ),
          ),
          SectionHeader(title: 'Care summary'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                plant.careSummary.isNotEmpty ? plant.careSummary : plant.care,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          SectionHeader(title: 'Care'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(plant.care, style: theme.textTheme.bodyMedium),
            ),
          ),
          SectionHeader(title: 'Common problems'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(plant.commonProblems, style: theme.textTheme.bodyMedium),
            ),
          ),
          SectionHeader(title: 'Common diseases'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final disease in plant.commonDiseases)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.broken_image_outlined, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(disease, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SectionHeader(title: 'Why it gets sick'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final reason in plant.sicknessReasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warn),
                          const SizedBox(width: 8),
                          Expanded(child: Text(reason, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SectionHeader(title: 'Medicine guidance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tip in plant.medicineGuidance)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.health_and_safety_outlined, size: 16, color: AppColors.teal),
                          const SizedBox(width: 8),
                          Expanded(child: Text(tip, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SectionHeader(title: 'Did you know?'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final fact in plant.facts) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.eco,
                              size: 16, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(fact,
                              style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}