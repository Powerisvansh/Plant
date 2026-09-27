import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/scan_models.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/health_ring.dart';
import 'scan_detail_screen.dart';

/// Chronological log of saved check-ups.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryController>().scans;
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: history.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No check-ups yet',
              message:
                  'Finished check-ups are saved here so you can compare '
                  'your plant over time.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, i) => _ScanTile(scan: history[i]),
            ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.scan});

  final ScanRecord scan;

  @override
  Widget build(BuildContext context) {
    final d = scan.createdAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ScanDetailScreen(scanId: scan.id)),
        ),
        leading: _thumb(),
        title: Text(scan.plantGuess, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
          '· ${scan.overallCondition}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: SizedBox(
          width: 54,
          child: HealthRing(index: scan.healthIndex, size: 50, stroke: 5),
        ),
      ),
    );
  }

  Widget _thumb() {
    final valid = scan.thumbPath.isNotEmpty && File(scan.thumbPath).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: valid
            ? Image.file(
                File(scan.thumbPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.primarySoft,
        child: const Icon(Icons.eco_outlined, color: AppColors.primary),
      );
}