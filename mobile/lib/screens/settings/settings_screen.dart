import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';
import '../science_fair/science_fair_screen.dart';
import '../scan/scan_capture_screen.dart';
import 'legal_screen.dart';

/// Settings: screening disclaimers, science-fair extras and about info.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Screening disclaimer'),
              subtitle: const Text(
                  'Show the "not a diagnosis" notice when PlantDoctor opens.'),
              value: settings.settings.showDisclaimers,
              onChanged: settings.setShowDisclaimers,
            ),
          ),
          Card(
            child: SwitchListTile(
              title: const Text('Science-fair extras'),
              subtitle: const Text(
                  'Show live accuracy and timing details on the science-fair demo.'),
              value: settings.settings.scienceFairMode,
              onChanged: settings.setScienceFairMode,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick links',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_a_photo_outlined,
                        color: AppColors.primary),
                    title: const Text('Start a check-up'),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.inkMuted),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ScanCaptureScreen()),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.science_outlined, color: AppColors.teal),
                    title: const Text('Science fair demo'),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.inkMuted),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const ScienceFairScreen()),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined,
                        color: AppColors.primary),
                    title: const Text('Legal & privacy'),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.inkMuted),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LegalScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '${AppConstants.appName} v${AppConstants.version}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Center(
            child: Text(
              'Runs fully offline. Photos never leave this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}