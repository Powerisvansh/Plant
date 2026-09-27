import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/scan_models.dart';
import '../../state/providers.dart';
import '../../widgets/health_ring.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';

/// Full detail of one saved check-up, reloaded from the database.
class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.scanId});

  final String scanId;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> {
  ScanRecord? _scan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    final history = context.read<HistoryController>();
    for (final s in history.scans) {
      if (s.id == widget.scanId) {
        if (mounted) setState(() => _scan = s);
        return;
      }
    }
  }

  Future<void> _editNotes(ScanRecord scan) async {
    final controller = TextEditingController(text: scan.notes);
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
      await context.read<HistoryController>().updateNotes(scan.id, result);
      if (mounted) setState(() => _scan = scan.copyWith(notes: result));
    }
  }

  Future<void> _delete(ScanRecord scan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this check-up?'),
        content: const Text('The photos stay on your device, but the record is removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      await context.read<HistoryController>().deleteScan(scan.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-up'),
        actions: scan == null
            ? null
            : [
                IconButton(
                  onPressed: () => _editNotes(scan),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit notes',
                ),
                IconButton(
                  onPressed: () => _delete(scan),
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  tooltip: 'Delete',
                ),
              ],
      ),
      body: scan == null
          ? const Center(child: CircularProgressIndicator())
          : _body(scan),
    );
  }

  Widget _body(ScanRecord scan) {
    final theme = Theme.of(context);
    final d = scan.createdAt;
    final followUp = _followUpMap(scan.followUp);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            HealthRing(
                index: scan.healthIndex,
                label: scan.healthIndex < 55 ? 'Concern' : 'OK',
                size: 84),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scan.plantGuess, style: theme.textTheme.titleLarge),
                  if (scan.scientificGuess.isNotEmpty)
                    Text(scan.scientificGuess,
                        style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
Text(
                    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
                    '· ${d.hour}:${d.minute.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    scan.overallCondition,
                    style: theme.textTheme.titleMedium!
                        .copyWith(color: healthColor(scan.healthIndex)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Identified as', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  scan.identificationUncertain
                      ? 'Guess with ${(scan.identificationConfidence * 100).round()}% confidence '
                          '(morphology only - not confirmed)'
                      : '${(scan.identificationConfidence * 100).round()}% match',
                  style: theme.textTheme.bodySmall,
                ),
                if (scan.observedIndicators.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Observed', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  for (final ind in scan.observedIndicators)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(ind,
                                  style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (scan.observedIndicators.isNotEmpty ||
            scan.causeLabels.isNotEmpty) ...[
          SectionHeader(title: 'Possible explanations'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in scan.causeLabels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.troubleshoot_outlined,
                              size: 16, color: AppColors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(c, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (followUp.isNotEmpty) ...[
          SectionHeader(title: 'Follow-up answers'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in followUp.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: StatCard(label: e.key, value: e.value),
                    ),
                ],
              ),
            ),
          ),
        ],
        SectionHeader(title: 'Notes'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              scan.notes.isEmpty ? 'No notes yet.' : scan.notes,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Photos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < scan.imagePaths.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(scan.imagePaths[i]),
                errorBuilder: (_, _, _) => Container(
                  height: 120,
                  color: AppColors.border,
                  child: const Center(child: Text('Photo not available')),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Map<String, String> _followUpMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    final parts = raw.split('\n');
    const labels = ['Where the plant is', 'Watering frequency', 'Problem noticed'];
    final out = <String, String>{};
    for (var i = 0; i < parts.length && i < labels.length; i++) {
      if (parts[i].trim().isNotEmpty) out[labels[i]] = parts[i].trim();
    }
    return out;
  }
}

extension on ScanRecord {
  ScanRecord copyWith({String? notes}) => ScanRecord(
        id: id,
        createdAt: createdAt,
        thumbPath: thumbPath,
        imagePaths: imagePaths,
        imageSubjects: imageSubjects,
        plantGuess: plantGuess,
        scientificGuess: scientificGuess,
        identificationConfidence: identificationConfidence,
        identificationUncertain: identificationUncertain,
        healthIndex: healthIndex,
        overallCondition: overallCondition,
        observedIndicators: observedIndicators,
        causeLabels: causeLabels,
        followUp: followUp,
        notes: notes ?? this.notes,
        savedPlantId: savedPlantId,
      );
}