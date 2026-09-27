import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/plant_database.dart';

class DiseaseByPlantScreen extends StatefulWidget {
  const DiseaseByPlantScreen({super.key});

  @override
  State<DiseaseByPlantScreen> createState() => _DiseaseByPlantScreenState();
}

class _DiseaseByPlantScreenState extends State<DiseaseByPlantScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = PlantDatabase.searchDiseaseByPlant(_query);

    return Scaffold(
      appBar: AppBar(title: const Text('Disease by plant')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search by plant or disease',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = results[index];
                  final plant = PlantDatabase.byId(item.plantId);
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            plant?.emoji ?? '🌿',
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      title: Text(item.plantName),
                      subtitle: Text(item.disease),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(item.plantName)),
                            body: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    item.summary.isNotEmpty
                                        ? item.summary
                                        : 'This disease is commonly associated with $item.plantName and should be managed by improving care, airflow and product-label guidance.',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
