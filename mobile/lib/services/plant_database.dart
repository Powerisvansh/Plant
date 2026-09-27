import '../models/scan_models.dart';
import 'plant_catalogue_expansion.dart';

class PlantDiseaseEntry {
  const PlantDiseaseEntry({
    required this.plantId,
    required this.plantName,
    required this.disease,
    required this.summary,
  });

  final String plantId;
  final String plantName;
  final String disease;
  final String summary;
}

/// Curated, locally stored reference database.
///
/// Facts were written from well-established horticultural references
/// (extension publications and standard plant references). Entries are
/// intentionally small so every fact can be verified. The app never guesses
/// extras beyond this file.
class PlantDatabase {
  PlantDatabase._();

  static const List<String> categoryLabels = [
    'all',
    'houseplant',
    'herb',
    'vegetable',
    'flowering',
    'tree',
    'succulent',
    'tropical',
    'frond',
    'garden',
  ];

  static List<String> get categories => List.unmodifiable(categoryLabels);

  static const List<PlantInfo> _baseEntries = [
    PlantInfo(
      id: 'tomato',
      commonName: 'Tomato',
      scientificName: 'Solanum lycopersicum',
      family: 'Solanaceae (nightshade family)',
      origin: 'Western South America (Andes region)',
      sunlight: 'Full sun - at least 6-8 hours of direct light',
      water: 'Keep the soil consistently moist but not soggy',
      soil: 'Fertile, well-drained loam; pH around 6.0-6.8',
      temperature: '18-29 C; severely frost-sensitive',
      growth: 'Warm-season annual; bushy or vining growth habit',
      flowering: 'Yellow flowers; fruit develops 55-90 days after planting',
      commonProblems:
          'Blossom-end rot (calcium/water stress), early blight, leaf curl '
          'in heat, aphids and whitefly.',
      care:
          'Stake or cage plants, water consistently, mulch to keep moisture '
          'even and avoid wetting the foliage too often.',
      facts: [
        'Botanically a fruit; the name "lycopersicum" means "wolf peach".',
        'The tomato is a member of the nightshade family.',
      ],
      emoji: '🍅',
      morphologyTags: ['broadleaf', 'herb', 'vegetable', 'vine-optional'],
      careSummary:
          'Tomatoes need warm weather, steady moisture, and support. Give them full sun, mulch the root zone, and avoid allowing the soil to dry out fast between waterings.',
      commonDiseases: ['Early blight', 'Leaf spot', 'Powdery mildew', 'Blossom-end rot'],
      sicknessReasons: [
        'Overwatering or irregular watering can trigger blossom-end rot and stress.',
        'Warm, wet weather encourages fungal leaf diseases and fruit issues.',
        'Poor airflow and dense foliage keep moisture on leaves longer.',
      ],
      medicineGuidance: [
        'Treat leaf diseases by improving airflow and removing infected leaves first.',
        'Use only a plant product labelled for the exact crop and disease; do not guess a rate.',
        'No exact dosage is shown here. Follow the product label and local extension advice.',
      ],
    ),
    PlantInfo(
      id: 'basil',
      commonName: 'Sweet Basil',
      scientificName: 'Ocimum basilicum',
      family: 'Lamiaceae (mint family)',
      origin: 'Tropical Asia (India region)',
      sunlight: 'Full sun - 6-8 hours',
      water: 'Keep lightly moist; avoid both drought and waterlogging',
      soil: 'Rich, well-drained soil; pH 6-7',
      temperature: '18-30 C; frost-sensitive',
      growth: 'Annual herb reaching about 30-60 cm',
      flowering: 'White flower spikes; pinch them to keep leaves coming',
      commonProblems:
          'Downy mildew, cold spells causing black marks, and aphids.',
      care:
          'Pinch regularly to encourage bushy growth, harvest leaves often, '
          'and provide afternoon shade in very hot climates.',
      facts: [
        'A member of the mint family, rich in aromatic essential oils.',
        'Basil seeds swell into a gel when soaked, like chia seeds.',
      ],
      emoji: '🌿',
      morphologyTags: ['broadleaf', 'herb', 'aromatic'],
    ),
    PlantInfo(
      id: 'mint',
      commonName: 'Mint (Spearmint)',
      scientificName: 'Mentha spicata',
      family: 'Lamiaceae (mint family)',
      origin: 'Europe / western Asia',
      sunlight: 'Full sun to light shade',
      water: 'Prefers reliably moist soil',
      soil: 'Moist, rich soil; pH 6-7.5',
      temperature: '10-25 C; tolerant of cool weather',
      growth: 'Spreading perennial herb; grows vigorously sideways',
      flowering: 'Small purple-white flower spikes in summer',
      commonProblems:
          'Mint rust (a fungus), powdery mildew, and infestations of '
          'spider mites.',
      care:
          'Grow in a pot or sunk container because it spreads aggressively; '
          'harvest regularly.',
      facts: [
        'One of the most ancient cultivated herbs.',
        'The "menthol" that gives the cooling feel comes from its oils.',
      ],
      emoji: '🌱',
      morphologyTags: ['broadleaf', 'herb', 'aromatic', 'spreader'],
    ),
    PlantInfo(
      id: 'pothos',
      commonName: 'Pothos',
      scientificName: 'Epipremnum aureum',
      family: 'Araceae (arum family)',
      origin: 'French Polynesia / Southeast Asia',
      sunlight: 'Bright indirect light; tolerates lower light',
      water: 'Allow the top of the soil to dry between waterings',
      soil: 'Well-draining potting mix',
      temperature: '15-30 C (typical indoor range)',
      growth: 'Trailing or climbing vine with heart-shaped leaves',
      flowering: 'Very rarely flowers indoors',
      commonProblems:
          'Root rot from overwatering, yellowing from overwatering, and '
          'scale insects.',
      care:
          'Easy houseplant; water only when partly dry, wipe leaves, and trim '
          'to shape.',
      facts: [
        'Also known as "devil\u2019s ivy".',
        'One of the most popular houseplants in the world.',
      ],
      emoji: '🪴',
      morphologyTags: ['vine', 'broadleaf', 'houseplant'],
    ),
    PlantInfo(
      id: 'snake_plant',
      commonName: 'Snake Plant',
      scientificName: 'Dracaena trifasciata',
      family: 'Asparagaceae',
      origin: 'West Africa',
      sunlight: 'Low to bright indirect light',
      water: 'Water rarely; let the soil dry out completely',
      soil: 'Well-draining, sandy potting mix',
      temperature: '15-29 C; protect from temperatures below 10 C',
      growth: 'Upright sword-shaped leaves in a rosette',
      flowering: 'Occasional fragrant green-white flower spikes',
      commonProblems:
          'Root rot from overwatering, mealybugs, and scale.',
      care:
          'Overwatering kills it faster than any other mistake; water only '
          'when fully dry.',
      facts: [
        'Also called "mother-in-law\u2019s tongue".',
        'Uses CAM photosynthesis, exchanging gases at night.',
      ],
      emoji: '🌵',
      morphologyTags: ['monocot', 'succulent', 'upright', 'houseplant'],
    ),
    PlantInfo(
      id: 'spider_plant',
      commonName: 'Spider Plant',
      scientificName: 'Chlorophytum comosum',
      family: 'Asparagaceae',
      origin: 'South Africa',
      sunlight: 'Bright indirect light; some direct sun is fine',
      water: 'Keep lightly moist; do not leave it bone dry',
      soil: 'Well-draining soil',
      temperature: '15-27 C',
      growth: 'Rosette of arching, grass-like leaves with plantlets',
      flowering: 'Small white star flowers on long runners',
      commonProblems:
          'Brown leaf tips (dry air, fluoride, or over-fertilising) and '
          'root rot.',
      care:
          'Very easy; remove the little plantlets to make new plants.',
      facts: [
        'Named for the spider-like baby plants on its runners.',
        'Grown as a houseplant for over a century.',
      ],
      emoji: '🍃',
      morphologyTags: ['monocot', 'arching', 'houseplant'],
    ),
    PlantInfo(
      id: 'jade_plant',
      commonName: 'Jade Plant',
      scientificName: 'Crassula ovata',
      family: 'Crassulaceae',
      origin: 'South Africa / Mozambique',
      sunlight: 'Bright light; a few hours of direct sun suits it',
      water: 'Water sparingly; let the soil dry completely',
      soil: 'Succulent or gritty, free-draining mix',
      temperature: '18-24 C; protect from frost (keep above ~7 C)',
      growth: 'Slow-growing succulent shrub with thick stems',
      flowering: 'Small white-pink star flowers, usually in winter',
      commonProblems:
          'Root rot from overwatering, leaf drop from cold, mealybugs and '
          'spider mites.',
      care:
          'One of the classic succulents - more light, less water.',
      facts: [
        'Stores water in its leaves and stem.',
        'Long associated with good luck and prosperity.',
      ],
      emoji: '🪴',
      morphologyTags: ['succulent', 'broadleaf', 'shrub', 'houseplant'],
    ),
    PlantInfo(
      id: 'rosemary',
      commonName: 'Rosemary',
      scientificName: 'Salvia rosmarinus',
      family: 'Lamiaceae (mint family)',
      origin: 'Mediterranean region',
      sunlight: 'Full sun',
      water: 'Let the soil dry between waterings; drought tolerant',
      soil: 'Well-draining, sandy or gritty soil',
      temperature: '4-27 C; tolerates light frost once established',
      growth: 'Woody perennial shrub with needle-like aromatic leaves',
      flowering: 'Small blue flowers in spring/summer',
      commonProblems:
          'Root rot in heavy or waterlogged soil, and powdery mildew.',
      care:
          'Needs excellent drainage; prune to keep it bushy.',
      facts: [
        'The name is thought to mean "dew of the sea".',
        'A staple of Mediterranean cooking.',
      ],
      emoji: '🌿',
      morphologyTags: ['needle-leaf', 'shrub', 'herb', 'aromatic'],
    ),
    PlantInfo(
      id: 'thyme',
      commonName: 'Thyme',
      scientificName: 'Thymus vulgaris',
      family: 'Lamiaceae (mint family)',
      origin: 'Mediterranean region',
      sunlight: 'Full sun',
      water: 'Low water needs; allow soil to dry',
      soil: 'Well-draining, gritty soil',
      temperature: 'Hardy; tolerates frost in most gardens',
      growth: 'Low-growing perennial herb with tiny leaves',
      flowering: 'Small pink or white flowers in summer',
      commonProblems:
          'Root rot from waterlogged soil and aphids.',
      care:
          'Trim it back in spring and avoid overwatering.',
      facts: [
        'Its oil (thymol) has been used historically as an antiseptic.',
      ],
      emoji: '🌿',
      morphologyTags: ['small-leaf', 'herb', 'low-growing'],
    ),
    PlantInfo(
      id: 'lemon',
      commonName: 'Lemon Tree',
      scientificName: 'Citrus limon',
      family: 'Rutaceae (citrus family)',
      origin: 'Northeast India / southern China',
      sunlight: 'Full sun',
      water: 'Consistent watering; less in winter',
      soil: 'Well-drained soil, pH 5.5-6.5',
      temperature: '10-30 C; needs protection from frost',
      growth: 'Evergreen small tree, can be grown in pots',
      flowering: 'Fragrant white flowers, often year-round',
      commonProblems:
          'Yellowing from nutrient uptake problems, sooty mould from sap-'
          'sucking insects, leaf miners and scale.',
      care:
          'Feed with a citrus fertiliser, protect from frost, and check for '
          'pests regularly.',
      facts: [
        'A hybrid of the citron and the sour orange.',
        'One lemon can provide much of an adult\u2019s daily vitamin C.',
      ],
      emoji: '🍋',
      morphologyTags: ['tree', 'broadleaf', 'woody'],
    ),
    PlantInfo(
      id: 'lettuce',
      commonName: 'Lettuce',
      scientificName: 'Lactuca sativa',
      family: 'Asteraceae (daisy family)',
      origin: 'Domesticated around the Mediterranean / Egypt',
      sunlight: 'Full sun to light shade',
      water: 'Keep consistently moist',
      soil: 'Cool, fertile soil; pH 6-6.7',
      temperature: '10-20 C; prefers cool weather and bolts in heat',
      growth: 'Fast-growing annual forming a loose rosette',
      flowering: 'Bolts into a tall flowering stalk in heat',
      commonProblems:
          'Tip burn (irregular water/calcium), slugs, aphids, and bolting '
          'in hot weather.',
      care:
          'Sow in successions, keep shaded and moist in heat.',
      facts: [
        'Belongs to the same family as sunflowers.',
        'Known and cultivated since ancient Egyptian times.',
      ],
      emoji: '🥬',
      morphologyTags: ['broadleaf', 'vegetable', 'rosette'],
    ),
    PlantInfo(
      id: 'boston_fern',
      commonName: 'Boston Fern',
      scientificName: 'Nephrolepis exaltata',
      family: 'Nephrolepidaceae',
      origin: 'Tropical Americas',
      sunlight: 'Bright but indirect light',
      water: 'Keep the soil evenly moist, never bone dry',
      soil: 'Rich, well-draining loamy mix',
      temperature: '15-24 C',
      growth: 'Spreading evergreen fern with arching fronds',
      flowering: 'None - ferns reproduce with spores, not flowers',
      commonProblems:
          'Brown fronds from dry air, scale insects and spider mites.',
      care:
          'Loves humidity; mist the fronds and keep the soil evenly moist.',
      facts: [
        'Ferns are ancient plants that predate flowering plants.',
        'They reproduce through spores on the underside of fronds.',
      ],
      emoji: '🌿',
      morphologyTags: ['fern', 'frond', 'arch'],
    ),
    PlantInfo(
      id: 'african_violet',
      commonName: 'African Violet',
      scientificName: 'Saintpaulia ionantha',
      family: 'Gesneriaceae',
      origin: 'East Africa',
      sunlight: 'Bright indirect light; avoid harsh direct sun',
      water: 'Water from below or keep the top lightly moist',
      soil: 'Light, airy potting mix rich in organic matter',
      temperature: '18-26 C',
      growth: 'Compact flowering houseplant with soft velvety leaves',
      flowering: 'Clusters of purple, pink, white or blue blooms',
      commonProblems:
          'Leaf spots, crown rot from overwatering, and mealybugs.',
      care:
          'Keep leaves dry, water carefully, and fertilise lightly during active growth.',
      facts: [
        'Named after the German botanist Baron Walter von Saint Paul-Illaire.',
        'They are popular for continuous flowering indoors.',
      ],
      emoji: '💜',
      morphologyTags: ['flowering', 'houseplant', 'broadleaf'],
    ),
    PlantInfo(
      id: 'peace_lily',
      commonName: 'Peace Lily',
      scientificName: 'Spathiphyllum wallisii',
      family: 'Araceae',
      origin: 'Central and South America',
      sunlight: 'Low to medium indirect light',
      water: 'Keep evenly moist but not soggy',
      soil: 'Loose, rich, well-draining potting mix',
      temperature: '18-27 C',
      growth: 'Clump-forming tropical foliage plant',
      flowering: 'White spathes on upright stems',
      commonProblems:
          'Yellow leaves from overwatering, brown edges from dry air, and scale insects.',
      care:
          'Use filtered light, maintain humidity, and trim spent blooms regularly.',
      facts: [
        'Its white “flower” is actually a modified leaf called a spathe.',
        'It is widely grown as a low-light indoor foliage plant.',
      ],
      emoji: '🕊️',
      morphologyTags: ['houseplant', 'broadleaf', 'tropical'],
    ),
    PlantInfo(
      id: 'zz_plant',
      commonName: 'ZZ Plant',
      scientificName: 'Zamioculcas zamiifolia',
      family: 'Araceae',
      origin: 'Eastern Africa',
      sunlight: 'Low to bright indirect light',
      water: 'Only when the soil is mostly dry',
      soil: 'Well-draining mix rich in organic matter',
      temperature: '15-30 C',
      growth: 'Glossy upright stems with waxy leaflets',
      flowering: 'Rarely flowers indoors',
      commonProblems:
          'Root rot from excess moisture and mealybugs.',
      care:
          'Very forgiving; few things are more damaging than frequent watering.',
      facts: [
        'The plant stores water in thick underground rhizomes.',
        'It is one of the easiest low-maintenance houseplants.',
      ],
      emoji: '🪴',
      morphologyTags: ['houseplant', 'upright', 'tropical'],
    ),
    PlantInfo(
      id: 'rubber_plant',
      commonName: 'Rubber Plant',
      scientificName: 'Ficus elastica',
      family: 'Moraceae',
      origin: 'South and Southeast Asia',
      sunlight: 'Bright indirect light',
      water: 'Allow the top layer to dry before watering',
      soil: 'Loose, nutrient-rich, well-drained mix',
      temperature: '18-30 C',
      growth: 'Large-leaved indoor tree with a strong trunk',
      flowering: 'Rarely flowers indoors',
      commonProblems:
          'Leaf drop from sudden changes, spider mites, and scale.',
      care:
          'Rotate for even growth and avoid keeping it in cold drafts.',
      facts: [
        'Its latex was historically used in rubber production.',
        'Modern ornamental forms are often grown for their patterned foliage.',
      ],
      emoji: '🌳',
      morphologyTags: ['tree', 'houseplant', 'broadleaf'],
    ),
    PlantInfo(
      id: 'monstera',
      commonName: 'Monstera',
      scientificName: 'Monstera deliciosa',
      family: 'Araceae',
      origin: 'Southern Mexico to Panama',
      sunlight: 'Bright indirect light',
      water: 'Water when the top 2-3 cm is dry',
      soil: 'Well-draining, chunky mix with aeration',
      temperature: '18-30 C',
      growth: 'Fast-climbing tropical vine with split leaves',
      flowering: 'Large cream inflorescence, uncommon indoors',
      commonProblems:
          'Yellowing from overwatering, browning from underwatering, and gnats.',
      care:
          'Support with a moss pole or stake and keep humidity moderate to high.',
      facts: [
        'Young leaves may start as whole leaves and later split as the plant matures.',
        'It is one of the most recognizable tropical foliage plants.',
      ],
      emoji: '🌿',
      morphologyTags: ['vine', 'tropical', 'large-leaf'],
    ),
    PlantInfo(
      id: 'aloe_vera',
      commonName: 'Aloe Vera',
      scientificName: 'Aloe vera',
      family: 'Asphodelaceae',
      origin: 'Arabian Peninsula',
      sunlight: 'Bright, direct or indirect light',
      water: 'Water deeply but infrequently',
      soil: 'Cactus or gritty free-draining mix',
      temperature: '18-30 C',
      growth: 'Succulent rosette with thick fleshy leaves',
      flowering: 'Tall orange-red flower stalks in warm weather',
      commonProblems:
          'Soft mushy leaves from overwatering and mealybugs.',
      care:
          'Do not leave the roots in soggy soil; good drainage matters most.',
      facts: [
        'Aloe gel is famous for soothing skin irritation.',
        'The genus name Aloe comes from the Arabic word for bitter.',
      ],
      emoji: '🌵',
      morphologyTags: ['succulent', 'rosette', 'houseplant'],
    ),
    PlantInfo(
      id: 'lavender',
      commonName: 'Lavender',
      scientificName: 'Lavandula angustifolia',
      family: 'Lamiaceae',
      origin: 'Mediterranean region',
      sunlight: 'Full sun',
      water: 'Low water needs once established',
      soil: 'Well-drained, slightly alkaline soil',
      temperature: '10-28 C',
      growth: 'Dense woody subshrub with narrow leaves',
      flowering: 'Purple flower spikes in summer',
      commonProblems:
          'Root rot in wet soils, aphids, and spider mites.',
      care:
          'Prune lightly after flowering and avoid heavy feeding.',
      facts: [
        'The scented oil is widely used in perfumery and calming products.',
        'Lavender is a classic drought-tolerant herb for sunny gardens.',
      ],
      emoji: '💜',
      morphologyTags: ['herb', 'shrub', 'aromatic'],
    ),
    PlantInfo(
      id: 'parsley',
      commonName: 'Parsley',
      scientificName: 'Petroselinum crispum',
      family: 'Apiaceae',
      origin: 'Mediterranean region',
      sunlight: 'Full sun to light shade',
      water: 'Keep the soil lightly moist',
      soil: 'Loose, fertile, well-drained mix',
      temperature: '10-24 C',
      growth: 'Biennial herb with bright green compound leaves',
      flowering: 'Tiny yellow-green umbels in the second year',
      commonProblems:
          'Leaf spot, root stress from dry heat, and aphids.',
      care:
          'Harvest often and keep the soil evenly moist in warm weather.',
      facts: [
        'Parsley is a classic culinary herb with a strong flavor profile.',
        'It is often grown as a biennial even though it is used as an annual crop.',
      ],
      emoji: '🌿',
      morphologyTags: ['herb', 'leafy', 'garden'],
    ),
    PlantInfo(
      id: 'cilantro',
      commonName: 'Cilantro',
      scientificName: 'Coriandrum sativum',
      family: 'Apiaceae',
      origin: 'Mediterranean / Middle East',
      sunlight: 'Full sun to part shade',
      water: 'Keep lightly moist and cool',
      soil: 'Rich, well-drained soil',
      temperature: '15-25 C',
      growth: 'Fast-growing leafy annual herb',
      flowering: 'Small white or pink umbels as it matures',
      commonProblems:
          'Bolting in heat, leaf spot, and aphids.',
      care:
          'Grow in cooler conditions and succession sow for steady harvests.',
      facts: [
        'Cilantro is the leaves; coriander is the seed from the same plant.',
        'It often bolts quickly in warm weather.',
      ],
      emoji: '🌱',
      morphologyTags: ['herb', 'leafy', 'cool-season'],
    ),
    PlantInfo(
      id: 'chili_pepper',
      commonName: 'Chili Pepper',
      scientificName: 'Capsicum annuum',
      family: 'Solanaceae',
      origin: 'Mexico / Central America',
      sunlight: 'Full sun',
      water: 'Keep evenly moist, not soggy',
      soil: 'Warm, fertile, well-drained soil',
      temperature: '20-30 C',
      growth: 'Warm-season compact shrub or shrub-like annual',
      flowering: 'White to green flowers followed by fruit',
      commonProblems:
          'Flower drop in cold weather, aphids, and fungal leaf spots.',
      care:
          'Feed regularly and keep the roots warm for steady fruiting.',
      facts: [
        'The fruit can range from mild to extremely hot depending on variety.',
        'Peppers are closely related to tomatoes and potatoes.',
      ],
      emoji: '🌶️',
      morphologyTags: ['vegetable', 'fruiting', 'warm-season'],
    ),
    PlantInfo(
      id: 'sunflower',
      commonName: 'Sunflower',
      scientificName: 'Helianthus annuus',
      family: 'Asteraceae',
      origin: 'North America',
      sunlight: 'Full sun',
      water: 'Moderate water; avoid stress during flowering',
      soil: 'Well-drained, fertile soil',
      temperature: '15-30 C',
      growth: 'Tall annual with strong upright stems',
      flowering: 'Large yellow flower heads following the sun',
      commonProblems:
          'Rust, mildew, seedling damping-off, and aphids.',
      care:
          'Give space, sturdy support if needed, and deep watering in dry spells.',
      facts: [
        'Sunflowers track the sun when young and are famous for large composite heads.',
        'They can also help attract pollinators and birds.',
      ],
      emoji: '🌻',
      morphologyTags: ['flowering', 'annual', 'tall'],
    ),
    PlantInfo(
      id: 'marigold',
      commonName: 'Marigold',
      scientificName: 'Tagetes erecta',
      family: 'Asteraceae',
      origin: 'Mexico / Central America',
      sunlight: 'Full sun',
      water: 'Keep soil evenly moist but not saturated',
      soil: 'Fertile, well-drained loamy soil',
      temperature: '18-30 C',
      growth: 'Bushy bedding plant with bright flowers',
      flowering: 'Orange, yellow or red blooms over a long season',
      commonProblems:
          'Powdery mildew, aphids, and root stress in poor drainage.',
      care:
          'Deadhead regularly to keep flowering and improve appearance.',
      facts: [
        'Marigolds are commonly used around crops to support pollinators and companion planting.',
        'Their strong scent can help deter some pests in garden beds.',
      ],
      emoji: '🌼',
      morphologyTags: ['flowering', 'annual', 'garden'],
    ),
    PlantInfo(
      id: 'orchid',
      commonName: 'Orchid',
      scientificName: 'Phalaenopsis spp.',
      family: 'Orchidaceae',
      origin: 'Southeast Asia and Australia',
      sunlight: 'Bright filtered light',
      water: 'Water thoroughly, then allow roots to dry somewhat',
      soil: 'Airy bark or orchid mix',
      temperature: '18-29 C',
      growth: 'Epiphytic flowering plant with aerial roots',
      flowering: 'Long-lasting blooms in many colours',
      commonProblems:
          'Root rot from constant wetness, leaf yellowing, and scale.',
      care:
          'Provide good airflow and avoid overwatering, especially in cool periods.',
      facts: [
        'Orchids are among the largest families of flowering plants.',
        'Many species grow on trees rather than in soil.',
      ],
      emoji: '🌸',
      morphologyTags: ['flowering', 'epiphyte', 'houseplant'],
    ),
    PlantInfo(
      id: 'peperomia',
      commonName: 'Peperomia',
      scientificName: 'Peperomia obtusifolia',
      family: 'Piperaceae',
      origin: 'Tropical Americas',
      sunlight: 'Medium to bright indirect light',
      water: 'Water when the top layer dries slightly',
      soil: 'Light, airy potting mix',
      temperature: '18-27 C',
      growth: 'Compact foliage plant with thick leaves',
      flowering: 'Small green-white flower spikes occasionally',
      commonProblems:
          'Overwatering, yellowing leaves, and mealybugs.',
      care:
          'Keep it in stable indoor conditions and avoid cold drafts.',
      facts: [
        'Peperomias are known for their diverse textures and leaf shapes.',
        'Some are grown for ornamental foliage rather than flowers.',
      ],
      emoji: '🍃',
      morphologyTags: ['houseplant', 'broadleaf', 'tropical'],
    ),
    PlantInfo(
      id: 'hydrangea',
      commonName: 'Hydrangea',
      scientificName: 'Hydrangea macrophylla',
      family: 'Hydrangeaceae',
      origin: 'Japan and eastern Asia',
      sunlight: 'Morning sun with afternoon shade',
      water: 'Keep soil evenly moist in warm weather',
      soil: 'Rich, moisture-retentive soil',
      temperature: '15-25 C',
      growth: 'Showy flowering shrub with large heads',
      flowering: 'Large clusters of pink, blue or white blooms',
      commonProblems:
          'Wilting in dry soil, fungal leaf spots, and aphids.',
      care:
          'Mulch and water regularly, especially during bloom formation.',
      facts: [
        'Flower colour can shift depending on soil acidity.',
        'Hydrangeas are often prized for large ornamental flower heads.',
      ],
      emoji: '💐',
      morphologyTags: ['flowering', 'shrub', 'garden'],
    ),
    PlantInfo(
      id: 'kale',
      commonName: 'Kale',
      scientificName: 'Brassica oleracea var. sabellica',
      family: 'Brassicaceae',
      origin: 'Mediterranean and coastal Europe',
      sunlight: 'Full sun to part shade',
      water: 'Keep evenly moist for tender leaves',
      soil: 'Fertile, cool-season soil with good drainage',
      temperature: '10-20 C',
      growth: 'Cool-season leafy vegetable with frilled leaves',
      flowering: 'Yellow flowers if it bolts',
      commonProblems:
          'Cabbage worms, aphids, and bolting in heat.',
      care:
          'Harvest outer leaves regularly and provide cool conditions for best texture.',
      facts: [
        'Kale is very hardy and tolerates frost better than many greens.',
        'Its leaves are rich in vitamins and hardy leafy greens can be harvested repeatedly.',
      ],
      emoji: '🥬',
      morphologyTags: ['vegetable', 'leafy', 'cool-season'],
    ),
    PlantInfo(
      id: 'grape_vine',
      commonName: 'Grape Vine',
      scientificName: 'Vitis vinifera',
      family: 'Vitaceae',
      origin: 'Near East and Mediterranean',
      sunlight: 'Full sun',
      water: 'Deep watering during dry growth periods',
      soil: 'Well-drained, fertile soil',
      temperature: '15-30 C',
      growth: 'Climbing vine with woody stems',
      flowering: 'Small green flower clusters',
      commonProblems:
          'Powdery mildew, fungal leaf spots, and mealybugs.',
      care:
          'Train on support, prune in season, and keep the vines airy.',
      facts: [
        'Grapes have been cultivated for millennia for fruit and wine.',
        'The vine is a classic climbing crop with annual pruning needs.',
      ],
      emoji: '🍇',
      morphologyTags: ['vine', 'fruiting', 'garden'],
    ),
    PlantInfo(
      id: 'cactus',
      commonName: 'Cactus',
      scientificName: 'Cactaceae family',
      family: 'Cactaceae',
      origin: 'Americas',
      sunlight: 'Bright direct light',
      water: 'Very sparse watering; let the mix dry thoroughly',
      soil: 'Fast-draining cactus mix',
      temperature: '15-30 C',
      growth: 'Succulent stem-forming plant with spines',
      flowering: 'Showy bloom depending on species and season',
      commonProblems:
          'Overwatering, root rot, and scale insects.',
      care:
          'Give strong light and drainage; many cactus problems come from wet roots.',
      facts: [
        'Cacti are adapted to arid environments with water-storing tissues.',
        'Many species have evolved spines as protection and to reduce transpiration.',
      ],
      emoji: '🌵',
      morphologyTags: ['succulent', 'arid', 'houseplant'],
    ),
    PlantInfo(
      id: 'gardenia',
      commonName: 'Gardenia',
      scientificName: 'Gardenia jasminoides',
      family: 'Rubiaceae',
      origin: 'China, Japan and Southeast Asia',
      sunlight: 'Bright filtered light',
      water: 'Keep evenly moist but not soggy',
      soil: 'Acidic, fertile, well-drained soil',
      temperature: '18-26 C',
      growth: 'Dense evergreen shrub with glossy leaves',
      flowering: 'Highly fragrant white flowers',
      commonProblems:
          'Yellowing leaves, scale insects, and dry leaf edges.',
      care:
          'Use regular watering and keep it in a stable, bright, sheltered place.',
      facts: [
        'Gardenias are prized for their very fragrant flowers.',
        'They prefer acidic soil and can struggle in alkaline conditions.',
      ],
      emoji: '🌼',
      morphologyTags: ['flowering', 'shrub', 'houseplant'],
    ),
    PlantInfo(
      id: 'bamboo',
      commonName: 'Bamboo',
      scientificName: 'Bambusa spp.',
      family: 'Poaceae',
      origin: 'Asia and the Americas',
      sunlight: 'Bright indirect light to full sun',
      water: 'Keep the soil consistently moist',
      soil: 'Rich, well-drained, slightly acidic soil',
      temperature: '18-30 C',
      growth: 'Fast-growing grass with woody shoots',
      flowering: 'Rare, highly varied by species',
      commonProblems:
          'Leaf yellowing in poor drainage and occasional spider mites.',
      care:
          'Grow in a large container or area with room for spread and regular watering.',
      facts: [
        'Bamboo is actually a grass, not a tree.',
        'Some species are among the fastest-growing plants on earth.',
      ],
      emoji: '🎍',
      morphologyTags: ['garden', 'grass', 'tropical'],
    ),
  ];

  static final List<PlantInfo> _entries = <PlantInfo>[...
    _baseEntries,
    ...buildExpandedPlantCatalog(),
  ];

  static final Map<String, PlantInfo> _byId = {
    for (final e in _entries) e.id: e,
  };

  static List<PlantInfo> get all => List.unmodifiable(_entries);

  static List<PlantDiseaseEntry> diseaseByPlantIndex() {
    final entries = <PlantDiseaseEntry>[];
    for (final plant in _entries) {
      final diseases = plant.commonDiseases.isEmpty
          ? <String>[plant.commonName]
          : plant.commonDiseases;
      for (final disease in diseases) {
        entries.add(
          PlantDiseaseEntry(
            plantId: plant.id,
            plantName: plant.commonName,
            disease: disease,
            summary: plant.careSummary.isNotEmpty
                ? '${disease}: ${plant.careSummary}'
                : plant.sicknessReasons.isNotEmpty
                    ? '${disease}: ${plant.sicknessReasons.first}'
                    : 'Improve air flow, observe the plant carefully, and follow product-label guidance for treatment.',
          ),
        );
      }
    }
    return entries;
  }

  static List<PlantDiseaseEntry> diseaseByPlant(String plantId) {
    return diseaseByPlantIndex()
        .where((entry) => entry.plantId == plantId)
        .toList();
  }

  static List<PlantDiseaseEntry> searchDiseaseByPlant(String query) {
    final normalized = query.trim().toLowerCase();
    final entries = diseaseByPlantIndex();
    if (normalized.isEmpty) return entries;
    return entries
        .where(
          (entry) => '${entry.plantName} ${entry.disease} ${entry.summary}'
              .toLowerCase()
              .contains(normalized),
        )
        .toList();
  }

  static PlantInfo? byId(String id) => _byId[id];

  static PlantInfo? extraFor(String id) => _byId[id];

  static List<PlantInfo> search(String query, {String category = 'all'}) {
    final normalizedQuery = query.trim().toLowerCase();
    final selectedCategory = category.toLowerCase();

    final filtered = _entries.where((plant) {
      if (selectedCategory != 'all') {
        final tags = plant.morphologyTags.map((tag) => tag.toLowerCase()).toSet();
        final categoryMatch = tags.contains(selectedCategory) ||
            plant.commonName.toLowerCase().contains(selectedCategory) ||
            plant.scientificName.toLowerCase().contains(selectedCategory);
        if (!categoryMatch) return false;
      }

      if (normalizedQuery.isEmpty) return true;

      final text = [
        plant.commonName,
        plant.scientificName,
        plant.family,
        plant.origin,
        plant.commonProblems,
        plant.care,
        ...plant.facts,
      ].join(' ').toLowerCase();

      return text.contains(normalizedQuery);
    }).toList();

    return filtered;
  }

  /// Lookup by common name substring (used for tagging user-named plants).
  static PlantInfo? byCommonName(String name) {
    final low = name.toLowerCase();
    for (final e in _entries) {
      if (low.contains(e.commonName.toLowerCase())) return e;
      if (e.commonName.toLowerCase().contains(low)) return e;
    }
    return null;
  }
}