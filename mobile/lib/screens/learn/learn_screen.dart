import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/condition_models.dart';
import '../../models/education_models.dart';
import '../../services/condition_content.dart';
import '../../services/education_content.dart';
import '../../services/plant_database.dart';
import '../../widgets/section_header.dart';
import 'condition_detail_screen.dart';
import 'disease_by_plant_screen.dart';
import 'learn_detail_screen.dart';
import 'learn_topic_detail_screen.dart';
import 'plant_browser_screen.dart';
import 'plant_health_guide_screen.dart';

/// Educational content: plant-science topics plus the plant care catalogue.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Understand plants, symptoms, and how this app works.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          SectionHeader(
            title: 'Plant health',
            subtitle: 'Find a problem and understand the safest next step',
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlantHealthGuideScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.health_and_safety_outlined,
                        color: AppColors.danger,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sick plant & medicine guide',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Symptoms, causes, first aid, treatments and safety',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                  ],
                ),
              ),
            ),
          ),
          SectionHeader(
            title: 'Plant science',
            subtitle: 'Short, verified basics',
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final topic in EducationContent.topics)
                _TopicCard(topic: topic),
            ],
          ),
          SectionHeader(
            title: 'Source-linked quick reference',
            subtitle: 'Optional shorter summaries with direct reference links',
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.link_outlined, color: AppColors.teal),
              title: const Text('Open condition profiles'),
              subtitle: Text(
                '${ConditionContent.conditions.length} entries for quick comparison',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'For full first aid, treatment options and safety guidance, use the comprehensive plant health guide above. These shorter profiles are kept for direct extension-service links.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                for (final condition in ConditionContent.conditions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ConditionCard(condition: condition),
                  ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PlantBrowserScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Browse all plants',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Search, filter and open a larger plant catalogue',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                  ],
                ),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DiseaseByPlantScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.medical_information_outlined,
                        color: AppColors.teal,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Disease by plant',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Search common plant diseases and care patterns',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                  ],
                ),
              ),
            ),
          ),
          SectionHeader(
            title: 'Plant care catalogue',
            subtitle: 'Common house and garden plants',
          ),
          for (final p in PlantDatabase.all)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LearnDetailScreen(plantId: p.id),
                  ),
                ),
                leading: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(p.emoji, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                title: Text(
                  p.commonName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: Text(
                  p.scientificName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConditionCard extends StatelessWidget {
  const _ConditionCard({required this.condition});

  final PlantCondition condition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConditionDetailScreen(conditionId: condition.id),
          ),
        ),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.eco_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      condition.commonName,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ConditionContent.categoryLabel(condition.category),
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: const Color(0xFF00695C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      condition.symptoms,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});

  final LearnTopic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LearnTopicDetailScreen(topicId: topic.id),
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: (MediaQuery.of(context).size.width - 42) / 2,
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: topic.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(topic.icon, color: topic.color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(topic.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(
              topic.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
