import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/education_content.dart';
import '../../state/providers.dart';
import '../../widgets/health_ring.dart';
import '../../widgets/stat_card.dart';
import '../history/scan_detail_screen.dart';
import '../scan/scan_capture_screen.dart';
import '../science_fair/science_fair_screen.dart';

/// Landing page: the main call to action, science-fair entry point and a
/// glance at recent scans.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _askedDisclaimer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsController>().settings;
      if (_askedDisclaimer || !settings.showDisclaimers) return;
      _askedDisclaimer = true;
      _showDisclaimer();
    });
  }

  Future<void> _showDisclaimer() async {
    final settings = context.read<SettingsController>();
    var keepShowing = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('A screening app, not a lab'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PlantDoctor gives AI-assisted, visual-only hints. It is '
                  'an educational screening tool and cannot replace a '
                  'planting professional or a laboratory test.\n\n'
                  'Nothing you scan is uploaded - analysis runs entirely on '
                  'this phone.',
                ),
              ],
            ),
          ),
          actions: [
            CheckboxListTile(
              value: keepShowing,
              contentPadding: EdgeInsets.zero,
              title: const Text('Show this next time'),
              onChanged: (v) => setState(() => keepShowing = v ?? false),
            ),
            TextButton(
              onPressed: () {
                if (!keepShowing) settings.setShowDisclaimers(false);
                Navigator.of(context).pop();
              },
              child: const Text('I understand'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryController>();
    final recent = history.scans.take(3).toList();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _Header(),
            const SizedBox(height: 18),
            _CheckUpCard(onTap: () => _startScan(context)),
            const SizedBox(height: 14),
            _ScienceFairCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScienceFairScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _TipOfTheDayCard(),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.history, size: 18, color: AppColors.inkMuted),
                const SizedBox(width: 6),
                Text('Recent check-ups',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            if (recent.isEmpty)
              _EmptyRecent(onAction: () => _startScan(context))
            else
              ...recent.map((scan) => _RecentTile(
                    scanId: scan.id,
                    thumbPath: scan.thumbPath,
                    plant: scan.plantGuess,
                    condition: scan.overallCondition,
                    index: scan.healthIndex,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ScanDetailScreen(scanId: scan.id),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.eco, color: Colors.white, size: 30),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppConstants.appName, style: theme.textTheme.headlineMedium),
              Text(AppConstants.tagline, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _CheckUpCard extends StatelessWidget {
  const _CheckUpCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SCAN PLANT',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge!
                          .copyWith(color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Take 1-4 photos of your plant. PlantDoctor screens '
                    'leaf colour, spots, damage and shape - on your device, '
                    'no upload needed.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.forest,
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Scan now'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.upload_file_outlined, size: 20),
                    label: const Text('Upload a photo instead'),
                  ),
                ],
              ),
            ),
            const Icon(Icons.spa, size: 64, color: Color(0x99FFFFFF)),
          ],
        ),
      ),
    );
  }
}

class _ScienceFairCard extends StatelessWidget {
  const _ScienceFairCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showTiming = context.watch<SettingsController>().settings.scienceFairMode;
    return StatCard(
      label: 'Science fair demo',
      value: showTiming ? 'Run the 42-case benchmark' : 'See how PlantDoctor is evaluated',
      icon: Icons.science_outlined,
      color: AppColors.teal,
      onTap: onTap,
    );
  }
}

class _TipOfTheDayCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tip = EducationContent.tipOfDay(DateTime.now());
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lightbulb_outline,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Plant tip of the day',
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(tip.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(tip.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.scanId,
    required this.thumbPath,
    required this.plant,
    required this.condition,
    required this.index,
    required this.onTap,
  });

  final String scanId;
  final String thumbPath;
  final String plant;
  final String condition;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: _thumb(thumbPath),
        title: Text(plant, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(condition,
            style: Theme.of(context).textTheme.bodySmall),
        trailing: SizedBox(
          width: 58,
          child: HealthRing(index: index, size: 54, stroke: 5, label: null),
        ),
      ),
    );
  }

  Widget _thumb(String path) {
    final valid = path.isNotEmpty && File(path).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: valid
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _PhotoFallback(),
              )
            : const _PhotoFallback(),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.primarySoft,
        child: const Icon(Icons.eco_outlined, color: AppColors.primary),
      );
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.onAction});

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('No check-ups yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Your scan history will appear here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('First check-up'),
            ),
          ],
        ),
      ),
    );
  }
}

void _startScan(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ScanCaptureScreen()),
  );
}