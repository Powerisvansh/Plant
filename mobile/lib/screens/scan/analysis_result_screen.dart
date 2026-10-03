import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formats.dart';
import '../../core/theme/app_theme.dart';
import '../../models/analysis_models.dart';
import '../../models/scan_models.dart';
import '../../services/identification/identification_models.dart';
import '../../services/analysis/scan_suggestions.dart';
import '../../services/knowledge/knowledge_repository.dart';
import '../../services/plant_database.dart';
import '../../state/providers.dart';
import '../../widgets/evidence_overlay.dart';
import '../../widgets/health_ring.dart';
import '../learn/knowledge_plant_detail_screen.dart';
import '../../widgets/stat_card.dart';

/// Full result of a check-up: identification, health screening, evidence,
/// possible causes, care notes and saving.
class AnalysisResultScreen extends StatefulWidget {
  const AnalysisResultScreen({
    super.key,
    required this.scanId,
    required this.bundle,
  });

  final String scanId;
  final AnalysisBundle bundle;

  @override
  State<AnalysisResultScreen> createState() => _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends State<AnalysisResultScreen> {
  int _photoIndex = 0;
  bool _saved = false;
  bool _savedAsPlant = false;
  bool _answeredFollowUp = false;

  final _locationCtrl = TextEditingController();
  final _wateringCtrl = TextEditingController();
  final _timelineCtrl = TextEditingController();

  /// Suggestions derived from the bundle plus the offline knowledge base.
  ///
  /// Loaded once in initState. A failure here must never take down the result
  /// screen, which already shows everything measured from the image.
  ScanSuggestions? _suggestions;
  bool _suggestionsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    try {
      final repo = await KnowledgeRepository.open();
      final result = await ScanSuggestionService(repo).build(
        identification: bundle.identification,
        health: bundle.health,
        perImage: bundle.perImage,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = result;
        _suggestionsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestionsLoading = false);
    }
  }

  AnalysisBundle get bundle => widget.bundle;

  @override
  void dispose() {
    _locationCtrl.dispose();
    _wateringCtrl.dispose();
    _timelineCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveScan({String? withPlantId}) async {
    if (_saved) return;
    final history = context.read<HistoryController>();
    final followUp = <String>[_locationCtrl.text.trim(), _wateringCtrl.text.trim(), _timelineCtrl.text.trim()]
        .where((s) => s.isNotEmpty)
        .join('\n');
    final record = ScanRecord(
      id: widget.scanId,
      createdAt: DateTime.now(),
      thumbPath: bundle.workingPaths.isNotEmpty ? bundle.workingPaths.first : '',
      imagePaths: bundle.workingPaths,
      imageSubjects: bundle.subjects.map(subjectLabel).toList(),
      plantGuess: bundle.identification.recordName,
      scientificGuess: bundle.identification.recordScientific,
      identificationConfidence: bundle.identification.identifiedConfidence ??
          bundle.identification.growthFormConfidence,
      identificationUncertain: bundle.identification.uncertain,
      healthIndex: bundle.index.score,
      overallCondition: bundle.health.overallCondition,
      observedIndicators: bundle.health.observedIndicators,
      causeLabels: bundle.health.possibleCauses.map((c) => c.label).toList(),
      followUp: followUp.isEmpty ? null : followUp,
      notes: '',
      savedPlantId: withPlantId,
    );
    await history.addScan(record);
    setState(() => _saved = true);
    _toast('Check-up saved to history.');
  }

  Future<void> _saveAsPlant() async {
    final plants = context.read<PlantsController>();
    final plant = await plants.addPlant(
      name: bundle.identification.recordName,
      species: bundle.identification.recordScientific,
      healthIndex: bundle.index.score,
      photoPath: bundle.workingPaths.isNotEmpty ? bundle.workingPaths.first : '',
    );
    if (!mounted) return;
    await _saveScan(withPlantId: plant.id);
    if (!mounted) return;
    await context.read<HistoryController>().attachToPlant(widget.scanId, plant.id);
    if (mounted) setState(() => _savedAsPlant = true);
    _toast('Added to My Plants.');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFollowUp() async {
    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Follow-up questions',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Optional - helps interpret the screening.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(labelText: 'Where is the plant?'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wateringCtrl,
              decoration: const InputDecoration(labelText: 'How often do you water?'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timelineCtrl,
              decoration: const InputDecoration(labelText: 'When did the problem start?'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save answers with the check-up'),
            ),
          ],
        ),
      ),
    );
    if (edited == true) setState(() => _answeredFollowUp = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identification = bundle.identification;

    return Scaffold(
      appBar: AppBar(title: const Text('Check-up result')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _qualityWarnings(),
          const SizedBox(height: 12),
          _conditionCard(theme),
          const SizedBox(height: 12),
          _modelScreeningCard(theme),
          const SizedBox(height: 12),
          _identificationCard(theme, identification),
          const SizedBox(height: 12),
          _photoEvidence(theme),
          const SizedBox(height: 12),
          _safeCareCard(theme),
          const SizedBox(height: 12),
          _medicineSafetyCard(theme),
          const SizedBox(height: 12),
          _causesCard(theme),
          const SizedBox(height: 12),
          _suggestionsCard(theme),
          const SizedBox(height: 12),
          _careCard(theme, identification),
          const SizedBox(height: 12),
          _plantInfoCard(theme, identification),
          const SizedBox(height: 12),
          _followUpCard(theme),
          const SizedBox(height: 24),
          _saveSection(),
        ],
      ),
    );
  }

  Widget _qualityWarnings() {
    final bad = bundle.qualityReports.where((q) => !q.usable).toList();
    if (bad.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Some photos may reduce accuracy: ${bad.map((q) => q.summary).join(' ')}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conditionCard(ThemeData theme) {
    final index = bundle.index;
    final condition = bundle.health.overallCondition;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            HealthRing(index: index.score, label: gradeLabel(index.score)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plant health status', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(condition,
                      style: theme.textTheme.titleLarge!
                          .copyWith(color: healthColor(index.score))),
                  const SizedBox(height: 6),
                  Text(
                    'Experimental visual score only. It is not a confirmed diagnosis.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identificationCard(ThemeData theme, PlantIdentification id) {
    final hasSpecies = id.hasSpeciesIdentification;
    final modelCandidates =
        id.candidates.where((c) => !c.morphologyOnly).toList(growable: false);
    final lookAlikes = id.possibilities;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_outlined, color: AppColors.teal),
                const SizedBox(width: 8),
                Text(
                  hasSpecies ? 'Identified plant' : 'Plant identity',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(id.displayName, style: theme.textTheme.titleLarge),
            if (id.displayScientificName.isNotEmpty)
              Text(id.displayScientificName, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(id.explanation, style: theme.textTheme.bodyMedium),
            if (id.conflictingEvidence) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.compare_arrows,
                        size: 18, color: AppColors.warn),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The submitted images provide conflicting visual '
                        'evidence, so no single answer is forced.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _bandChip(theme, id),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    id.modelAvailable
                        ? 'On-device model'
                        : 'No model bundled - leaf-shape screening only',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (hasSpecies && modelCandidates.length > 1) ...[
              const SizedBox(height: 12),
              Text('Runner-up matches', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              for (final c in modelCandidates.skip(1).take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${c.commonName}'
                    '${c.scientificName.isEmpty ? '' : ' (${c.scientificName})'}'
                    ' - ${c.displayScore}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (!hasSpecies && modelCandidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Closest model matches (not confirmed)',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              for (final c in modelCandidates.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${c.commonName} - ${c.displayScore}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            if (!hasSpecies && lookAlikes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Look-alikes from the local catalogue (shape similarity only, '
                'not a probability)',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              for (final c in lookAlikes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${c.commonName} (${c.scientificName})',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bandChip(ThemeData theme, PlantIdentification id) {
    final isUnknown =
        id.band == ConfidenceBand.unknown || id.band == ConfidenceBand.low;
    final color = isUnknown ? AppColors.warn : AppColors.primary;
    final probability = id.identifiedConfidence;
    final text = probability != null
        ? '${id.band.label} - ${(probability * 100).round()}%'
        : id.band.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall!
            .copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _modelScreeningCard(ThemeData theme) {
    final screen = bundle.conditionScreen;
    if (screen == null) return const SizedBox.shrink();
    final condition = screen.conditionName;
    final headline = screen.healthy
        ? 'no disease class won for this photo'
        : (condition ?? 'unsupported condition');
    final agreementText = screen.agreement >= 1.0
        ? 'all photos agreed'
        : '${(screen.agreement * 100).round()}% of photos agreed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.biotech_outlined, color: AppColors.teal),
                const SizedBox(width: 8),
                Text('Model disease screening',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${screen.cropName} - $headline',
              style: theme.textTheme.titleMedium!.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Strongest class ${(screen.topProbability * 100).round()}% '
              '($agreementText).',
              style: theme.textTheme.bodySmall,
            ),
            if (screen.topK.length > 1) ...[
              const SizedBox(height: 8),
              Text('Other candidates', style: theme.textTheme.bodySmall),
              for (final p in screen.topK.skip(1).take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${p.classInfo?.crop ?? '?'}'
                    '${p.classInfo?.condition == null ? ' (healthy)' : ' - ${p.classInfo!.condition}'}'
                    ' - ${(p.probability * 100).round()}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              'Visual screening from a model trained on the PlantVillage '
              'dataset (${screen.modelKey}). Not a laboratory diagnosis - '
              'confirm before treating.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoEvidence(ThemeData theme) {
    final idx = _photoIndex.clamp(0, bundle.workingPaths.length - 1);
    final photo = bundle.perImage[idx];
    final path = bundle.workingPaths[idx];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.center_focus_strong, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('What PlantDoctor sees',
                      style: theme.textTheme.titleMedium),
                ),
                Text('${idx + 1}/${bundle.workingPaths.length}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            EvidenceOverlay(
              imagePath: path,
              evidence: photo.evidence,
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _metricChip('Yellow', pct(photo.yellowFraction), const Color(0xFFF9A825)),
                  _metricChip('Brown', pct(photo.brownFraction), const Color(0xFF8D6E63)),
                  _metricChip('Spots', pct(photo.spottedFraction), const Color(0xFFD81B60)),
                  _metricChip('Coverage', pct(photo.plantCoverage), AppColors.teal),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 66,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < bundle.workingPaths.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _photoIndex = i),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: i == idx ? AppColors.primary : Colors.transparent,
                            width: 2.5,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(bundle.workingPaths[i]),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 60,
                              height: 60,
                              color: AppColors.border,
                              child: const Icon(Icons.eco_outlined),
                            ),
                          ),
                        ),
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

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 6),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall!
                  .copyWith(color: AppColors.ink, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _safeCareCard(ThemeData theme) {
    final guidance = bundle.health.safeCareGuidance;
    if (guidance.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Safe actions', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ...guidance.map((step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _medicineSafetyCard(ThemeData theme) {
    final guidance = bundle.health.safeMedicineGuidance;
    if (guidance.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety_outlined, color: AppColors.warn, size: 20),
                const SizedBox(width: 8),
                Text('Warnings & product safety', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ...guidance.map((step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warn),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
                ],
              ),
            )),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warn.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'No exact dosage is shown here. Dosage, timing and product choice must follow the product label and local extension guidance.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _causesCard(ThemeData theme) {
    final causes = bundle.health.possibleCauses;
    if (causes.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.troubleshoot_outlined, color: AppColors.teal, size: 20),
                const SizedBox(width: 8),
                Text('Likely issue', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(bundle.health.uncertaintyExplanation,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            for (var i = 0; i < causes.length; i++) ...[
              if (i > 0) const Divider(height: 22),
              _CauseView(cause: causes[i]),
            ],
          ],
        ),
      ),
    );
  }

  /// Suggestions drawn from the offline knowledge base and from what the
  /// image actually measured. Renders nothing when there is nothing sourced to
  /// say, rather than padding the screen with filler.
  Widget _suggestionsCard(ThemeData theme) {
    final s = _suggestions;
    if (_suggestionsLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (s == null || s.items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined,
                    color: AppColors.teal, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('What to do next',
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Based on what this photo measured and the records bundled with '
              'the app.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final item in s.items) ...[
              _suggestionRow(theme, item),
              const SizedBox(height: 10),
            ],
            if (s.hasRelated) ...[
              const SizedBox(height: 4),
              Text('Related plants', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final r in s.related)
                    ActionChip(
                      label: Text(r.displayName),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              KnowledgePlantDetailScreen(slug: r.slug),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _suggestionRow(ThemeData theme, ScanSuggestion item) {
    final (icon, color) = switch (item.kind) {
      ScanSuggestionKind.identification =>
        (Icons.category_outlined, AppColors.teal),
      ScanSuggestionKind.cultivation =>
        (Icons.grass_outlined, AppColors.primary),
      ScanSuggestionKind.symptom =>
        (Icons.healing_outlined, Colors.orange.shade800),
      ScanSuggestionKind.care => (Icons.eco_outlined, AppColors.primary),
      ScanSuggestionKind.safety =>
        (Icons.warning_amber_rounded, Colors.red.shade700),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(item.detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _careCard(ThemeData theme, PlantIdentification id) {
    final info = _plantInfoFor(id);
    if (info == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.spa_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('Suggested care for ${info.commonName}',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(info.care, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'Sunlight: ${info.sunlight}  |  Water: ${info.water}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _plantInfoCard(ThemeData theme, PlantIdentification id) {
    final info = _plantInfoFor(id);
    final slug = _knowledgeSlugFor(id);
    if (info == null && slug == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined,
                    color: AppColors.teal, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info == null
                        ? 'About ${id.identifiedName ?? 'this plant'}'
                        : 'About ${info.commonName}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (slug != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => KnowledgePlantDetailScreen(slug: slug),
                  ),
                ),
                icon: const Icon(Icons.storage_rounded, size: 18),
                label: const Text('Open the full plant record'),
              ),
              const SizedBox(height: 4),
              Text(
                'Sourced taxonomy, diseases, pests and safety from the bundled '
                'offline database.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (info != null) ...[
              const SizedBox(height: 12),
              StatCard(
                label: 'Family',
                value: info.family,
                icon: Icons.emoji_nature_outlined,
              ),
              const SizedBox(height: 8),
              StatCard(
                label: 'Growth',
                value: info.growth,
                icon: Icons.trending_up,
              ),
              const SizedBox(height: 8),
              Text('Origin', style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(info.origin, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Text('Common problems', style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(info.commonProblems, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  /// Slug of the knowledge-base row for the identified plant, when the model
  /// named one. Returns null for an uncertain result so no record is opened.
  String? _knowledgeSlugFor(PlantIdentification id) {
    if (id.source != IdentificationSource.model) return null;
    if (id.identifiedName == null) return null;
    final lead = id.candidates.isEmpty ? null : id.candidates.first;
    final slug = lead?.plantId ?? '';
    // Guard against a raw class label being used as a slug.
    if (slug.isEmpty || slug.contains('___')) return null;
    return slug;
  }

  Widget _followUpCard(ThemeData theme) {
    return Card(
      child: ListTile(
        onTap: _openFollowUp,
        leading: const Icon(Icons.quiz_outlined, color: AppColors.teal),
        title: Text('Follow-up questions', style: theme.textTheme.titleMedium),
        subtitle: Text(
          _answeredFollowUp
              ? 'Answers will be stored with this check-up.'
              : 'Optional context to interpret the screening.',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Icon(
          _answeredFollowUp ? Icons.check_circle : Icons.chevron_right,
          color: _answeredFollowUp ? AppColors.primary : AppColors.inkMuted,
        ),
      ),
    );
  }

  Widget _saveSection() {
    return Column(
      children: [
        FilledButton.icon(
          onPressed: _saved ? null : _saveScan,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(_saved ? 'Saved to history' : 'Save check-up to history'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _savedAsPlant || _saved
              ? null
              : _saveAsPlant,
          icon: const Icon(Icons.add_circle_outline),
          label: Text(_savedAsPlant
              ? 'Saved to My Plants'
              : 'Also save to My Plants'),
        ),
      ],
    );
  }

  /// Local catalogue entry for the leading candidate, if there is one. The
  /// profile card is hidden unless the app actually has a matching entry.
  PlantInfo? _plantInfoFor(PlantIdentification id) {
    if (id.candidates.isEmpty) return null;
    final lead = id.candidates.first;
    for (final p in PlantDatabase.all) {
      if (p.id == lead.plantId) return p;
    }
    for (final p in PlantDatabase.all) {
      if (p.commonName.toLowerCase() == lead.commonName.toLowerCase()) return p;
    }
    return null;
  }
}

class _CauseView extends StatelessWidget {
  const _CauseView({required this.cause});

  final CauseCandidate cause;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(cause.label,
                  style: theme.textTheme.titleMedium!
                      .copyWith(fontSize: 15)),
            ),
            Text(cause.confidenceLabel,
                style: theme.textTheme.bodySmall!
                    .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Text(cause.explanation, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}