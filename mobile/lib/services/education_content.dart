import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/education_models.dart';

/// Curated educational content: Learn topics and the rotating Home tips.
///
/// Facts below are general, widely-published plant science basics. They are
/// intentionally conservative - no cultivar-specific claims, no chemical
/// recipes. The "how the analysis works" topic describes the real on-device
/// algorithm in this repository.
class EducationContent {
  EducationContent._();

  // ----------------------------------------------------------------- Home tip

  static const List<PlantTip> _tips = [
    PlantTip(
      title: 'Water less often, more deeply',
      body: 'Deep, infrequent watering encourages roots to grow downwards. '
          'A constantly damp top layer often signals overwatering.',
    ),
    PlantTip(
      title: 'Yellow leaves can be normal',
      body: 'Lower, older leaves naturally yellow and drop as a plant '
          'recycles their nutrients. Check new growth before acting.',
    ),
    PlantTip(
      title: 'Look at the leaf surface',
      body: 'Fuzzy or dusty-looking spots on leaf tops are often harmless '
          'dust or minerals. Soft, mushy, or hole-riddled tissue matters more.',
    ),
    PlantTip(
      title: 'Make sure it can breathe',
      body: 'Crowded plants trap humid air. A little airflow around leaves '
          'helps prevent many fungal leaf problems.',
    ),
    PlantTip(
      title: 'Check the pothole method',
      body: 'Before watering, push a finger a few centimetres into the soil. '
          'If it still feels moist, wait another day or two.',
    ),
    PlantTip(
      title: 'Sunburn looks like bleach, not rot',
      body: 'Sudden direct sun often bleaches leaves pale or crispy-brown '
          'on the edges - different from the soft, mushy look of rot.',
    ),
    PlantTip(
      title: 'Wet soil is not always "fed"',
      body: 'Roots need air as well as water. Soggy soil suffocates roots '
          'and causes yellowing that looks exactly like drought.',
    ),
    PlantTip(
      title: 'Signs of pests hide below',
      body: 'Many insects live under the leaf. If you suspect pests, check '
          'the underside and the stems, not just the top.',
    ),
    PlantTip(
      title: 'Symptoms have multiple causes',
      body: 'The same yellow or spotted leaf can come from water, light, '
          'nutrients or age. Always check conditions before treating.',
    ),
    PlantTip(
      title: 'Take photos in good light',
      body: 'PlantDoctor analyses are most reliable on sharp, well-lit '
          'photos. Avoid harsh shadows and blurred close-ups.',
    ),
  ];

  /// Deterministic tip for a given date (day-of-year rotation).
  static PlantTip tipOfDay(DateTime day) {
    final start = DateTime(day.year);
    final doy = day.difference(start).inDays;
    return _tips[doy % _tips.length];
  }

  // ------------------------------------------------------------- Learn topics

  static const List<LearnTopic> topics = [
    LearnTopic(
      id: 'photosynthesis',
      title: 'Photosynthesis',
      subtitle: 'How a plant turns light into food',
      icon: Icons.wb_sunny_outlined,
      color: AppColors.amber,
      sections: [
        (
          'What it is',
          'Photosynthesis is how green plants turn light energy, water and '
              'carbon dioxide into sugars - their food - and release oxygen. '
              'It happens mainly in the leaves, in structures called '
              'chloroplasts, driven by chlorophyll (the green pigment).',
        ),
        (
          'The inputs and outputs',
          'Simplified: light + water + carbon dioxide -> sugar + oxygen. '
              'If light, water or air is lacking, photosynthesis slows and '
              'the plant grows more slowly or starts showing stress.',
        ),
        (
          'Why this matters for health',
          'A plant that receives too little light but too much water often '
              'yellow from the bottom. Plants that receive harsh direct sun '
              'can "bleach". Knowing a plant\u2019s light needs is the first '
              'fix for many issues.',
        ),
      ],
    ),
    LearnTopic(
      id: 'nutrition',
      title: 'Plant nutrition',
      subtitle: 'Which nutrients do what',
      icon: Icons.science_outlined,
      color: AppColors.teal,
      sections: [
        (
          'The big three',
          'Nitrogen (N) drives leaf growth and green colour; a shortage '
              'often shows as overall yellowing of older leaves. Phosphorus '
              '(P) supports roots and flowering. Potassium (K) regulates '
              'water balance and disease resistance - shortages can appear '
              'as brown leaf edges.',
        ),
        (
          'Micronutrients',
          'Iron, magnesium, and manganese are needed in small amounts but '
              'matter for chlorophyll. Yellowing *between the veins* while '
              'veins stay green is the classic pattern of iron or magnesium '
              'trouble, depending on which leaves are affected.',
        ),
        (
          'The honest caveat',
          'Leaf colours almost never prove a single nutrient problem. '
              'Watering, soil pH and root health change how nutrients are '
              'available. Treat nutrient ideas as hypotheses to check, not '
              'confirmed diagnosis.',
        ),
      ],
    ),
    LearnTopic(
      id: 'diseases',
      title: 'Plant diseases',
      subtitle: 'Fungal, bacterial and viral basics',
      icon: Icons.coronavirus_outlined,
      color: AppColors.danger,
      sections: [
        (
          'The three groups',
          'Most leaf diseases are fungal (spotty, powdery, or rust marks), '
              'some are bacterial (often wet, oozing, angular spots), and '
              'a few are viral (mottling, stunted or distorted growth). '
              'Many look similar from a distance.',
        ),
        (
          'How they spread',
          'Fungal spores travel on air, water splash and tools. Wet foliage, '
              'poor airflow and reused soil all raise the risk. This is why '
              'so many care guides say "avoid wetting leaves".',
        ),
        (
          'What a photo can and cannot show',
          'A photo can show a fungus-like pattern, but identifying the '
              'specific organism usually needs a lab or a qualified plant '
              'clinic. PlantDoctor always labels these as possible causes, '
              'described as hypotheses.',
        ),
      ],
    ),
    LearnTopic(
      id: 'pests',
      title: 'Common pests',
      subtitle: 'Why to check under the leaves',
      icon: Icons.bug_report_outlined,
      color: AppColors.warn,
      sections: [
        (
          'Sap feeders',
          'Aphids, whitefly, scale and spider mites suck plant juice. Signs '
              'include sticky residue, pale speckling, curled new growth, or '
              'fine webbing - often on the leaf underside.',
        ),
        (
          'Chewers and borers',
          'Caterpillars and slugs eat visible holes and edges. Leaf miners '
              'leave pale winding tunnels inside the leaf tissue.',
        ),
        (
          'What to do first',
          'Inspect undersides, stems and new growth. Many small infestations '
              'start with washing or physical removal. Only reach for '
              'chemicals after identifying the actual pest and following the '
              'product label and local guidance.',
        ),
      ],
    ),
    LearnTopic(
      id: 'water_stress',
      title: 'Water stress',
      subtitle: 'Too much and too little',
      icon: Icons.water_drop_outlined,
      color: AppColors.primary,
      sections: [
        (
          'Under-watering',
          'Drooping, crisp brown tips and dry soil are the classic signs. '
              'Consistent moisture usually fixes this quickly.',
        ),
        (
          'Over-watering',
          'Surprisingly, over-watering also causes yellowing, wilting and '
              'brown edges, because roots drown and cannot take up water. '
              'Soggy soil plus yellowing usually means too much, not too '
              'little, water.',
        ),
        (
          'A quick check',
          'Let the top of the soil dry between waterings for most plants, '
              'then water thoroughly. Match watering to the plant species, '
              'the pot size and the season - not to a fixed calendar date.',
        ),
      ],
    ),
    LearnTopic(
      id: 'soil',
      title: 'Soil',
      subtitle: 'Drainage, texture and pH',
      icon: Icons.terrain_outlined,
      color: AppColors.amber,
      sections: [
        (
          'The two jobs',
          'Soil supports roots and stores the water and nutrients a plant '
              'needs. Good soil holds moisture but still drains, so roots '
              'get both water and air.',
        ),
        (
          'Drainage matters most',
          'More houseplants die from poor drainage than from poor nutrition. '
              'A pot must have drainage holes, and heavy garden soil turns '
              'into suffocating mud when container-grown.',
        ),
        (
          'pH controls availability',
          'Acid or alkaline extremes lock up nutrients even when fertiliser '
              'is present. Most vegetables and houseplants prefer a slightly '
              'acidic to neutral pH - but every species has its own range.',
        ),
      ],
    ),
    LearnTopic(
      id: 'plant_care',
      title: 'Plant care basics',
      subtitle: 'Light, water, air and patience',
      icon: Icons.spa_outlined,
      color: AppColors.primary,
      sections: [
        (
          'Light is the biggest lever',
          'Match the plant to the spot: direct-sun plants fail indoors, '
              'and low-light plants burn in a bright window. Most indoor '
              'issues trace back to a light mismatch.',
        ),
        (
          'Air and humidity',
          'Heating dries indoor air. Brown leaf tips are common in dry '
              'rooms. Grouping plants, occasional misting, or a small '
              'humidity tray can help moisture lovers.',
        ),
        (
          'Change slowly',
          'Plants adjust gradually. When moving or repotting a plant, do it '
              'in steps, and give it a few weeks before judging the result.',
        ),
      ],
    ),
    LearnTopic(
      id: 'how_analysis_works',
      title: 'How the analysis works',
      subtitle: 'The real on-device algorithm',
      icon: Icons.memory_outlined,
      color: AppColors.forest,
      sections: [
        (
          'Pixels, not magic',
          'PlantDoctor downscales your photo to a small grid and classifies '
              'each cell by colour in the HSL model: green leaf tissue, '
              'yellow (chlorotic) areas, brown (damaged) areas, and dark '
              'zones.',
        ),
        (
          'Measuring patterns',
          'A flood-fill finds connected leaf regions and damage clusters, so '
              'the app can draw a box around the affected area. It also '
              'estimates sharpness (Laplacian variance) and brightness, '
              'which feed the quality warnings.',
        ),
        (
          'Combining into a health index',
          'The PlantDoctor Health Index weights five measured signals: color '
              'condition, visible damage, spot/lesion area, leaf integrity '
              'and texture deviation. It is an experimental software metric '
              'for demonstration - not a standard.',
        ),
      ],
    ),
    LearnTopic(
      id: 'ai_limits',
      title: 'Limits of AI plant diagnosis',
      subtitle: 'Why a photo is never proof',
      icon: Icons.priority_high_outlined,
      color: AppColors.warn,
      sections: [
        (
          'Photos show symptoms, not causes',
          'Yellowing can come from nutrients, water, pests, light, pH or '
              'age. A camera cannot see the roots, the soil, or the history '
              'of the plant - all of which separate one cause from another.',
        ),
        (
          'Similar-looking diseases differ',
          'Many fungal and bacterial leaf patterns look almost identical in '
              'a photo. Confident "diagnosis" by image alone would be '
              'untruthful, so PlantDoctor reports possible causes instead.',
        ),
        (
          'Rule of thumb',
          'Use the app as a screening aid that guides your eyes and your '
              'next questions. For real decisions - especially with '
              'expensive plants or any chemical treatment - confirm with a '
              'plant clinic, extension service or qualified professional.',
        ),
      ],
    ),
    LearnTopic(
      id: 'plant_biology',
      title: 'Plant biology',
      subtitle: 'Roots, stems and leaves at a glance',
      icon: Icons.landscape_outlined,
      color: AppColors.teal,
      sections: [
        (
          'Roots',
          'Roots anchor the plant and take up water and minerals. Their '
              'health decides everything above ground: a damaged or drowned '
              'root system shows up as leaf symptoms.',
        ),
        (
          'Stems',
          'Stems carry water and nutrients between roots and leaves through '
              'xylem (water up) and phloem (food around). They also store '
              'reserves in many plants.',
        ),
        (
          'Leaves',
          'Leaves are the food factories: capture light, exchange gases '
              'through pores (stomata), and lose water by evaporation. '
              'That is why leaf colour and texture are such useful early '
              'warning signals.',
        ),
      ],
    ),
  ];

  static final Map<String, LearnTopic> _byId = {
    for (final t in topics) t.id: t,
  };

  static LearnTopic? byId(String id) => _byId[id];

  /// Deterministic pseudo-random tip/topic picker for tests.
  static int seedIndex(int seed, int length) {
    if (length <= 0) return 0;
    var n = seed;
    for (var i = 0; i < 3; i++) {
      n = (n * 1103515245 + 12345) & 0x7fffffff;
    }
    return n % length;
  }
}