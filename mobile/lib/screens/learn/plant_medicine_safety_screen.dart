import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/plant_health_content.dart';

class PlantMedicineSafetyScreen extends StatelessWidget {
  const PlantMedicineSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Using plant medicine safely')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.danger,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Identify before you treat',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Plant symptoms are not a diagnosis. The wrong pesticide can burn a plant, harm beneficial insects, contaminate food or make a disease worse.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SafetySection(
            title: 'First 10 minutes',
            icon: Icons.timer_outlined,
            color: AppColors.danger,
            children: [
              for (
                var index = 0;
                index < PlantHealthContent.emergencySteps.length;
                index++
              )
                _NumberedInstruction(
                  number: index + 1,
                  text: PlantHealthContent.emergencySteps[index],
                ),
            ],
          ),
          const _SafetySection(
            title: 'Choose treatment in this order',
            icon: Icons.stairs_outlined,
            color: AppColors.primary,
            children: [
              _PlainInstruction(
                number: '1',
                title: 'Contain a possible infection or infestation',
                text: 'Isolate the plant when a contagious disease or mobile pest is possible before moving among healthy plants.',
              ),
              _PlainInstruction(
                number: '2',
                title: 'Correct the environment',
                text: 'Fix light, drainage, watering, heat, crowding and airflow before treating symptoms.',
              ),
              _PlainInstruction(
                number: '3',
                title: 'Remove or exclude the source',
                text: 'Prune infected tissue, remove pests by hand, use barriers or remove an infected plant when advised.',
              ),
              _PlainInstruction(
                number: '4',
                title: 'Use biological controls carefully',
                text: 'Beneficial insects, microbes and nematodes work only for the target species, life stage and conditions.',
              ),
              _PlainInstruction(
                number: '5',
                title: 'Use a registered product last',
                text: 'Confirm the exact plant, problem, region and edible-crop permission on the product label.',
              ),
            ],
          ),
          _SafetySection(
            title: 'Before opening any pesticide',
            icon: Icons.checklist_rtl_outlined,
            color: AppColors.teal,
            children: [
              for (final instruction in PlantHealthContent.medicineSafety)
                _BulletInstruction(text: instruction),
            ],
          ),
          const _SafetySection(
            title: 'For vegetables, fruit and herbs',
            icon: Icons.restaurant_outlined,
            color: AppColors.amber,
            children: [
              _PlainInstruction(
                number: '!',
                title: 'Check the crop on the label',
                text: 'A product for ornamental plants may not be legal on food plants. The plant and part eaten must be listed.',
              ),
              _PlainInstruction(
                number: '!',
                title: 'Follow the harvest interval',
                text: 'Wait the full labelled time between the last application and harvest. Washing produce does not make an unapproved treatment safe.',
              ),
              _PlainInstruction(
                number: '!',
                title: 'Keep records',
                text: 'Record product, active ingredient, date, crop, weather and application area so local advice can be accurate.',
              ),
            ],
          ),
          const _SafetySection(
            title: 'If exposure may have occurred',
            icon: Icons.emergency_outlined,
            color: AppColors.danger,
            children: [
              _PlainInstruction(
                number: '!',
                title: 'Use the product label first',
                text: 'Move away from the treated area, remove contaminated clothing if directed, and follow the label first-aid instructions.',
              ),
              _PlainInstruction(
                number: '!',
                title: 'Get urgent professional help',
                text: 'For ingestion, breathing trouble, severe irritation, or pet or livestock exposure, contact a poison centre, emergency service, veterinarian or local authority immediately.',
              ),
              _PlainInstruction(
                number: '!',
                title: 'Bring the label',
                text: 'Keep the product container or a photo of its label. Do not delay urgent help while searching online.',
              ),
            ],
          ),
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
                      'This guide gives general education, not a diagnosis or prescription. Registration, crop approvals, protective equipment and harvest rules differ by country. The current product label and local extension or plant-clinic advice take priority.',
                      style: theme.textTheme.bodyMedium,
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

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedInstruction extends StatelessWidget {
  const _NumberedInstruction({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              '$number',
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
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainInstruction extends StatelessWidget {
  const _PlainInstruction({
    required this.number,
    required this.title,
    required this.text,
  });

  final String number;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.ink.withValues(alpha: 0.07),
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletInstruction extends StatelessWidget {
  const _BulletInstruction({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(
              Icons.check_circle_outline,
              size: 17,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
