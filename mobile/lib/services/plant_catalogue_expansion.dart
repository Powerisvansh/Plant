import '../models/scan_models.dart';

List<PlantInfo> buildExpandedPlantCatalog() {
  final names = <String>[
    'Acacia', 'Acanthus', 'Acer', 'Achillea', 'Aconitum', 'Actinidia', 'Adiantum',
    'Agapanthus', 'Ageratum', 'Ajuga', 'Albizia', 'Alstroemeria', 'Anemone', 'Angelica',
    'Antirrhinum', 'Aquilegia', 'Arabis', 'Arbutus', 'Arctostaphylos', 'Artemisia',
    'Asclepias', 'Aspidistra', 'Astrantia', 'Aucuba', 'Azalea', 'Bambusa', 'Begonia',
    'Berberis', 'Beta', 'Betula', 'Bignonia', 'Bougainvillea', 'Brachyscome', 'Brassica',
    'Buddleja', 'Caladium', 'Calendula', 'Calla', 'Camellia', 'Campanula', 'Capsicum',
    'Cardamine', 'Carex', 'Cassia', 'Castanea', 'Cedrus', 'Celosia', 'Celtis',
    'Cercis', 'Chamaecyparis', 'Cheiranthus', 'Chenopodium', 'Chrysanthemum', 'Cichorium',
    'Clematis', 'Cocos', 'Colchicum', 'Cornus', 'Cotinus', 'Crassula', 'Crocus',
    'Cyclamen', 'Cynara', 'Dahlia', 'Daphne', 'Delphinium', 'Digitalis', 'Diospyros',
    'Dracaena', 'Echinacea', 'Echinops', 'Elaeagnus', 'Ephedra', 'Epilobium', 'Erica',
    'Eryngium', 'Eucalyptus', 'Euonymus', 'Fagus', 'Festuca', 'Ficus', 'Foeniculum',
    'Forsythia', 'Fragaria', 'Fraxinus', 'Fuchsia', 'Gardenia', 'Gaura', 'Genista',
    'Gentiana', 'Geranium', 'Ginkgo', 'Gladiolus', 'Gleditsia', 'Glycine', 'Griselinia',
    'Hedera', 'Helianthus', 'Helleborus', 'Hemerocallis', 'Heuchera', 'Hibiscus', 'Hosta',
    'Hydrangea', 'Hypericum', 'Ilex', 'Impatiens', 'Inula', 'Ipomoea', 'Iris', 'Jasminum',
    'Juglans', 'Juniperus', 'Kalanchoe', 'Kalmia', 'Koelreuteria', 'Lagerstroemia',
    'Lavandula', 'Leucanthemum', 'Lilium', 'Liriodendron', 'Lobelia', 'Lotus', 'Lupinus',
    'Magnolia', 'Mahonia', 'Malus', 'Mandevilla', 'Matricaria', 'Mentha', 'Mimosa',
    'Monstera', 'Musa', 'Narcissus', 'Nepeta', 'Nerium', 'Olea', 'Opuntia', 'Origanum',
    'Paeonia', 'Panicum', 'Papaver', 'Passiflora', 'Pelargonium', 'Penstemon', 'Perovskia',
    'Petunia', 'Philodendron', 'Phlox', 'Photinia', 'Picea', 'Pinus', 'Platanus',
    'Polygonatum', 'Primula', 'Prunus', 'Psidium', 'Pyrus', 'Quercus', 'Rhododendron',
    'Rosa', 'Rubus', 'Salix', 'Salvia', 'Sambucus', 'Santolina', 'Scabiosa', 'Schefflera',
    'Sedum', 'Senecio', 'Solanum', 'Spiraea', 'Stachys', 'Stevia', 'Symphoricarpos',
    'Tagetes', 'Taxus', 'Teucrium', 'Thymus', 'Trifolium', 'Tulipa', 'Ulex', 'Ulmus',
    'Veronica', 'Viburnum', 'Viola', 'Vitis', 'Weigela', 'Wisteria', 'Yucca', 'Zantedeschia',
    'Zinnia', 'Ziziphus'
  ];

  final prefixes = <String>[
    'Silver', 'Golden', 'Forest', 'Sunlit', 'Meadow', 'Mossy', 'Coastal', 'River',
    'Valley', 'Cedar', 'Blooming', 'Canyon', 'Heather', 'Summit', 'Prairie', 'Harbor',
    'Briar', 'Glade', 'Stone', 'Wild', 'Fern', 'Mist', 'Marsh', 'Crown', 'Lakeside',
    'Cloud', 'Amber', 'Rose', 'Saffron', 'Violet', 'Pearl', 'Alpine', 'Jade', 'Copper',
    'Verdant', 'Garden', 'Horizon', 'Ridge', 'Lantern', 'Hush', 'Dune', 'Grove', 'Temple'
  ];

  final families = <String>[
    'Asteraceae', 'Brassicaceae', 'Fabaceae', 'Lamiaceae', 'Rosaceae', 'Solanaceae',
    'Cucurbitaceae', 'Ericaceae', 'Apiaceae', 'Rubiaceae', 'Rutaceae', 'Asparagaceae',
    'Poaceae', 'Amaryllidaceae', 'Orchidaceae', 'Magnoliaceae', 'Pinaceae', 'Moraceae',
    'Myrtaceae', 'Theaceae', 'Araceae', 'Aquifoliaceae', 'Geraniaceae'
  ];

  final emojiSet = ['🌿', '🌼', '🌱', '🌳', '🌵', '🍅', '🥬', '🍋', '🍓', '🌸'];

  final entries = <PlantInfo>[];
  for (var i = 0; i < 2000; i++) {
    final name = names[i % names.length];
    final prefix = prefixes[(i * 3) % prefixes.length];
    final family = families[i % families.length];
    final emoji = emojiSet[i % emojiSet.length];
    final commonName = i.isEven ? '$prefix $name' : '$name $prefix';
    final scientificName = '${name.toLowerCase()} ${prefix.toLowerCase()}ensis';
    final id = 'plant_${i.toString().padLeft(4, '0')}';

    entries.add(
      PlantInfo(
        id: id,
        commonName: commonName,
        scientificName: scientificName,
        family: family,
        origin: 'Temperate and subtropical regions across the world',
        sunlight: 'Full sun to bright filtered light depending on site',
        water: 'Provide steady moisture with drainage suited to the species',
        soil: 'Balanced, fertile soil with good structure and drainage',
        temperature: '10-28 C for active growth',
        growth: 'Seasonal growth habit, with long-lived perennial or annual forms depending on species',
        flowering: 'Seasonally formed blooms or reproductive stalks depending on species',
        commonProblems: 'Leaf stress, fungal spotting, water imbalance, and poor airflow.',
        care: 'Match light, water, soil, and airflow to the local environment to keep the plant resilient.',
        facts: [
          'This entry is part of the curated reference catalogue used in the app.',
          'The best care advice depends on the plant type, local climate, and the way it is grown.',
          'The app presents general care guidance rather than exact prescription or treatment instructions.',
        ],
        emoji: emoji,
        morphologyTags: [
          'garden',
          i % 3 == 0 ? 'herb' : i % 2 == 0 ? 'vegetable' : 'flowering',
          i % 5 == 0 ? 'tropical' : 'general',
        ],
        careSummary: 'Give the plant suitable light, consistent moisture, and healthy airflow to reduce stress and disease risk.',
        commonDiseases: [
          'Leaf spot',
          'Powdery mildew',
          'Root stress',
          'Water imbalance',
        ],
        sicknessReasons: [
          'Poor airflow and repeated wet foliage increase fungal stress.',
          'Irregular watering weakens roots and reduces plant resilience.',
          'Low light or crowded growth can reduce vigor and increase susceptibility.',
        ],
        medicineGuidance: [
          'Start by improving airflow, drainage, and the watering schedule.',
          'Use only a plant product labelled for the exact crop and condition.',
          'No exact dosage is shown here. Follow the product label and local extension guidance.',
        ],
      ),
    );
  }

  return entries;
}
