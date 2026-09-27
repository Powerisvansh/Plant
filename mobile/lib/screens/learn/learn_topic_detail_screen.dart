import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/education_content.dart';
import '../../widgets/section_header.dart';

/// Detail page for one educational topic in the Learn section.
class LearnTopicDetailScreen extends StatelessWidget {
  const LearnTopicDetailScreen({super.key, required this.topicId});

  final String topicId;

  @override
  Widget build(BuildContext context) {
    final topic = EducationContent.byId(topicId);
    if (topic == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Learn')),
        body: const Center(child: Text('Topic not found.')),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(topic.title),
        backgroundColor: topic.color.withValues(alpha: 0.12),
        foregroundColor: AppColors.ink,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: topic.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(topic.icon, color: topic.color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(topic.subtitle,
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (heading, body) in topic.sections) ...[
            SectionHeader(title: heading),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(body, style: theme.textTheme.bodyMedium),
              ),
            ),
            const SizedBox(height: 2),
          ],
          const SizedBox(height: 12),
          Card(
            color: AppColors.primarySoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Educational summary from general plant-science '
                      'references. For species-specific decisions, confirm '
                      'with a local extension service or plant professional.',
                      style: theme.textTheme.bodySmall,
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
}