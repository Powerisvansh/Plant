import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../services/condition_content.dart';
import '../../widgets/section_header.dart';

class ConditionDetailScreen extends StatelessWidget {
  const ConditionDetailScreen({super.key, required this.conditionId});

  final String conditionId;

  @override
  Widget build(BuildContext context) {
    final condition = ConditionContent.byId(conditionId);
    if (condition == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Condition guide')),
        body: const Center(child: Text('Condition not found.')),
      );
    }

    final theme = Theme.of(context);
    final categoryColor = _categoryColor(condition.category);
    return Scaffold(
      appBar: AppBar(
        title: Text(condition.commonName),
        backgroundColor: categoryColor.withValues(alpha: 0.12),
        foregroundColor: AppColors.ink,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _categoryIcon(condition.category),
                  color: categoryColor,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      condition.commonName,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      condition.scientificName,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(
                        ConditionContent.categoryLabel(condition.category),
                      ),
                      avatar: Icon(
                        _categoryIcon(condition.category),
                        size: 16,
                        color: categoryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryLight.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This is a possible explanation, not a diagnosis. '
                    'Confirm important problems with a local extension service, '
                    'plant clinic, or qualified professional.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _ContentCard(
            title: 'Possible symptoms',
            body: condition.symptoms,
            icon: Icons.visibility_outlined,
            color: AppColors.primary,
          ),
          _ContentCard(
            title: 'Likely causes',
            body: condition.likelyCauses,
            icon: Icons.help_outline,
            color: AppColors.teal,
          ),
          _ContentCard(
            title: 'Look-alikes',
            body: condition.lookAlikes,
            icon: Icons.compare_arrows_outlined,
            color: AppColors.warn,
          ),
          _ContentCard(
            title: 'Prevention',
            body: condition.prevention,
            icon: Icons.shield_outlined,
            color: AppColors.forest,
          ),
          _ContentCard(
            title: 'Safe cultural treatment',
            body: condition.culturalTreatment,
            icon: Icons.handyman_outlined,
            color: AppColors.primary,
          ),
          SectionHeader(
            title: 'Treatment categories',
            subtitle: 'Categories are not product recommendations.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in condition.treatmentTags)
                        Chip(label: Text(_tagLabel(tag))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'A product tag means that a labeled product category may '
                    'be relevant only after confirmation. Check the crop, '
                    'site, target, protective-equipment, re-entry, pollinator, '
                    'and pre-harvest requirements on the current label.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          _ContentCard(
            title: 'When to escalate',
            body: condition.escalation,
            icon: Icons.forum_outlined,
            color: AppColors.amber,
          ),
          _ContentCard(
            title: 'Urgent warning signs',
            body: condition.urgentWarning,
            icon: Icons.warning_amber_outlined,
            color: AppColors.danger,
          ),
          SectionHeader(
            title: 'Sources',
            subtitle: 'Stored for offline reference; check local guidance too.',
          ),
          for (final reference in ConditionContent.referencesFor(condition))
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reference.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(reference.publisher, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    SelectableText(
                      reference.url,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: const Color(0xFF00695C),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: reference.url),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Source link copied')),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copy source link'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _tagLabel(String tag) {
    return switch (tag) {
      'C' => 'C  Cultural / environmental',
      'M' => 'M  Mechanical / physical',
      'B' => 'B  Biological / conservation',
      'P' => 'P  Product category only',
      'D' => 'D  Diagnostic / removal',
      _ => tag,
    };
  }

  Color _categoryColor(String category) {
    return switch (category) {
      'Fungal' => AppColors.teal,
      'Oomycete' => AppColors.teal,
      'Bacterial' => AppColors.danger,
      'Viral' => AppColors.warn,
      'Pest' => AppColors.amber,
      'Physiological' => AppColors.primary,
      'Abiotic' => AppColors.inkSoft,
      'Nutrient' => AppColors.forest,
      _ => AppColors.primary,
    };
  }

  IconData _categoryIcon(String category) {
    return switch (category) {
      'Fungal' => Icons.filter_vintage_outlined,
      'Oomycete' => Icons.water_damage_outlined,
      'Bacterial' => Icons.bug_report_outlined,
      'Viral' => Icons.coronavirus_outlined,
      'Pest' => Icons.pest_control_outlined,
      'Physiological' => Icons.science_outlined,
      'Abiotic' => Icons.wb_sunny_outlined,
      'Nutrient' => Icons.eco_outlined,
      _ => Icons.eco_outlined,
    };
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
