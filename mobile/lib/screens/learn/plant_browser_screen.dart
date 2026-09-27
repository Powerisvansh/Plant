import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/plant_database.dart';
import 'learn_detail_screen.dart';

class PlantBrowserScreen extends StatefulWidget {
  const PlantBrowserScreen({super.key});

  @override
  State<PlantBrowserScreen> createState() => _PlantBrowserScreenState();
}

class _PlantBrowserScreenState extends State<PlantBrowserScreen> {
  String _query = '';
  String _category = 'all';

  @override
  Widget build(BuildContext context) {
    final plants = PlantDatabase.search(_query, category: _category);

    return Scaffold(
      appBar: AppBar(title: const Text('Browse plants')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search plants, family, care, or origin',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: PlantDatabase.categoryLabels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final label = PlantDatabase.categoryLabels[index];
                  final selected = _category == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = label),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: plants.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final plant = plants[index];
                  return Card(
                    child: ListTile(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LearnDetailScreen(plantId: plant.id),
                        ),
                      ),
                      leading: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(plant.emoji, style: const TextStyle(fontSize: 26))),
                      ),
                      title: Text(plant.commonName),
                      subtitle: Text(plant.scientificName),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
