import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/scan_models.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/health_ring.dart';
import 'plant_detail_screen.dart';

/// The user's personal plant collection (saved from check-ups or manually).
class MyPlantsScreen extends StatelessWidget {
  const MyPlantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final plants = context.watch<PlantsController>();
    final list = plants.plants;
    return Scaffold(
      appBar: AppBar(title: const Text('My plants')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Track plants you care about and watch their check-ups over time.',
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.yard_outlined,
                    title: 'No saved plants yet',
                    message:
                        'Save a plant after a check-up and its health history '
                        'appears here.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: list.map((p) => _PlantTile(plant: p)).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlantTile extends StatelessWidget {
  const _PlantTile({required this.plant});

  final SavedPlant plant;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlantDetailScreen(plantId: plant.id)),
        ),
        leading: Container(
          width: 56,
          height: 56,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: plant.photoPath.isNotEmpty
                ? Image.file(
                    File(plant.photoPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.eco_outlined, color: AppColors.primary),
                  )
                : const Icon(Icons.eco_outlined, color: AppColors.primary),
          ),
        ),
        title: Text(plant.name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          plant.species.isEmpty ? 'Unknown species' : plant.species,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: SizedBox(
          width: 54,
          child: HealthRing(index: plant.currentHealthIndex, size: 50, stroke: 5),
        ),
      ),
    );
  }
}