import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/plant_health_visuals.dart';
import '../../models/plant_health_models.dart';
import '../../services/plant_health_content.dart';
import '../../widgets/section_header.dart';
import 'plant_health_detail_screen.dart';
import 'plant_medicine_safety_screen.dart';

class PlantHealthGuideScreen extends StatefulWidget {
  const PlantHealthGuideScreen({super.key});

  @override
  State<PlantHealthGuideScreen> createState() => _PlantHealthGuideScreenState();
}

class _PlantHealthGuideScreenState extends State<PlantHealthGuideScreen> {
  final TextEditingController _searchController = TextEditingController();
  PlantProblemCategory? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = PlantHealthContent.search(
      _searchController.text,
      category: _selectedCategory,
    );
    final showingAll =
        _searchController.text.trim().isEmpty && _selectedCategory == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Plant health guide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF123619),
                  Color(0xFF1B5E20),
                  Color(0xFF245E27),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.health_and_safety_outlined,
                  color: Colors.white,
                  size: 34,
                ),
                const SizedBox(height: 10),
                Text(
                  'Find the cause before choosing the medicine',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Search ${PlantHealthContent.all.length} common diseases, pests, root problems, care disorders and nutrient issues.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.forest,
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PlantMedicineSafetyScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Plant medicine safety'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search white powder, yellow leaves, wilting, spots…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('All'),
                avatar: const Icon(Icons.apps_rounded, size: 17),
                selected: _selectedCategory == null,
                onSelected: (_) => setState(() => _selectedCategory = null),
              ),
              for (final category in PlantProblemCategory.values)
                FilterChip(
                  label: Text(category.label),
                  avatar: Icon(category.icon, size: 17),
                  selected: _selectedCategory == category,
                  onSelected: (selected) => setState(
                    () => _selectedCategory = selected ? category : null,
                  ),
                ),
            ],
          ),
          Card(
            margin: const EdgeInsets.only(top: 16),
            child: ExpansionTile(
              leading: const Icon(
                Icons.medical_information_outlined,
                color: AppColors.danger,
              ),
              title: const Text('Emergency first aid'),
              subtitle: const Text('What to do before using any product'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                for (
                  var index = 0;
                  index < PlantHealthContent.emergencySteps.length;
                  index++
                )
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.primarySoft,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.forest,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            PlantHealthContent.emergencySteps[index],
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  const Icon(Icons.menu_book_outlined, color: AppColors.teal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This guide supports observation and prevention. It cannot identify a pathogen from symptoms alone and does not replace a plant clinic, extension service or qualified crop adviser.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selectedCategory != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _selectedCategory!.softColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _selectedCategory!.color.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _selectedCategory!.icon,
                    color: _selectedCategory!.textColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      PlantHealthContent.categoryGuidance[_selectedCategory!
                          .label]!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Semantics(
            liveRegion: true,
            label:
                '${showingAll ? 'Browse all problems' : 'Search results'}, ${results.length} of ${PlantHealthContent.all.length}',
            child: ExcludeSemantics(
              child: SectionHeader(
                title: showingAll ? 'Browse all problems' : 'Search results',
                subtitle:
                    '${results.length} of ${PlantHealthContent.all.length}',
              ),
            ),
          ),
          if (results.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.search_off,
                      size: 44,
                      color: AppColors.inkMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No close match found',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Try a symptom such as “yellow”, “white”, “wilting”, “spots” or “insects”, or clear the filters.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            for (final entry in results) _ProblemCard(entry: entry),
        ],
      ),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.entry});

  final PlantHealthEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlantHealthDetailScreen(entryId: entry.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: entry.category.softColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  entry.category.icon,
                  color: entry.category.textColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(entry.title, style: theme.textTheme.titleMedium),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: entry.category.softColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            entry.category.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: entry.category.textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.scientificName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: entry.urgency.softColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entry.urgency.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: entry.urgency.textColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
