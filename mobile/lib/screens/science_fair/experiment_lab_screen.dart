import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/scan_models.dart';
import '../../services/science_fair_service.dart';
import '../../services/synthetic_samples.dart';

/// Experiment Lab: compares measurements between a synthetic healthy leaf and
/// a diseased leaf, side by side, using the real engine.
class ExperimentLabScreen extends StatefulWidget {
  const ExperimentLabScreen({super.key});

  @override
  State<ExperimentLabScreen> createState() => _ExperimentLabScreenState();
}

class _ExperimentLabScreenState extends State<ExperimentLabScreen> {
  late Future<ExperimentLabResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _compute();
  }

  Future<ExperimentLabResult> _compute() async {
    final healthy = SyntheticSamples.leaf(seed: 17, effect: SymptomEffect.healthy);
    final diseased = SyntheticSamples.leaf(seed: 23, effect: SymptomEffect.diseased);
    return ExperimentLabResult.compare(healthy, diseased);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Experiment Lab')),
      body: FutureBuilder<ExperimentLabResult>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snap.data;
          if (result == null) {
            return const Center(child: Text('Could not run the experiment.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppColors.tealSoft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'One leaf is generated healthy, the other carries brown '
                    'lesions and yellowing. Both are measured with the same '
                    'engine; the table compares the visible signals.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.ink),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _MetricHeader(label: 'Healthy leaf', color: AppColors.primary)),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricHeader(label: 'Diseased leaf', color: AppColors.danger)),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      for (final c in result.comparisons) _comparisonRow(theme, c),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _comparisonRow(ThemeData theme, ExperimentComparison c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(c.metric, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 1,
            child: Text(c.healthyValue,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: Text(c.affectedValue,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w700, color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _MetricHeader extends StatelessWidget {
  const _MetricHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(color: color)),
      ),
    );
  }
}