import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/scan_models.dart';
import '../../state/providers.dart';
import '../../widgets/health_ring.dart';
import '../../widgets/section_header.dart';
import '../history/scan_detail_screen.dart';

/// Detail page for one saved plant: health history, notes, follow-up scans.
class PlantDetailScreen extends StatefulWidget {
  const PlantDetailScreen({super.key, required this.plantId});

  final String plantId;

  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  late Future<List<ScanRecord>> _scansFuture;

  @override
  void initState() {
    super.initState();
    _scansFuture =
        context.read<HistoryController>().scansForPlant(widget.plantId);
  }

  Future<void> _editNotes(SavedPlant plant) async {
    final controller = TextEditingController(text: plant.notes);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notes'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      if (!mounted) return;
      await context.read<PlantsController>().updateNotes(plant.id, result);
    }
  }

  Future<void> _delete(SavedPlant plant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove plant?'),
        content: const Text(
            'This removes the plant card. Scans stay in history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      await context.read<PlantsController>().deletePlant(plant.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final plant = context.watch<PlantsController>().byId(widget.plantId);
    if (plant == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plant')),
        body: const Center(child: Text('This plant is no longer saved.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(plant.name),
        actions: [
          IconButton(
            onPressed: () => _editNotes(plant),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit notes',
          ),
          IconButton(
            onPressed: () => _delete(plant),
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            tooltip: 'Remove plant',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hero(plant),
          const SizedBox(height: 14),
          SectionHeader(
            title: 'Notes',
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                plant.notes.isEmpty ? 'No notes yet. Tap edit to add some.' : plant.notes,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SectionHeader(
            title: 'Health history',
            subtitle: 'Saved check-ups for this plant',
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
          FutureBuilder<List<ScanRecord>>(
            future: _scansFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final scans = snap.data ?? const <ScanRecord>[];
              if (scans.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No check-ups linked to this plant yet. Save the next '
                      'check-up with "Also save to My Plants" to link it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                );
              }
              return Column(
                children: scans
                    .map((s) => _ScanRow(scan: s))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hero(SavedPlant plant) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: plant.photoPath.isNotEmpty
                  ? Image.file(
                      File(plant.photoPath),
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _noPhoto(),
                    )
                  : _noPhoto(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plant.name, style: Theme.of(context).textTheme.titleLarge),
                  Text(plant.species.isEmpty ? 'Unknown species' : plant.species,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  Text('Latest health index',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      HealthRing(
                          index: plant.currentHealthIndex,
                          size: 46,
                          stroke: 5),
                      const SizedBox(width: 12),
                      Text(
                        '${plant.currentHealthIndex}/100',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium!
                            .copyWith(color: AppColors.ink),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noPhoto() => Container(
        width: 84,
        height: 84,
        color: AppColors.primarySoft,
        child: const Icon(Icons.eco_outlined, color: AppColors.primary),
      );
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.scan});

  final ScanRecord scan;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ScanDetailScreen(scanId: scan.id)),
        ),
        title: Text(scan.plantGuess, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          '${_date(scan)} · ${scan.overallCondition}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: SizedBox(
          width: 46,
          child: HealthRing(index: scan.healthIndex, size: 44, stroke: 4),
        ),
      ),
    );
  }

  String _date(ScanRecord s) {
    final d = s.createdAt;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}