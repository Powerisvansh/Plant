import 'package:flutter/material.dart';

import '../../models/knowledge_models.dart';
import '../../services/knowledge/knowledge_repository.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';

/// Full offline plant profile, assembled from the bundled database.
///
/// Sections with no sourced rows render an explicit "not verified" state. No
/// section is ever filled with a substitute value: in particular there is no
/// dosage fallback and no "safe" default for toxicity.
class KnowledgePlantDetailScreen extends StatefulWidget {
  const KnowledgePlantDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<KnowledgePlantDetailScreen> createState() =>
      _KnowledgePlantDetailScreenState();
}

class _KnowledgePlantDetailScreenState
    extends State<KnowledgePlantDetailScreen> {
  late final Future<KnowledgeProfile?> _profile = _load();

  Future<KnowledgeProfile?> _load() async {
    final repo = await KnowledgeRepository.open();
    return repo.profileForSlug(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plant profile')),
      body: FutureBuilder<KnowledgeProfile?>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Could not read this record',
              message: '${snapshot.error}',
            );
          }
          final profile = snapshot.data;
          if (profile == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Plant not found',
              message: 'This record is not in the bundled knowledge base.',
            );
          }
          return _body(profile);
        },
      ),
    );
  }

  Widget _body(KnowledgeProfile profile) {
    final plant = profile.plant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(
          plant.displayName,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 2),
        Text(
          plant.scientificName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (plant.authorship != null && plant.authorship!.isNotEmpty)
          Text(plant.authorship!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (plant.family != null) _chip(context, plant.family!),
            if (plant.genus != null) _chip(context, plant.genus!),
            _chip(context, plant.taxonomicStatus ?? 'taxon'),
            _chip(
              context,
              plant.verificationStatus == null
                  ? 'unverified'
                  : plant.verificationStatus!,
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ------------------------------------------------------------ taxonomy
        const SectionHeader(title: 'Taxonomy'),
        if (plant.familyLine != null)
          _kv(context, 'Classification', plant.familyLine!),
        if (plant.vernacularNames.isNotEmpty)
          _kv(context, 'Other names', plant.vernacularNames.join(', ')),
        if (profile.distribution.isNotEmpty)
          _kv(
            context,
            'Recorded in',
            profile.distribution
                .map((d) => d.region)
                .toSet()
                .take(12)
                .join(', '),
          ),

        // --------------------------------------------------------- description
        if (plant.description != null && plant.description!.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SectionHeader(title: 'Description'),
          Text(plant.description!),
        ],
        if (plant.identificationFeatures != null &&
            plant.identificationFeatures!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _kv(context, 'Identification', plant.identificationFeatures!),
        ],

        // -------------------------------------------------------------- growth
        const SizedBox(height: 18),
        const SectionHeader(title: 'Growing conditions'),
        if (!profile.hasCultivationData)
          _notSourced(
            context,
            'No sourced growing-condition data for this species in this '
            'release. Climate, soil, water and season fields stay empty rather '
            'than being filled with typical values for the genus.',
          )
        else
          ...profile.growth!.labelled.map((e) => _kv(context, e.key, e.value!)),

        // ------------------------------------------------------------ rooftop
        const SizedBox(height: 18),
        RooftopSection(profile: profile),

        // ------------------------------------------------------------ diseases
        const SizedBox(height: 18),
        SectionHeader(title: 'Diseases (${profile.diseases.length})'),
        if (profile.diseases.isEmpty)
          _notSourced(
            context,
            'No disease records are linked to this plant yet.',
          )
        else
          ...profile.diseases.map((d) => _diseaseTile(context, d)),

        // --------------------------------------------------------------- pests
        const SizedBox(height: 18),
        SectionHeader(title: 'Pests (${profile.pests.length})'),
        if (profile.pests.isEmpty)
          _notSourced(context, 'No pest records are linked to this plant yet.')
        else
          ...profile.pests.map((p) => _pestTile(context, p)),

        // --------------------------------------------------------- deficiencies
        const SizedBox(height: 18),
        SectionHeader(title: 'Nutrient deficiency reference'),
        if (profile.deficiencies.isEmpty)
          _notSourced(context, 'No deficiency reference data is bundled.')
        else ...[
          const _ReferenceLabel(),
          ...profile.deficiencies.map((d) => _deficiencyTile(context, d)),
        ],

        // ------------------------------------------------------------- stresses
        if (profile.stresses.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionHeader(title: 'Environmental stress reference'),
          const _ReferenceLabel(),
          ...profile.stresses.map(
            (s) => _Expansion(
              title: s.name,
              subtitle: s.verificationStatus,
              children: [
                if (s.description != null) Text(s.description!),
                if (s.visualSigns != null)
                  _kv(context, 'Visual signs', s.visualSigns!),
                if (s.similarConditions != null)
                  _kv(context, 'Looks similar to', s.similarConditions!),
                if (s.correctionGuidance != null)
                  _kv(context, 'What to do', s.correctionGuidance!),
              ],
            ),
          ),
        ],

        // ----------------------------------------------------------- treatment
        const SizedBox(height: 18),
        const SectionHeader(title: 'Treatment information'),
        if (!profile.hasVerifiedDosage)
          _unavailable(
            context,
            'Verified dosage information is unavailable.',
            'No label-verified treatment record exists for this plant in this '
                'release. PlantDoctor will not substitute a typical dose, a '
                'neighbouring crop\'s dose, or a folk remedy.\n\n'
                'Start with non-chemical measures: remove severely affected '
                'material, improve air circulation, correct irrigation and '
                'drainage, sanitise, remove pests physically, rotate crops, and '
                'monitor. Then consult a local agricultural advisory service.',
          )
        else
          ...profile.treatments.map((t) => _treatmentTile(context, t)),

        // ------------------------------------------------------------ toxicity
        const SizedBox(height: 18),
        const SectionHeader(title: 'Toxicity and safety'),
        _toxicityBlock(context, profile),

        // ------------------------------------------------------------- sources
        const SizedBox(height: 18),
        const SectionHeader(title: 'Sources'),
        if (profile.sources.isEmpty)
          _notSourced(context, 'No source rows are attached to this record.')
        else
          ...profile.sources.map((s) => _sourceTile(context, s)),
        const SizedBox(height: 14),
        Text(
          'This is visual screening and reference information, not a '
          'diagnosis. Confirm with a qualified agronomist or plant clinic '
          'before acting on anything health-related.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ pieces

  Widget _toxicityBlock(BuildContext context, KnowledgeProfile profile) {
    final known = profile.plant.toxicityKnown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kv(context, 'Toxicity status', profile.toxicityStatusText),
        _kv(context, 'Human safety', 'Not verified'),
        _kv(context, 'Pet safety', 'Not verified'),
        _kv(context, 'Livestock safety', 'Not verified'),
        _kv(context, 'Dangerous parts', 'Not verified'),
        if (!known)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _callout(
              context,
              Icons.warning_amber_rounded,
              'Unknown is not safe',
              'No reliable toxicity information is recorded for this species. '
                  'Absence from a published toxic-plant list is not evidence of '
                  'safety. Do not consume or use medicinally without independent '
                  'verification.',
              warn: true,
            ),
          ),
      ],
    );
  }

  Widget _diseaseTile(BuildContext context, KnowledgeDisease d) => _Expansion(
    title: d.name,
    subtitle: d.pathogenName == null
        ? d.verificationStatus
        : '${d.pathogenName} \u00b7 ${d.verificationStatus ?? 'unverified'}',
    children: [
      if (d.pathogenKind != null)
        _kv(context, 'Pathogen type', d.pathogenKind!),
      if (d.description != null) Text(d.description!),
      if (d.visualSymptoms != null)
        _kv(context, 'Visual symptoms', d.visualSymptoms!),
      if (d.earlySymptoms != null)
        _kv(context, 'Early signs', d.earlySymptoms!),
      if (d.advancedSymptoms != null)
        _kv(context, 'Advanced signs', d.advancedSymptoms!),
      if (d.favorableConditions != null)
        _kv(context, 'Favours', d.favorableConditions!),
      if (d.transmission != null) _kv(context, 'Spreads by', d.transmission!),
      if (d.prevention != null) _kv(context, 'Prevention', d.prevention!),
      if (d.management != null) _kv(context, 'Management', d.management!),
      if (d.lastVerified != null)
        _kv(context, 'Last verified', d.lastVerified!),
    ],
  );

  Widget _pestTile(BuildContext context, KnowledgePest p) => _Expansion(
    title: p.name,
    subtitle: p.scientificName == null
        ? p.verificationStatus
        : '${p.scientificName} \u00b7 ${p.verificationStatus ?? 'unverified'}',
    children: [
      if (p.appearance != null) _kv(context, 'Appearance', p.appearance!),
      if (p.feedingBehavior != null)
        _kv(context, 'Feeding', p.feedingBehavior!),
      if (p.damageSymptoms != null) _kv(context, 'Damage', p.damageSymptoms!),
      if (p.lifeStages != null) _kv(context, 'Life stages', p.lifeStages!),
      if (p.prevention != null) _kv(context, 'Prevention', p.prevention!),
      if (p.management != null) _kv(context, 'Management', p.management!),
    ],
  );

  Widget _deficiencyTile(
    BuildContext context,
    KnowledgeDeficiency d,
  ) => _Expansion(
    title: d.symbol == null ? d.nutrient : '${d.nutrient} (${d.symbol})',
    subtitle: d.verificationStatus,
    children: [
      if (d.description != null) Text(d.description!),
      if (d.visualSigns != null) _kv(context, 'Visual signs', d.visualSigns!),
      if (d.affectedParts != null)
        _kv(context, 'Affected parts', d.affectedParts!),
      if (d.similarConditions != null)
        _kv(context, 'Looks similar to', d.similarConditions!),
      if (d.soilFactors != null) _kv(context, 'Soil factors', d.soilFactors!),
      if (d.correctionGuidance != null)
        _kv(context, 'What to do', d.correctionGuidance!),
    ],
  );

  Widget _treatmentTile(BuildContext context, KnowledgeTreatment t) =>
      _Expansion(
        title: t.name,
        subtitle: t.treatmentType,
        children: [
          if (t.description != null) Text(t.description!),
          if (t.dosageDisplay != null) _kv(context, 'Dosage', t.dosageDisplay!),
          if (t.waterVolume != null)
            _kv(context, 'Water volume', t.waterVolume!),
          if (t.applicationMethod != null)
            _kv(context, 'Method', t.applicationMethod!),
          if (t.frequency != null) _kv(context, 'Frequency', t.frequency!),
          if (t.timing != null) _kv(context, 'Timing', t.timing!),
          if (t.preHarvestInterval != null)
            _kv(context, 'Pre-harvest interval', t.preHarvestInterval!),
          if (t.safetyPrecautions != null)
            _kv(context, 'Safety', t.safetyPrecautions!),
          if (t.protectiveEquipment != null)
            _kv(context, 'Protective equipment', t.protectiveEquipment!),
          if (t.labelUrl != null) _kv(context, 'Label', t.labelUrl!),
          if (t.lastVerified != null)
            _kv(context, 'Last verified', t.lastVerified!),
        ],
      );

  Widget _sourceTile(BuildContext context, KnowledgeSource s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.name, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          [
            s.organization,
            s.license,
            if (s.retrievedAt != null) 'retrieved ${s.retrievedAt}',
          ].whereType<String>().where((v) => v.isNotEmpty).join(' \u00b7 '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _kv(BuildContext context, String key, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$key: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );

  Widget _chip(BuildContext context, String text) => Chip(
    label: Text(text, style: Theme.of(context).textTheme.labelSmall),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _notSourced(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontStyle: FontStyle.italic),
    ),
  );

  Widget _unavailable(BuildContext context, String title, String body) =>
      _callout(context, Icons.block_outlined, title, body, warn: true);

  Widget _callout(
    BuildContext context,
    IconData icon,
    String title,
    String body, {
    bool warn = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: warn ? scheme.onErrorContainer : scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: warn ? scheme.onErrorContainer : scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Labels a list as general reference rather than a per-plant match.
class _ReferenceLabel extends StatelessWidget {
  const _ReferenceLabel();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      'General reference. These are not matched to this plant and are not '
      'a diagnosis - yellowing leaves alone do not identify a deficiency.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontStyle: FontStyle.italic),
    ),
  );
}

class _Expansion extends StatelessWidget {
  const _Expansion({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      children: children,
    ),
  );
}

/// Rooftop and terrace siting guidance for one plant.
///
/// Extracted from the detail screen so the section can be rendered under test
/// without standing up the asset pipeline, and so the two states stay
/// together: a species with a curated record, and one without. The second
/// state is a first-class message, not an empty box, because a grower needs
/// to know the guidance is absent rather than assume the plant is unsuitable.
class RooftopSection extends StatelessWidget {
  const RooftopSection({super.key, required this.profile});

  final KnowledgeProfile profile;

  @override
  Widget build(BuildContext context) {
    if (!profile.hasRooftopData) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Rooftop and terrace growing'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No rooftop siting record for this species in this release. '
              'Light, wind, container and watering bands stay empty rather than '
              'being filled with typical values for the genus.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      );
    }

    final record = profile.rooftop!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Rooftop and terrace growing'),
        _line(context, 'Sourcing', record.provenanceNotice),
        ...record.badges.map((e) => _line(context, e.key, e.value!)),
        ...record.details.map((e) => _line(context, e.key, e.value!)),
      ],
    );
  }

  static Widget _line(BuildContext context, String key, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: <InlineSpan>[
              TextSpan(
                text: '$key: ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      );
}
