import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/plant_health_visuals.dart';
import '../../models/plant_health_models.dart';
import '../../services/condition_content.dart';
import '../../services/plant_health_content.dart';
import 'condition_detail_screen.dart';
import 'plant_medicine_safety_screen.dart';

class PlantHealthDetailScreen extends StatelessWidget {
  const PlantHealthDetailScreen({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    final entry = PlantHealthContent.byId(entryId);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plant health guide')),
        body: const Center(child: Text('Guide not found.')),
      );
    }

    final quickReferenceId = PlantHealthContent.quickReferenceIdFor(entry.id);
    final quickReference = quickReferenceId == null
        ? null
        : ConditionContent.byId(quickReferenceId);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Condition guide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: entry.category.softColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: entry.category.color.withValues(alpha: 0.24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        entry.category.icon,
                        color: entry.category.textColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.category.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: entry.category.textColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.title,
                            style: theme.textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  entry.scientificName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderPill(
                      label: entry.category.label,
                      color: entry.category.textColor,
                      backgroundColor: Colors.white.withValues(alpha: 0.72),
                      icon: entry.category.icon,
                    ),
                    _HeaderPill(
                      label: entry.urgency.label,
                      color: entry.urgency.textColor,
                      backgroundColor: entry.urgency.softColor,
                      icon: entry.urgency == PlantProblemUrgency.urgent
                          ? Icons.emergency_outlined
                          : Icons.schedule_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(entry.summary, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.inkSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Educational screening guide, not a diagnosis. Several diseases and physical problems can look the same. Confirm the plant, symptom pattern and cause before treatment.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _GuideSection(
            title: 'What you may see',
            subtitle: 'Check both leaf surfaces, stems, soil and roots',
            icon: Icons.search_outlined,
            color: AppColors.danger,
            child: _BulletList(items: entry.symptoms),
          ),
          _GuideSection(
            title: 'Why it happens',
            subtitle: 'Common conditions, not proof of one cause',
            icon: Icons.account_tree_outlined,
            color: AppColors.amber,
            child: _BulletList(items: entry.causes),
          ),
          _GuideSection(
            title: 'First aid now',
            subtitle: 'Low-risk steps that stop spread or further damage',
            icon: Icons.medical_services_outlined,
            color: AppColors.primary,
            child: _NumberedList(items: entry.firstAid),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Before any registered product: confirm the target, exact plant, setting, crop, protective equipment, re-entry and harvest requirements on the current label.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PlantMedicineSafetyScreen(),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Read plant medicine safety'),
                  ),
                ),
              ],
            ),
          ),
          _GuideSection(
            title: 'Treatment options',
            subtitle: 'Start with the least intervention that can work',
            icon: Icons.medication_outlined,
            color: AppColors.teal,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < entry.treatments.length;
                  index++
                ) ...[
                  _TreatmentCard(treatment: entry.treatments[index]),
                  if (index != entry.treatments.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          _GuideSection(
            title: 'Prevent recurrence',
            subtitle: 'Prevention is usually more useful than rescue treatment',
            icon: Icons.shield_outlined,
            color: AppColors.forest,
            child: _BulletList(items: entry.prevention),
          ),
          _GuideSection(
            title: 'Could look like',
            subtitle: 'Do not choose a spray from appearance alone',
            icon: Icons.compare_arrows_outlined,
            color: AppColors.warn,
            child: _BulletList(items: entry.lookAlikes),
          ),
          _GuideSection(
            title: 'Get help promptly if',
            subtitle: 'Escalate severe, spreading or uncertain problems',
            icon: entry.urgency == PlantProblemUrgency.urgent
                ? Icons.emergency_outlined
                : Icons.support_agent_outlined,
            color: entry.urgency.textColor,
            child: _BulletList(items: entry.escalation),
          ),
          _SafetyCallout(note: entry.safetyNote),
          _GuideSection(
            title: 'Evidence base',
            subtitle:
                'Use local, current guidance for the exact plant and region',
            icon: Icons.fact_check_outlined,
            color: AppColors.inkSoft,
            child: _BulletList(items: entry.references),
          ),
          if (quickReference != null) ...[
            const SizedBox(height: 12),
            Text(
              'Optional host-specific source: ${quickReference.commonName}. Its plant and pathogen scope may differ from this general guide.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ConditionDetailScreen(conditionId: quickReference.id),
                ),
              ),
              icon: const Icon(Icons.link_outlined),
              label: const Text('Open source reference'),
            ),
          ],
          if (entry.relatedIds.isNotEmpty) ...[
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text(
                'Related problems',
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Compare related causes, look-alikes and shared risk factors.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in entry.relatedIds)
                  if (PlantHealthContent.byId(id) case final related?)
                    ActionChip(
                      avatar: Icon(
                        related.category.icon,
                        size: 17,
                        color: related.category.textColor,
                      ),
                      label: Text(related.title),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PlantHealthDetailScreen(entryId: id),
                        ),
                      ),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.icon,
  });

  final String label;
  final Color color;
  final Color backgroundColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _NumberedList extends StatelessWidget {
  const _NumberedList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppColors.forest,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      items[index],
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TreatmentCard extends StatelessWidget {
  const _TreatmentCard({required this.treatment});

  final PlantTreatment treatment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _treatmentColor(treatment.type);
    final textColor = _treatmentTextColor(treatment.type);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _treatmentIcon(treatment.type),
                  color: textColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      treatment.type.label.toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(treatment.title, style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < treatment.steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${index + 1}.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      treatment.steps[index],
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _treatmentColor(PlantTreatmentType type) => switch (type) {
    PlantTreatmentType.environment => AppColors.primary,
    PlantTreatmentType.sanitation => AppColors.inkSoft,
    PlantTreatmentType.physical => AppColors.warn,
    PlantTreatmentType.biological => AppColors.teal,
    PlantTreatmentType.registeredProduct => AppColors.danger,
    PlantTreatmentType.professionalCare => AppColors.forest,
  };

  Color _treatmentTextColor(PlantTreatmentType type) => switch (type) {
    PlantTreatmentType.environment => const Color(0xFF1B5E20),
    PlantTreatmentType.sanitation => const Color(0xFF455A64),
    PlantTreatmentType.physical => const Color(0xFF93430B),
    PlantTreatmentType.biological => const Color(0xFF00695C),
    PlantTreatmentType.registeredProduct => const Color(0xFFB3261E),
    PlantTreatmentType.professionalCare => const Color(0xFF33691E),
  };

  IconData _treatmentIcon(PlantTreatmentType type) => switch (type) {
    PlantTreatmentType.environment => Icons.eco_outlined,
    PlantTreatmentType.sanitation => Icons.cleaning_services_outlined,
    PlantTreatmentType.physical => Icons.handyman_outlined,
    PlantTreatmentType.biological => Icons.eco_outlined,
    PlantTreatmentType.registeredProduct => Icons.medication_outlined,
    PlantTreatmentType.professionalCare => Icons.support_agent_outlined,
  };
}

class _SafetyCallout extends StatelessWidget {
  const _SafetyCallout({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.gpp_maybe_outlined,
            color: AppColors.danger,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safety note',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(note, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
