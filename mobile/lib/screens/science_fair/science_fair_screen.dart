import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/scan_models.dart';
import '../../services/science_fair_service.dart';
import '../../state/providers.dart';
import '../../widgets/stat_card.dart';
import 'experiment_lab_screen.dart';

/// Science-fair demo: runs the real analysis engine over a labelled synthetic
/// test set and reports the honest, measured numbers.
class ScienceFairScreen extends StatefulWidget {
  const ScienceFairScreen({super.key});

  @override
  State<ScienceFairScreen> createState() => _ScienceFairScreenState();
}

class _ScienceFairScreenState extends State<ScienceFairScreen> {
  DemoBenchmarkResult? _result;
  bool _running = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      // Compute on the UI isolate; 42 small synthetic images are quick.
      final result = await Future<DemoBenchmarkResult>.delayed(
        const Duration(milliseconds: 60),
        () => ScienceFairService.run(),
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showExtras = context.watch<SettingsController>().settings.scienceFairMode;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Science fair demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.tealSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How is PlantDoctor evaluated?',
                      style: theme.textTheme.titleLarge!
                          .copyWith(color: AppColors.teal)),
                  const SizedBox(height: 8),
                  Text(
                    'A labelled test set of synthetic plant photos is analysed '
                    'on this device with the same engine you just used. The '
                    'screen then reports real, measured accuracy - nothing is '
                    'pretended or estimated for the demo.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.ink),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: const [
                    Chip(label: Text('7 conditions')),
                    Chip(label: Text('6 seeds each')),
                    Chip(label: Text('42 cases')),
                    Chip(label: Text('fully local')),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_result == null
                ? 'Run the benchmark'
                : 'Run again'),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Card(
              color: AppColors.dangerSoft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
            ),
          if (_result != null) _resultView(theme, _result!, showExtras),
        ],
      ),
    );
  }

  Widget _resultView(ThemeData theme, DemoBenchmarkResult r, bool showExtras) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Accuracy',
                value: _pct(r.accuracy),
                icon: Icons.check_circle_outline,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'Precision',
                value: _pct(r.precision),
                icon: Icons.filter_none,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Recall',
                value: _pct(r.recall),
                icon: Icons.visibility_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: 'F1 score',
                value: r.f1.toStringAsFixed(2),
                icon: Icons.stacked_line_chart,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _MatrixCard(result: r),
        if (showExtras) ...[
          const SizedBox(height: 10),
          _TimingCard(
            avgMs: r.avgInferenceMs,
            samples: r.samples,
            noPlant: '${r.noPlantCorrect}/${r.noPlantSamples}',
          ),
        ],
        const SizedBox(height: 10),
        _ConditionsCard(result: r),
        const SizedBox(height: 10),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.fact_check_outlined, color: AppColors.primary),
            title: Text('Correct predictions (${r.correctExamples.length})',
                style: theme.textTheme.titleSmall),
            children: [for (final e in r.correctExamples) _exampleTile(theme, e, true)],
          ),
        ),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.find_replace_outlined, color: AppColors.warn),
            title: Text('Incorrect / edge cases (${r.incorrectExamples.length})',
                style: theme.textTheme.titleSmall),
            children: [for (final e in r.incorrectExamples) _exampleTile(theme, e, false)],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: AppColors.primarySoft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why these numbers are honest',
                    style: theme.textTheme.titleMedium!
                        .copyWith(color: AppColors.forest)),
                const SizedBox(height: 8),
                Text(
                  'The health index is a simple experimental metric. It can '
                  'miss subtle problems and cannot diagnose. Its measured '
                  'limits - including false negatives - are shown here, not '
                  'hidden.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ExperimentLabScreen()),
          ),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Open Experiment Lab'),
        ),
      ],
    );
  }

  Widget _exampleTile(ThemeData theme, String line, bool correct) {
    return ListTile(
      dense: true,
      title: Text(line, style: theme.textTheme.bodySmall),
      leading: Icon(
        correct ? Icons.check : Icons.close,
        color: correct ? AppColors.primary : AppColors.danger,
        size: 18,
      ),
    );
  }

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}

class _MatrixCard extends StatelessWidget {
  const _MatrixCard({required this.result});

  final DemoBenchmarkResult result;

  @override
  Widget build(BuildContext context) {
    final c = result.confusionAffected;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confusion matrix (affected = patient)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                _cell(theme, 'TP ${c['TP']}', AppColors.primarySoft),
                const SizedBox(width: 8),
                _cell(theme, 'FP ${c['FP']}', AppColors.dangerSoft),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _cell(theme, 'FN ${c['FN']}', AppColors.amber.withValues(alpha: 0.2)),
                const SizedBox(width: 8),
                _cell(theme, 'TN ${c['TN']}', AppColors.tealSoft),
              ],
            ),
            const SizedBox(height: 8),
            Text('FP = false positive (healthy said affected) · '
                'FN = false negative (affected missed)',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _cell(ThemeData theme, String label, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(label,
              style: theme.textTheme.titleMedium!
                  .copyWith(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _ConditionsCard extends StatelessWidget {
  const _ConditionsCard({required this.result});

  final DemoBenchmarkResult result;

  @override
  Widget build(BuildContext context) {
    final conditions = result.byCondition.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accuracy per photo condition',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final c in conditions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _label(c.key),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${(c.value.samples)} cases',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: c.value.accuracy,
                          minHeight: 10,
                          color: c.value.accuracy >= 0.8
                              ? AppColors.primary
                              : (c.value.accuracy >= 0.5
                                  ? AppColors.warn
                                  : AppColors.danger),
                          backgroundColor: AppColors.border,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(c.value.accuracy * 100).round()}%',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall!
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _label(String key) => switch (key) {
        'good' => 'Clear photo',
        'blurry' => 'Blurry photo',
        'dark' => 'Dark photo',
        'occlusion' => 'No plant in frame',
        _ => key,
      };
}

class _TimingCard extends StatelessWidget {
  const _TimingCard(
      {required this.avgMs, required this.samples, required this.noPlant});

  final double avgMs;
  final int samples;
  final String noPlant;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engineering details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _TimingRow(label: 'Avg. inference time', value: '${avgMs.toStringAsFixed(1)} ms / image'),
            const SizedBox(height: 6),
            _TimingRow(label: 'Benchmark cases', value: '$samples'),
            const SizedBox(height: 6),
            _TimingRow(label: 'No-plant frames correctly rejected', value: noPlant),
          ],
        ),
      ),
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium!
                .copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
      ],
    );
  }
}