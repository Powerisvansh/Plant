import '../models/plant_health_models.dart';

class PlantHealthContent {
  PlantHealthContent._();

  static const List<String> emergencySteps = [
    'Isolate the affected plant if pests or a contagious disease are possible.',
    'Check both leaf surfaces, stems, soil and roots before choosing a treatment.',
    'Photograph the whole plant and affected tissue in good light for later comparison.',
    'Remove only tissue that is clearly dead, rotting or heavily infested.',
    'Correct drainage, watering, crowding and other environmental stress first.',
    'Do not spray an unidentified problem; the wrong product can damage plants and spread pests.',
    'Contact a plant clinic or extension service when symptoms are severe, spreading or uncertain.',
  ];

  static const List<String> medicineSafety = [
    'Read the entire product label before use. The label identifies approved plants, problems, directions, protective equipment, re-entry and harvest intervals.',
    'Use only a product registered for the exact crop and problem in your country or region. An ornamental label does not automatically cover vegetables, fruit or herbs.',
    'Never diagnose from one symptom alone. Fungal spots, bacterial spots, nutrient problems and physical injury can look alike.',
    'When the label or local professional guidance permits a small trial, test on one plant or a small area and wait long enough to observe damage.',
    'Do not mix products unless the label specifically permits it. Some combinations can cause fire, crop injury or dangerous fumes.',
    'Do not use kitchen chemicals, concentrated household cleaners or improvised ratios as plant medicine.',
    'Keep children, pets, food, water and animals away during handling and follow all label re-entry and harvest restrictions.',
    'Avoid spraying open flowers when pollinators are active and prevent drift into drains, ponds and neighbouring plants.',
    'Store products in their original container, lock them away and dispose of waste as the label and local rules require.',
  ];

  static const List<PlantHealthEntry> all = [
    PlantHealthEntry(
      id: 'powdery-mildew',
      title: 'Powdery mildew',
      scientificName: 'Erysiphe and Podosphaera species',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.prompt,
      summary: 'A widespread fungal disease that forms pale, dusty or felt-like growth on leaves, shoots, buds and sometimes fruit.',
      symptoms: [
        'White or grey powdery patches that spread across the leaf surface',
        'Yellowing, curling, cupping or distorted young growth',
        'Reduced flowering, crop quality or plant vigour when infection is heavy',
        'White growth may be sparse on some hosts even when damage is present',
      ],
      causes: [
        'A host-specific fungal pathogen',
        'Crowding, poor air movement and excessive shade',
        'Drought-stressed plants and moderate temperatures with humid air',
      ],
      lookAlikes: [
        'Natural pale variegation or dust on the leaf surface',
        'Downy mildew, which usually has growth underneath and angular lesions above',
        'Mineral deposits left by hard water on a pot rim or foliage',
      ],
      firstAid: [
        'Separate affected plants to reduce pressure and inspect nearby plants.',
        'Remove the most heavily infected leaves and fallen debris with clean tools.',
        'Improve spacing and airflow, and water the soil rather than wetting foliage.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Reduce conditions that favour mildew',
          steps: [
            'Place plants with more space and avoid a permanently crowded canopy.',
            'Match watering to the species and allow the recommended surface drying.',
            'Avoid excess nitrogen that creates lush, especially susceptible growth.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Protect new growth if needed',
          steps: [
            'Choose a fungicide labelled for powdery mildew and the exact plant.',
            'Follow the label, repeat interval, crop restrictions and harvest interval exactly.',
            'Fungicides do not restore damaged tissue; judge success by healthy new growth.',
          ],
        ),
      ],
      prevention: [
        'Choose resistant varieties where available.',
        'Keep foliage and root zones at species-appropriate moisture levels.',
        'Remove infected debris and disinfect reusable pots and tools between affected plants.',
      ],
      escalation: [
        'Infection is spreading rapidly despite sanitation and airflow changes.',
        'A valuable food crop, greenhouse crop or dense planting has extensive mildew.',
        'A diagnosis is uncertain because no powdery growth is visible.',
      ],
      safetyNote: 'Fungicides can burn foliage and do not cure existing damage. Do not recommend an active ingredient or product unless a local label confirms it is registered and suitable for the plant.',
      references: [
        'RHS Advice: Powdery mildews',
        'University extension plant pathology guidance',
        'Local plant diagnostic clinic or certified crop adviser',
      ],
      relatedIds: ['downy-mildew', 'fungal-leaf-spot', 'rust', 'aphids'],
    ),
    PlantHealthEntry(
      id: 'downy-mildew',
      title: 'Downy mildew',
      scientificName: 'Peronospora, Plasmopara and related oomycetes',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.prompt,
      summary: 'A group of fungus-like pathogens favoured by cool, wet conditions and often seen first as angular yellow patches.',
      symptoms: [
        'Angular yellow, green or purple patches often bounded by leaf veins',
        'Fine white, grey or purple growth on the underside beneath the patches',
        'Leaf curling, browning, premature drop and stunted growth in severe cases',
        'Darkened flower stalks, buds or crop heads on some hosts',
      ],
      causes: [
        'Host-specific oomycete pathogens spread by air, water splash and contaminated material',
        'Prolonged leaf wetness, cool temperatures and high humidity',
        'Dense growth, overhead watering and infected soil or seed in some crops',
      ],
      lookAlikes: [
        'Powdery mildew, which usually grows more visibly on upper surfaces',
        'Bacterial leaf spot and nutrient or environmental yellowing',
        'Insect damage between veins on young foliage',
      ],
      firstAid: [
        'Isolate the plant and remove fallen leaves and the worst affected tissue.',
        'Keep leaves dry: water at soil level early enough for accidental splashes to dry.',
        'Increase spacing and ventilation without creating a cold, damp draft around the plant.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.sanitation,
          title: 'Limit spread',
          steps: [
            'Bag or dispose of removed material according to local waste guidance; do not compost visibly diseased tissue.',
            'Clean tools and hands after working with affected plants.',
            'For annuals and vegetables, follow local crop rotation and resistant-variety advice.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use a crop-specific preventive option',
          steps: [
            'Some regions have registered products for particular downy mildews; few are broadly available to home growers.',
            'Use only if the plant, disease, application and harvest interval are listed on the label.',
            'Treatment works best early and generally protects uninfected tissue rather than repairing lesions.',
          ],
        ),
      ],
      prevention: [
        'Use resistant cultivars and certified disease-free plants where possible.',
        'Avoid overhead irrigation and improve air movement around the canopy.',
        'Remove infected crop residues and do not save seed from severely affected plants.',
      ],
      escalation: [
        'A whole crop is affected quickly during cool, wet weather.',
        'The underside has no recognisable growth and the diagnosis is uncertain.',
        'A protected crop is nearing harvest and a treatment decision is needed.',
      ],
      safetyNote: 'Do not apply a general fungicide by guesswork. Many products do not control downy mildews, and some registered products are not approved for edible crops.',
      references: [
        'RHS Advice: Downy mildews',
        'University extension plant pathology guidance',
        'Local agricultural extension or plant diagnostic service',
      ],
      relatedIds: [
        'powdery-mildew',
        'bacterial-leaf-spot',
        'fungal-leaf-spot',
        'overwatering-root-stress',
      ],
    ),
    PlantHealthEntry(
      id: 'fungal-leaf-spot',
      title: 'Fungal leaf spots',
      scientificName: 'Many host-specific fungi',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Many fungal diseases create round or irregular dead spots. The exact pathogen and plant host often need to be identified for reliable control.',
      symptoms: [
        'Brown, purple or black spots, sometimes with yellow halos',
        'Spots that enlarge, merge and cause leaf drop',
        'Dark fruiting dots, concentric rings or a dry paper-like centre on some diseases',
        'Stem, flower or fruit lesions when the disease has spread beyond leaves',
      ],
      causes: [
        'A diverse group of fungi, often favoured by wet foliage and fallen infected debris',
        'Splash from watering, rain or contaminated hands, pots, soil and tools',
        'Crowding, poor airflow and plants already stressed by roots, light or nutrition',
      ],
      lookAlikes: [
        'Bacterial leaf spot, which can have water-soaked margins or angular lesions',
        'Chemical or fertilizer burn and physical sun or cold injury',
        'Insect feeding damage and naturally variegated foliage',
      ],
      firstAid: [
        'Remove and discard the worst affected leaves and all fallen debris.',
        'Water at soil level, preferably in the morning, and do not handle wet plants.',
        'Keep tools clean and keep the affected plant separate while the pattern develops.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Stop prolonged leaf wetness',
          steps: [
            'Improve spacing, pruning and air movement without removing so much tissue that the plant is weakened.',
            'Adjust irrigation so foliage dries during the day.',
            'Check that the pot drains freely and that roots are not continuously waterlogged.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use a labelled protectant when justified',
          steps: [
            'Identify the plant and likely disease first; leaf spots are not one treatable disease.',
            'Select a fungicide labelled for that host and problem, then follow the complete label.',
            'Rotate any labelled mode-of-action group rather than repeatedly using one active ingredient.',
          ],
        ),
      ],
      prevention: [
        'Remove infected leaves in early autumn so spores do not overwinter.',
        'Use mulch to reduce soil splash and clean containers before reuse.',
        'Choose species and varieties suited to the available light and climate.',
      ],
      escalation: [
        'Spots occur on stems, crowns or fruits and are rapidly enlarging.',
        'A new or valuable plant is affected, or several species show the same spots at once.',
        'A sample is needed to separate fungal, bacterial and physical causes.',
      ],
      safetyNote: 'A copper or other product that works on one disease can injure sensitive plants. Confirm the crop, plant and disease on the label and avoid spraying in extreme heat.',
      references: [
        'University extension leaf-spot fact sheets',
        'RHS Advice: plant problems and disease prevention',
        'Local plant diagnostic clinic',
      ],
      relatedIds: [
        'bacterial-leaf-spot',
        'anthracnose',
        'rust',
        'leaf-scorch-edema',
      ],
    ),
    PlantHealthEntry(
      id: 'rust',
      title: 'Rust diseases',
      scientificName: 'Fungi in the order Pucciniales',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Host-specific fungal diseases that usually make orange, yellow or brown pustules that release powdery spores.',
      symptoms: [
        'Yellow or orange spots above, with matching powdery pustules below',
        'Raised, dusty pustules on leaves, stems or fruit',
        'Premature leaf yellowing and drop when infection is heavy',
        'Some rusts cause distorted shoots or pale, swollen growth',
      ],
      causes: [
        'A rust fungus adapted to a particular host, sometimes needing a second host',
        'Airborne spores released from infected leaves and nearby alternate hosts',
        'Wet spring weather, leaf wetness and moderate temperatures',
      ],
      lookAlikes: [
        'Spider-mite feeding, which can create fine stippling and webbing',
        'Scale insects or natural orange markings on some foliage',
        'Bacterial or other fungal leaf spots',
      ],
      firstAid: [
        'Pick or remove heavily infected leaves before the pustules release more spores.',
        'Collect fallen material and keep it away from susceptible plants.',
        'Inspect neighbouring hosts, including alternative host plants when known.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.sanitation,
          title: 'Reduce inoculum',
          steps: [
            'Remove infected material promptly and clean up before spores spread.',
            'In gardens, remove volunteer hosts only where this does not harm the landscape.',
            'Do not save infected seed, bulbs or cuttings for propagation.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Protect uninfected growth',
          steps: [
            'Use only a product specifically labelled for rust on the identified crop or ornamental.',
            'Apply at the labelled growth stage and repeat only as directed.',
            'Record mode-of-action groups when a repeat treatment is needed to manage resistance.',
          ],
        ),
      ],
      prevention: [
        'Remove rust-prone material in autumn where local guidance recommends it.',
        'Space plants for airflow and avoid overhead watering.',
        'Choose resistant cultivars and remove known alternate hosts when practical.',
      ],
      escalation: [
        'Orange growth is present on a food crop close to harvest.',
        'The pustules are on stems or fruit rather than leaves.',
        'A large planting is affected and the host-specific disease needs confirmation.',
      ],
      safetyNote: 'Do not eat a crop unless the product label permits that use and its pre-harvest interval has been followed. "Organic" does not mean risk-free.',
      references: [
        'RHS Advice: rust diseases',
        'University extension rust fact sheets',
        'Local certified crop adviser or plant clinic',
      ],
      relatedIds: [
        'fungal-leaf-spot',
        'spider-mites',
        'powdery-mildew',
        'anthracnose',
      ],
    ),
    PlantHealthEntry(
      id: 'grey-mould',
      title: 'Grey mould and blossom blight',
      scientificName: 'Botrytis cinerea and related fungi',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.urgent,
      summary: 'A fungal disease that colonises dying tissue and can quickly turn flowers, fruit and soft growth into brown-grey rot.',
      symptoms: [
        'Water-soaked spots on flowers, fruit, leaves or soft stems',
        'Grey, fuzzy or dusty growth on dead or dying tissue',
        'Rapid soft collapse and shrivelling during cool, humid weather',
        'Stems or buds that wilt despite moist soil',
      ],
      causes: [
        'Botrytis fungi that attack weakened or dead tissue and can spread to healthy tissue',
        'Cool, humid, crowded conditions and poor air movement',
        'Senescent flowers, damaged tissue, overripe fruit and dead leaves left on the plant',
      ],
      lookAlikes: [
        'Bacterial soft rot, which is wetter and may smell strongly',
        'Sunscald, cold injury or simple senescence without fuzzy growth',
        'Fungal fruit rots caused by other host-specific pathogens',
      ],
      firstAid: [
        'Remove infected flowers, fruit, leaves and stems immediately; do not shake spores indoors.',
        'Bag the material and clean the area, hands, stakes and tools.',
        'Reduce humidity, remove crowded growth and keep water away from flowers and fruit.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Remove infection sources',
          steps: [
            'Cut out tissue generously enough to remove the brown transition between dead and healthy tissue.',
            'Remove old blossoms and overripe fruit that will not be harvested.',
            'Discard produce that is soft, leaking or visibly rotting; do not eat plant parts affected by rot.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use protectants only for a continuing risk',
          steps: [
            'Select a Botrytis-registered product labelled for the crop and setting.',
            'Most products are preventive; repeatedly removing infected material remains essential.',
            'Follow label intervals, resistance-management directions and harvest restrictions.',
          ],
        ),
      ],
      prevention: [
        'Space plants and prune dense interiors without stripping too much healthy foliage.',
        'Water at soil level in the morning and avoid wet flowers overnight.',
        'Keep fallen petals and dead tissue out of the canopy and harvest crops promptly.',
      ],
      escalation: [
        'Soft rot is spreading quickly through a greenhouse, crop or stored produce.',
        'Cane or stem lesions girdle the plant or reach the crown.',
        'The growth is not clearly fungal and a sample is needed urgently.',
      ],
      safetyNote: 'Never eat produce from a crop treated with an unlabelled product. Follow the label for protective equipment, re-entry, harvest interval and storage of harvested food crops.',
      references: [
        'RHS Advice: grey mould and botrytis',
        'University extension postharvest and greenhouse guidance',
        'Local plant diagnostic clinic',
      ],
      relatedIds: [
        'bacterial-soft-rot',
        'anthracnose',
        'downy-mildew',
        'powdery-mildew',
      ],
    ),
    PlantHealthEntry(
      id: 'sooty-mould',
      title: 'Sooty mould',
      scientificName: 'Capnodium and other surface-growing fungi',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.prompt,
      summary: 'A black coating that grows on sticky honeydew. It usually does not infect the leaf itself; the sap-feeding insects responsible are the main problem.',
      symptoms: [
        'A black, soot-like film on leaves, stems or fruit',
        'Sticky honeydew on the surface, sometimes before the black film appears',
        'Reduced photosynthesis when a heavy coating blocks light',
        'A nearby population of aphids, whiteflies, scale, mealybugs or leafhoppers',
      ],
      causes: [
        'Sap-feeding insects excrete sugary honeydew as they feed',
        'Fungi use the honeydew as a food source and spread by spores',
        'Crowded foliage and slow-drying surfaces allow the black coating to develop',
      ],
      lookAlikes: [
        'Dirt, dust, soot, algae or mineral deposits that wipe from the surface',
        'A true leaf-spot disease that enters tissue rather than growing on honeydew',
        'Natural dark markings on some plant surfaces',
      ],
      firstAid: [
        'Check leaf undersides and stems for sap feeders and identify them before cleaning the surface.',
        'Wipe or gently rinse the black film without soaking the plant or disturbing insects unnecessarily.',
        'Reduce sticky honeydew by controlling the insect source rather than spraying the mould alone.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Clean the coating after the insects are controlled',
          steps: [
            'Remove heavy film with a damp cloth or a gentle rinse when the plant tolerates it.',
            'Do not assume a fungicide will remove sooty mould while honeydew keeps arriving.',
            'Monitor new growth for fresh honeydew to confirm the source is controlled.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.biological,
          title: 'Manage the sap-feeding pest',
          steps: [
            'Choose a physical or biological control labelled or recommended for the identified insect.',
            'Conserve lady beetles, lacewings and parasitoid wasps by avoiding unnecessary broad-spectrum sprays.',
            'For a recurring protected crop, use sticky-card monitoring and an integrated pest plan.',
          ],
        ),
      ],
      prevention: [
        'Inspect new plants and monitor tender growth for aphids, whiteflies and scale.',
        'Avoid excessive nitrogen that encourages rapid, tender growth and large pest populations.',
        'Keep foliage reasonably clean and dry without removing beneficial insect habitat unnecessarily.',
      ],
      escalation: [
        'Honeydew continues despite pest control or no insects can be found.',
        'A large protected crop or valuable collection is covered rapidly.',
        'Black areas are embedded in dead tissue rather than sitting on the surface.',
      ],
      safetyNote: 'Sooty mould itself usually does not need a fungicide. Identify the sap feeder and use only a product labelled for that pest and plant.',
      references: [
        'University extension sooty-mould and honeydew guidance',
        'RHS Advice: sooty mould',
        'Local extension or greenhouse pest adviser',
      ],
      relatedIds: [
        'aphids',
        'whiteflies',
        'scale-mealybugs',
        'fungal-leaf-spot',
      ],
    ),
    PlantHealthEntry(
      id: 'anthracnose',
      title: 'Anthracnose and shoot blight',
      scientificName: 'Colletotrichum and related fungi',
      category: PlantProblemCategory.fungal,
      urgency: PlantProblemUrgency.prompt,
      summary: 'A group of fungal diseases that cause dark leaf, stem, twig and fruit lesions, often becoming conspicuous after cool, wet weather.',
      symptoms: [
        'Sunken brown, purple or black lesions on leaves, stems or fruit',
        'Twig or shoot tips that wilt, die back or break at a dark lesion',
        'Sunken circular fruit spots that may develop pink, orange or dark spores',
        'Small dead spots that enlarge and merge during wet weather',
      ],
      causes: [
        'Host-specific or host-range fungal pathogens',
        'Rain or irrigation splash carrying spores from soil, mulch and infected debris',
        'Cool, wet spring conditions, overhead irrigation and overhead plant cover',
      ],
      lookAlikes: [
        'Bacterial canker or bacterial leaf spot',
        'Sunburn, frost or mechanical stem damage',
        'Fungal leaf spots and cankers caused by other organisms',
      ],
      firstAid: [
        'Remove infected twigs or badly affected tissue during dry weather and disinfect tools.',
        'Collect all fallen leaves, fruit and dead flower material.',
        'Keep irrigation water and hands away from wounds and avoid working among wet plants.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Reduce leaf and fruit wetness',
          steps: [
            'Open dense canopies and prevent branches from rubbing together.',
            'Use mulch and soil-level irrigation to prevent mud from splashing onto lower tissues.',
            'Avoid overhead cover systems that keep foliage wet for long periods.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Target a confirmed disease',
          steps: [
            'Use a fungicide labelled for anthracnose on the exact host and disease complex.',
            'Begin within the label window and rotate labelled mode-of-action groups.',
            'Do not expect damaged fruit, stems or leaves to return to a marketable state.',
          ],
        ),
      ],
      prevention: [
        'Prune for airflow and disinfect tools between trees or shrubs.',
        'Use resistant cultivars and remove heavily infected young plants from nurseries.',
        'Clear crop debris after harvest and rotate susceptible annual crops where advised.',
      ],
      escalation: [
        'Disease is entering the trunk, crown or main branches of a valuable tree.',
        'Cankers girdle shoots or a whole planting declines despite sanitation.',
        'A protected crop develops extensive fruit lesions and needs a confirmed diagnosis.',
      ],
      safetyNote: 'Remove fallen fruit from home gardens and compost areas. Do not place potentially diseased material where children, livestock or wildlife can access it.',
      references: [
        'University extension anthracnose fact sheets',
        'RHS Advice: preventing plant disease',
        'Local arborist, plant clinic or certified crop adviser',
      ],
      relatedIds: [
        'fungal-leaf-spot',
        'bacterial-leaf-spot',
        'grey-mould',
        'rust',
      ],
    ),
    PlantHealthEntry(
      id: 'bacterial-leaf-spot',
      title: 'Bacterial leaf spot and blight',
      scientificName: 'Xanthomonas, Pseudomonas and related bacteria',
      category: PlantProblemCategory.bacterial,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Bacterial diseases cause water-soaked, angular or dead lesions and may spread quickly through wet plants, tools and splashing water.',
      symptoms: [
        'Small water-soaked spots that turn brown, black or purple',
        'Angular lesions bounded by veins, especially on younger leaves',
        'Yellow halos, shot holes after dead tissue falls out, or leaf-edge scorch',
        'Blackened flower buds, fruit spots or stem lesions on some hosts',
      ],
      causes: [
        'Host-specific bacteria spread by splashing rain, irrigation, tools, hands and infected stock',
        'Warm, wet conditions and injury that allow bacteria to enter tissue',
        'Seed, transplants or infected debris that carry bacteria into a planting',
      ],
      lookAlikes: [
        'Fungal leaf spots, anthracnose and chemical injury',
        'Insect feeding that produces small holes or torn tissue',
        'Sunscorch, frost and salt accumulation',
      ],
      firstAid: [
        'Isolate the plant and stop overhead watering or handling wet foliage.',
        'Remove severely affected leaves and crop debris; disinfect tools after each cut.',
        'Do not work among plants when leaves are wet, and wash hands between crops.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.sanitation,
          title: 'Limit bacterial spread',
          steps: [
            'Remove infected tissue early and dispose of it in sealed or contained waste.',
            'Clean containers, benches and tools; do not save affected seed or tubers.',
            'For gardens, rotate susceptible vegetable or ornamental crops according to local guidance.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Discuss preventive copper options',
          steps: [
            'Copper products may suppress some bacterial diseases but do not cure dead tissue.',
            'Confirm the host, disease, crop and timing on a local label and account for phytotoxicity.',
            'Avoid routine copper use because it can accumulate in soil and harm organisms.',
          ],
        ),
      ],
      prevention: [
        'Buy certified disease-free seed and transplants.',
        'Use drip or soil-level irrigation and avoid working in wet plants.',
        'Remove crop debris and rotate susceptible hosts beyond the local pathogen survival period.',
      ],
      escalation: [
        'A rapidly spreading outbreak affects many plants at once.',
        'A food crop, nursery stock or valuable perennial has extensive lesions.',
        'A sample or laboratory test is needed before any product decision.',
      ],
      safetyNote: 'Do not eat fruit affected by bacterial leaf spot. Bacterial diseases are often not curable at home; product claims vary by country, and preventive copper can injure plants or contaminate soil if overused.',
      references: [
        'University extension bacterial disease fact sheets',
        'Local plant diagnostic laboratory guidance',
        'RHS Advice: preventing pest and disease problems',
      ],
      relatedIds: [
        'bacterial-soft-rot',
        'fungal-leaf-spot',
        'anthracnose',
        'downy-mildew',
      ],
    ),
    PlantHealthEntry(
      id: 'bacterial-soft-rot',
      title: 'Bacterial soft rot',
      scientificName: 'Pectobacterium and Dickeya species',
      category: PlantProblemCategory.bacterial,
      urgency: PlantProblemUrgency.urgent,
      summary: 'A rapidly progressing bacterial rot that turns fleshy tissues wet, slimy or soft and can spread through stored produce.',
      symptoms: [
        'Soft, watery or mushy tissue with a sharp transition from healthy tissue',
        'A wet or slimy surface and sometimes an unpleasant smell',
        'Rapid collapse of a leaf, stem, fruit head, tuber or root',
        'Brown bacterial ooze under pressure on some tissues',
      ],
      causes: [
        'Soft-rot bacteria entering through wounds and multiplying in warm, wet tissue',
        'Overwatering, waterlogging, poor air movement and damaged produce',
        'Contaminated knives, harvest containers, soil and contact between rotting plants',
      ],
      lookAlikes: [
        'Grey mould, which can develop fuzzy grey growth',
        'Fungal root or crown rots and frost injury',
        'Normal ripening or bruising without a wet, foul progression',
      ],
      firstAid: [
        'Move the affected plant or produce out of the growing area immediately.',
        'Do not squeeze, shake or compost rotting material; keep it away from other plants.',
        'Remove and discard soft tissue with clean tools, then clean and dry the container area.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Stop the rot',
          steps: [
            'Discard rotted plant parts and produce; they cannot be made sound by trimming or a spray.',
            'Harvest at the correct maturity, keep produce cool and prevent bruising.',
            'Clean harvest tools and containers and keep crops off wet soil.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.professionalCare,
          title: 'Investigate recurring losses',
          steps: [
            'Contact an extension service, plant clinic or crop adviser for recurring soft rot.',
            'A sample may be needed to distinguish bacteria from fungi and identify the entry route.',
            'Do not use antibiotics or household disinfectants preventively without professional and legal direction.',
          ],
        ),
      ],
      prevention: [
        'Improve drainage and harvest handling; avoid injuries during cultivation.',
        'Store only sound, dry produce in clean, cool, ventilated conditions.',
        'Rotate susceptible crops and remove infected residues where local guidance recommends it.',
      ],
      escalation: [
        'The disease is moving through stored food, seedlings or a field crop.',
        'The plant is a valuable perennial and the rot is near the crown or main stem.',
        'There is a foul smell, leaking sap or a need to determine whether food produce is safe.',
      ],
      safetyNote: 'Do not eat plant parts affected by rot. Clean hands and surfaces after handling, and ask a qualified food-safety professional about questionable produce.',
      references: [
        'University extension bacterial soft-rot fact sheets',
        'Local food-crop extension and plant diagnostic services',
        'RHS Advice: preventing disease problems',
      ],
      relatedIds: [
        'grey-mould',
        'root-crown-rot',
        'bacterial-wilt',
        'anthracnose',
      ],
    ),
    PlantHealthEntry(
      id: 'bacterial-wilt',
      title: 'Bacterial wilt',
      scientificName: 'Ralstonia, Xanthomonas, Erwinia and related bacteria',
      category: PlantProblemCategory.bacterial,
      urgency: PlantProblemUrgency.urgent,
      summary: 'Bacteria can block plant vessels, causing rapid wilting and yellowing even while soil remains wet. There is usually no reliable home cure.',
      symptoms: [
        'Sudden wilting that does not improve after the soil is watered',
        'Yellowing or bronze foliage with vascular discoloration',
        'Stem or root tissue that shows a dark ring when cut',
        'Bacterial slime in some plants and rapid death in susceptible crops',
      ],
      causes: [
        'Soil-borne, root-feeding or vascular bacteria entering through roots or wounds',
        'Infected seed, tubers, cuttings, plant debris, tools and soil movement',
        'Warm conditions and soil or water that drains very poorly',
      ],
      lookAlikes: [
        'Root rot from water moulds or ordinary root damage',
        'Fungal vascular wilts, stem borers and severe nutrient or water stress',
        'Physical root restriction, compaction or accidental herbicide exposure',
      ],
      firstAid: [
        'Stop watering into a wet root zone and do not move potentially contaminated soil.',
        'Isolate the plant; avoid taking cuttings or saving seed from it.',
        'Disinfect tools after contact and wash hands, footwear and equipment before handling healthy plants.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Contain the affected area',
          steps: [
            'If a regulated disease is confirmed or local authorities direct removal, remove the affected plant, roots and nearby volunteer growth as directed; otherwise seek diagnostic advice before destroying a valuable specimen.',
            'Contain and dispose of material as directed by local agricultural or waste rules.',
            'Do not compost a suspected regulated pathogen or move affected soil off-site.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.professionalCare,
          title: 'Confirm before replanting',
          steps: [
            'Ask a plant clinic, extension service or regulatory authority to test the sample.',
            'Use clean planting stock and follow any official rotation, disinfection or quarantine direction.',
            'There is no dependable curative pesticide treatment for a diseased plant.',
          ],
        ),
      ],
      prevention: [
        'Start with certified disease-free plants, seed and tubers.',
        'Improve drainage and avoid injuring roots during cultivation.',
        'Clean tools, boots and machinery and control soil movement between sites.',
      ],
      escalation: [
        'Several rapidly wilting plants occur in a patch or crop.',
        'A regulated disease is suspected in a region where movement of plants or soil is restricted.',
        'A sample is needed to distinguish bacterial wilt from fungal wilt and root injury.',
      ],
      safetyNote: 'There is no safe household spray that reliably cures bacterial wilt. Follow official quarantine and disposal directions and avoid sharing affected plants or soil.',
      references: [
        'University extension bacterial-wilt fact sheets',
        'Local plant diagnostic laboratory and agricultural authority',
        'Regional plant-health quarantine guidance',
      ],
      relatedIds: [
        'root-crown-rot',
        'overwatering-root-stress',
        'mosaic-virus',
        'fungal-leaf-spot',
      ],
    ),
    PlantHealthEntry(
      id: 'mosaic-virus',
      title: 'Mosaic and other plant viruses',
      scientificName:
          'Many viruses, including mosaic, mottle and yellow viruses',
      category: PlantProblemCategory.viral,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Viruses can cause persistent mottling, distortion and stunting. Infected plants cannot be cured with fungicide or antibiotic sprays.',
      symptoms: [
        'Irregular light and dark green or yellow mosaic patterns on leaves',
        'Rings, lines, mottling or vein clearing that persists as new leaves grow',
        'Narrow, curled, puckered or distorted leaves',
        'Stunted growth, poor fruit set or streaking and internal browning in some crops',
      ],
      causes: [
        'A plant virus introduced in infected stock, seed, sap, tools or plant contact',
        'Sap-feeding insects such as aphids, whiteflies or thrips',
        'Mechanical transmission during pruning, handling or propagation',
      ],
      lookAlikes: [
        'Downy mildew, nutrient deficiency, herbicide injury and mite feeding',
        'Natural leaf variegation and seasonal colour change',
        'Broad mite, thrips or aphid damage that distorts new growth',
      ],
      firstAid: [
        'Isolate the plant and stop moving plant material between it and healthy plants.',
        'Do not take cuttings or seeds from a plant with persistent unexplained mosaic symptoms.',
        'Clean hands and tools after contact, then inspect for the insect vectors named for the local virus.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Remove confirmed infection sources',
          steps: [
            'Dispose of a confirmed or strongly suspected infected plant rather than treating it in place.',
            'Remove nearby weeds that may harbour viruses or vectors when practical.',
            'Clean propagation tools and avoid saving seed from symptomatic plants.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.biological,
          title: 'Manage vectors and transmission',
          steps: [
            'Correctly identify and manage the local vector species using cultural or labelled controls.',
            'Use insect netting or exclusion where suitable and avoid overusing broad-spectrum insecticides that kill natural enemies.',
            'Control nearby infected crops and use resistant or certified clean stock when available.',
          ],
        ),
      ],
      prevention: [
        'Buy certified disease-free plants and virus-tested seed or tubers.',
        'Control weeds and manage vectors without harming pollinators or beneficial insects.',
        'Disinfect tools between plants, especially during propagation and pruning.',
      ],
      escalation: [
        'Several plants show the same persistent mosaic or distortion pattern.',
        'A high-value crop, nursery or protected planting is affected.',
        'A laboratory test is needed before removing a large number of plants.',
      ],
      safetyNote: 'No over-the-counter plant spray cures a systemic virus. Removing plants can be emotional and expensive, so seek laboratory confirmation when the consequences are significant.',
      references: [
        'University extension plant-virus fact sheets',
        'RHS Advice: virus diseases in plants',
        'Local plant diagnostic laboratory',
      ],
      relatedIds: ['aphids', 'whiteflies', 'thrips', 'herbicide-injury'],
    ),
    PlantHealthEntry(
      id: 'aphids',
      title: 'Aphids',
      scientificName: 'Aphididae',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.routine,
      summary: 'Small sap-feeding insects that cluster on shoots, buds and undersides of leaves, often leaving sticky honeydew behind.',
      symptoms: [
        'Clusters of soft-bodied green, black, grey or translucent insects',
        'Curled or distorted new growth and yellowing with heavy feeding',
        'Sticky honeydew on leaves and black sooty mould growing on it',
        'Ants moving up and down stems or nearby soil',
      ],
      causes: [
        'Aphid females produce live young rapidly in warm conditions',
        'Ants may protect aphids from predators, especially outdoors',
        'Soft new growth and stressed or over-fertilised plants are often attractive',
      ],
      lookAlikes: [
        'Whiteflies, which flutter when disturbed and hold white wings',
        'Scale or mealybugs, which have a more fixed waxy or shell-like body',
        'Small leafhoppers and psyllids',
      ],
      firstAid: [
        'Inspect new shoots and leaf undersides; isolate an infested plant from valuable neighbours.',
        'Remove small colonies by hand and rinse the plant with a firm but non-damaging stream of water.',
        'Wipe sticky surfaces and monitor new growth daily for several days.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Handle small infestations directly',
          steps: [
            'Squash colonies, prune heavily infested tips or rinse aphids away.',
            'Avoid excess nitrogen that creates lush growth and review nearby ant activity.',
            'Do not discard infested shoots where they could contaminate clean plants or compost.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use a labelled soap, oil or insecticide if needed',
          steps: [
            'Identify the aphid and check the product label for the exact plant and setting.',
            'Insecticidal soap or horticultural oil usually requires direct contact and thorough leaf coverage.',
            'Test first, avoid hot sun and stressed plants, and repeat only as the label directs.',
          ],
        ),
      ],
      prevention: [
        'Inspect new plants and monitor tender growth regularly.',
        'Conserve lady beetles, lacewings, syrphid flies and other natural enemies.',
        'Control nearby broad-leaved weeds only when this will not disturb desirable habitat.',
      ],
      escalation: [
        'Aphids rapidly spread to many plants or a high-value crop is heavily infested.',
        'Honeydew and sooty mould are widespread, or a virus-vector species is present.',
        'Repeated labelled treatments are failing or harming beneficial insects.',
      ],
      safetyNote: 'Oils and soaps can burn foliage, especially in heat or drought. Keep all insecticides away from open flowers when pollinators are active and follow label harvest restrictions.',
      references: [
        'University extension integrated pest-management guidance',
        'RHS Advice: aphids',
        'Local extension service for region-specific vector species',
      ],
      relatedIds: [
        'sooty-mould',
        'whiteflies',
        'scale-mealybugs',
        'mosaic-virus',
      ],
    ),
    PlantHealthEntry(
      id: 'spider-mites',
      title: 'Spider mites',
      scientificName: 'Tetranychidae',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Tiny sap-feeding mites that thrive in warm, dusty conditions and may be present in very high numbers before damage is obvious.',
      symptoms: [
        'Fine pale stippling, speckles or bronzing across leaves',
        'Very fine webbing, especially on leaf undersides and new growth',
        'Moving red, yellow, brown, green or translucent dots under a hand lens',
        'Dull, dusty or prematurely dropping foliage in severe infestations',
      ],
      causes: [
        'Heat, low humidity, drought stress and dusty conditions can favour outbreaks',
        'Mites arrive on infested plants, clothing, tools or outdoor wind',
        'Broad-spectrum insecticides can remove predators and worsen some mite problems',
      ],
      lookAlikes: [
        'Thrips damage, leaf stippling from another cause and natural leaf texture',
        'Powdery mildew or fine dust on the leaf surface',
        'Shade, nutrient stress and chemical leaf injury',
      ],
      firstAid: [
        'Isolate the plant and inspect the underside of leaves with a hand lens or white paper test.',
        'Rinse leaves, especially undersides, and wipe away heavy webbing without crushing tender growth.',
        'Reduce dust and hot, dry conditions while monitoring the plant daily.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Reduce the population',
          steps: [
            'Repeat gentle water rinses at an interval that keeps leaves manageable for the plant.',
            'Remove badly damaged leaves and heavily webbed tips where loss will not stress the plant.',
            'Avoid routine broad-spectrum insecticides unless a local label specifically targets the problem.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.biological,
          title: 'Support natural predators',
          steps: [
            'Phytoseiid predatory mites can work in protected settings when the local climate and advice support their release.',
            'Avoid spraying plants that will harm predators and follow specialist release instructions.',
            'Improve conditions without creating persistent leaf wetness that favours other disease.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use a registered miticide for severe cases',
          steps: [
            'Confirm mites and choose a product labelled for the plant, setting and target mite.',
            'Follow the label exactly, including the undersides, interval, safety and harvest restrictions.',
            'When repeat treatment is permitted, rotate modes of action rather than only products or active ingredients, following the label and local resistance-management advice.',
          ],
        ),
      ],
      prevention: [
        'Quarantine and inspect new plants for several weeks before adding them to a collection.',
        'Keep plants adequately watered and remove dust without creating wet foliage overnight.',
        'Monitor warm, dry periods and avoid unnecessary broad-spectrum pest sprays.',
      ],
      escalation: [
        'Webbing or stippling is spreading across a collection rapidly.',
        'A crop or high-value plant has heavy damage and reliable predator timing is unavailable.',
        'Several labelled treatments fail, suggesting resistance or a misidentified pest.',
      ],
      safetyNote: 'Mites are not insects, so many insecticides do not control them. Do not combine miticides, oils or soaps unless the label allows it, and test stressed plants first.',
      references: [
        'University extension spider-mite management guides',
        'RHS Advice: glasshouse red spider mite',
        'Local integrated pest-management adviser',
      ],
      relatedIds: [
        'thrips',
        'powdery-mildew',
        'whiteflies',
        'leaf-scorch-edema',
      ],
    ),
    PlantHealthEntry(
      id: 'whiteflies',
      title: 'Whiteflies',
      scientificName: 'Aleyrodidae',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Small flying insects that gather on leaf undersides; their nymphs remain attached and may look like pale scales.',
      symptoms: [
        'Small white moth-like insects that fly upward when disturbed',
        'Clusters of pale, oval nymphs and flattened dark pupal cases underneath',
        'Sticky honeydew and black sooty mould',
        'Yellowing, reduced vigour and virus symptoms on susceptible crops',
      ],
      causes: [
        'Adults lay eggs on leaf undersides and move between plants on air, wind or infested stock',
        'Warm conditions support rapid reproduction, especially in protected settings',
        'Broad-spectrum insecticides can disrupt natural control and select for resistance',
      ],
      lookAlikes: [
        'Aphids, which do not normally fly when colony is disturbed',
        'Scale insects, mealybugs and leafhopper nymphs',
        'Dust or mould on pale leaf undersides',
      ],
      firstAid: [
        'Isolate the plant and inspect leaf undersides and nearby weeds.',
        'Rinse accessible foliage and remove the most heavily infested leaves when loss is acceptable.',
        'Use yellow sticky cards to monitor adults, not to treat the infestation by themselves.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Target nymphs and adults',
          steps: [
            'Remove and seal heavily infested material and clean up fallen leaves.',
            'Rinse leaf undersides regularly where the plant tolerates it.',
            'Keep greenhouses vented and monitor traps to detect a reinvasion early.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use a product labelled for whitefly',
          steps: [
            'Products must cover the correct life stage; many contact insecticides do not reach protected eggs or pupae.',
            'Use a soap, oil or insecticide only if the exact plant and whitefly are on the label.',
            'Plan a label-directed rotation to manage resistance and protect beneficial insects.',
          ],
        ),
      ],
      prevention: [
        'Quarantine new plants and inspect before moving them near a collection or crop.',
        'Use insect screens or exclusion in greenhouses where practical.',
        'Remove weed reservoirs and conserve or release appropriate natural enemies in protected crops.',
      ],
      escalation: [
        'A protected crop or collection develops a rapidly expanding population.',
        'Nymphs are present but repeated adult-only treatment is failing.',
        'A virus-susceptible crop is exposed and needs an integrated management plan.',
      ],
      safetyNote: 'Repeated spraying can create resistance and kill pollinators or natural enemies. Observe label re-entry, crop and harvest intervals, and never spray an open flower where bees are active.',
      references: [
        'University extension whitefly management guides',
        'RHS Advice: glasshouse whitefly',
        'Local protected-crop integrated pest-management service',
      ],
      relatedIds: ['aphids', 'sooty-mould', 'mosaic-virus', 'spider-mites'],
    ),
    PlantHealthEntry(
      id: 'scale-mealybugs',
      title: 'Scale and mealybugs',
      scientificName: 'Coccoidea and Pseudococcidae',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Sap-feeding insects hidden under protective shells or waxy filaments. Small colonies can spread through infested plant material and tools.',
      symptoms: [
        'Fixed brown, grey or white bumps attached to stems and leaf undersides',
        'White cottony material between leaves, roots and leaf veins',
        'Sticky honeydew, sooty mould, yellowing and premature leaf drop',
        'Weakened growth despite apparently moist soil',
      ],
      causes: [
        'Mobile crawler stages spread on plants, tools and clothing',
        'Indoor plants and sheltered outdoor plants provide favourable conditions',
        'Ant protection can reduce natural control of some scale insects',
      ],
      lookAlikes: [
        'Whitefly pupae, mealybug eggs and harmless plant galls',
        'Fungal fruiting bodies, lichen and mineral deposits',
        'Whitefly nymphs that are smaller and more uniformly aligned',
      ],
      firstAid: [
        'Isolate the plant and check stems, leaf joints, leaf undersides and roots for a hidden colony.',
        'Pick off accessible scale or mealybugs by hand; remove reachable cottony egg masses carefully without smearing wax across the plant.',
        'Clean tools and isolate for at least several weeks while checking for new crawlers.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Remove the protective cover',
          steps: [
            'Prune a small, known-good portion if the colony is concentrated there.',
            'Use an appropriate physical method for mealybugs and avoid squeezing sap onto the plant.',
            'Repeat inspections because eggs and crawlers often survive the first removal.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use complete coverage where justified',
          steps: [
            'Horticultural oil or insecticidal soap can work only when it reaches sheltered stages and is safe for the plant.',
            'Follow label crop and plant restrictions; test first and avoid heat, drought and tender new growth.',
            'Repeat only as directed because the protective covering and life stage affect control.',
          ],
        ),
      ],
      prevention: [
        'Quarantine and inspect new plants, including leaf axils and roots.',
        'Avoid overfertilising and manage ants when they protect scale colonies.',
        'Keep stressed plants healthy and use clean potting mix and pots.',
      ],
      escalation: [
        'The infestation has spread to roots or many stems despite repeated physical removal.',
        'A crop, greenhouse or large collection needs an integrated pest plan.',
        'The plant is valuable and the correct crawler timing or product is uncertain.',
      ],
      safetyNote: 'Do not use a household cleaner or cooking oil. Test soaps and horticultural oils because some plants, including stressed plants, are sensitive.',
      references: [
        'University extension scale insect management guides',
        'RHS Advice: scale insects and mealybugs',
        'Local extension or horticultural advisory service',
      ],
      relatedIds: ['aphids', 'whiteflies', 'sooty-mould', 'mosaic-virus'],
    ),
    PlantHealthEntry(
      id: 'thrips',
      title: 'Thrips',
      scientificName: 'Thripidae and related families',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Tiny slender insects that rasp young tissue and flowers, causing streaking that can remain long after the pests have gone.',
      symptoms: [
        'Fine silver, tan or pale streaks on leaves and flower petals',
        'Tiny dark flecks of excrement and reflective empty skins in sheltered areas',
        'Distorted young leaves, buds and flowers',
        'Small, slim insects moving quickly inside flowers or folded young tissue',
      ],
      causes: [
        'Thrips feed on tender tissue and may vector some plant viruses',
        'Warm weather, drought-stressed plants and abundant flowers can favour outbreaks',
        'They move in on wind, cut flowers, plant material and stored products',
      ],
      lookAlikes: [
        'Spider mites, which produce stippling and webbing',
        'Aphids, whitefly or aphid-induced leaf distortion',
        'Fungal streaks, mechanical rubbing and herbicide damage',
      ],
      firstAid: [
        'Inspect flowers, shoots and leaf folds with a white paper test under good light.',
        'Remove and bag badly infested flowers and tap a dark surface to identify the insects.',
        'Rinse accessible foliage and reduce stress without creating prolonged wetness.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Remove sheltered stages',
          steps: [
            'Remove affected flowers, old blooms and tightly folded leaves where practical.',
            'Use blue sticky cards for monitoring and keep them out of pollinator access.',
            'Do not move symptomatic plants or flowers between a crop and a clean collection.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.biological,
          title: 'Use a crop-specific biological plan',
          steps: [
            'Oriental thrips are commonly eaten by Orius predatory bugs and other beneficial insects.',
            'Avoid broad-spectrum sprays that remove predators and repeat treatments only when monitoring shows a need.',
            'Use exclusion or clean stock in high-value protected crops under local advice.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Treat confirmed severe infestations',
          steps: [
            'Choose a product labelled for thrips and the exact crop; some products work by contact and others by ingestion.',
            'Pay attention to sheltered young tissue and repeat only as the label directs.',
            'Observe pollinator, re-entry and harvest restrictions.',
          ],
        ),
      ],
      prevention: [
        'Monitor flowering plants with blue sticky cards and inspect new growth regularly.',
        'Keep plants evenly watered and choose clean propagation material.',
        'Remove old flowers and manage weeds that can provide an early reservoir.',
      ],
      escalation: [
        'A virus-susceptible crop is exposed and a vector-capable species is confirmed.',
        'A greenhouse or flower crop has a population despite monitoring and sanitation.',
        'Silver damage continues after all live thrips have disappeared and diagnosis is uncertain.',
      ],
      safetyNote: 'Old feeding scars do not heal and prove a product failed. Confirm live pests before repeating sprays, and avoid treating open flowers when pollinators are foraging.',
      references: [
        'University extension thrips integrated pest-management guides',
        'RHS Advice: thrips on flowers and crops',
        'Local protected-crop adviser',
      ],
      relatedIds: ['spider-mites', 'mosaic-virus', 'aphids', 'whiteflies'],
    ),
    PlantHealthEntry(
      id: 'fungus-gnats',
      title: 'Fungus gnats',
      scientificName: 'Sciaridae and related flies',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.routine,
      summary: 'Small dark flies around damp potting mix; their larvae feed on fungi and vulnerable organic matter but can also damage small roots.',
      symptoms: [
        'Small dark flies rising in clouds when a pot is moved',
        'Constantly wet soil, algae on the surface or a sour organic smell',
        'Tiny translucent larvae in the upper soil layer with a dark head',
        'Seedling loss or reduced vigour when the root zone remains saturated',
      ],
      causes: [
        'Adult fungus gnats lay eggs in damp organic potting mix',
        'Overwatering and poor drainage create the moist conditions larvae prefer',
        'Adults enter from neighbouring pots, compost or bring-in soil',
      ],
      lookAlikes: [
        'Small fungus gnat adults can be confused with harmless flies and other dark gnats',
        'Shore fly, sciarid fly larvae and root-feeding aphids',
        'Overwatering, algae or nutrient problems without any larvae present',
      ],
      firstAid: [
        'Place yellow sticky cards near the pot to confirm adult activity without spraying first.',
        'Let the surface dry according to the plant’s needs and correct drainage or pot standing in water.',
        'Remove dead leaves and check a small soil sample for translucent larvae with dark heads.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Remove excess moisture',
          steps: [
            'Water less often and never leave a container standing in a full saucer.',
            'Use a free-draining mix appropriate to the plant and repot only when the mix has broken down.',
            'Allow the surface to dry where the species and environment permit.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.biological,
          title: 'Use a suitable biological control',
          steps: [
            'Beneficial nematodes can target fungus-gnat larvae when the product, temperature and moisture conditions match.',
            'Apply exactly as the biological product label directs and maintain the stated soil conditions.',
            'Sticky cards monitor adults but do not kill larvae in the soil.',
          ],
        ),
      ],
      prevention: [
        'Use clean, well-drained potting mix and avoid bringing outdoor soil indoors.',
        'Inspect and quarantine new plants, including the soil surface.',
        'Avoid empty pots, stagnant water and constantly wet saucers.',
      ],
      escalation: [
        'Seedlings are collapsing despite corrected watering and no obvious stem disease.',
        'A large greenhouse or nursery crop has a sustained population.',
        'A different dark fly or root-feeding pest is suspected and identification is needed.',
      ],
      safetyNote: 'Insect growth regulators or insecticides often fail because they target adults rather than larvae. Use only a product labelled for fungus gnats and follow all food-crop and pet restrictions.',
      references: [
        'University extension fungus-gnat management guides',
        'RHS Advice: fungus gnats',
        'Local biological-control supplier or extension adviser',
      ],
      relatedIds: [
        'overwatering-root-stress',
        'damping-off',
        'root-crown-rot',
        'aphids',
      ],
    ),
    PlantHealthEntry(
      id: 'slugs-snails',
      title: 'Slugs and snails',
      scientificName: 'Terrestrial gastropods',
      category: PlantProblemCategory.pest,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Night-active molluscs that rasp holes in young seedlings, soft leaves and fruit, often leaving shiny trails.',
      symptoms: [
        'Ragged holes, notches and seedlings missing at ground level',
        'Shiny or dried mucus trails on soil, pots and pots',
        'Damage concentrated in damp, sheltered places or after dark',
        'Holes in fruit and low leaves, sometimes with grey-brown waste nearby',
      ],
      causes: [
        'Slugs and snails feed after dark and during moist weather',
        'Dense ground cover, mulch, pots and damp debris provide cover and moisture',
        'They move in on plants, compost, soil and stored materials',
      ],
      lookAlikes: [
        'Caterpillars, earwigs and rodents can create similar holes',
        'Wind, frost and mechanical damage can tear or scorch leaves',
        'Dark marks alone can be mistaken for feeding without confirming a trail or organism.',
      ],
      firstAid: [
        'Check after dark and in damp hiding places; protect a small vulnerable plant as a trap or barrier.',
        'Clear debris only where it will not harm beneficial habitat and reduce hiding places around pots.',
        'Water in the morning so soil and surroundings are drier overnight.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Use barriers, traps and hand removal',
          steps: [
            'Hand-pick hiding places at night and keep pots off the ground where practical.',
            'Use a physical barrier tested in the local setting; check that it does not trap or harm wildlife.',
            'Replace a known vulnerable seedling with a temporary physical cover until the threat falls.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use bait only under label directions',
          steps: [
            'Choose a bait labelled for the crop, setting and molluscs and place it according to the label.',
            'Store and place bait away from children, pets and wildlife; some products are not iron phosphate.',
            'Avoid broad homemade mixtures and never use a product on edible produce unless the label allows it.',
          ],
        ),
      ],
      prevention: [
        'Reduce sheltered damp hiding places and inspect plants in the evening.',
        'Use natural habitat and avoid disturbing beneficial decomposers or ground-feeding wildlife.',
        'Protect vulnerable seedlings and maintain plant vigour so they can tolerate limited feeding.',
      ],
      escalation: [
        'Seedlings are being destroyed faster than they can be protected.',
        'A high-value food crop or nursery has repeated severe damage.',
        'The damage is increasing and slugs or snails cannot be confirmed.',
      ],
      safetyNote: 'No molluscicide is safe to ignore around children, pets or wildlife. Follow the exact label for bait placement, collection, re-entry and harvest intervals.',
      references: [
        'RHS Advice: slugs and snails',
        'University extension mollusc integrated pest-management guides',
        'Local wildlife-safe gardening adviser',
      ],
      relatedIds: [
        'fungal-leaf-spot',
        'aphids',
        'overwatering-root-stress',
        'damping-off',
      ],
    ),
    PlantHealthEntry(
      id: 'root-crown-rot',
      title: 'Root and crown rot',
      scientificName:
          'Phytophthora, Pythium, Rhizoctonia and other soil pathogens',
      category: PlantProblemCategory.waterRoots,
      urgency: PlantProblemUrgency.urgent,
      summary: 'Several root and crown pathogens cause plants to wilt, decline and die from below. Waterlogging is a major risk factor.',
      symptoms: [
        'Wilting despite consistently moist soil',
        'Dark, soft, smelly or reddish-brown roots with a damaged outer layer',
        'Crown tissue that is dark, sunken, soft or cracking at the soil line',
        'Sudden collapse, branch dieback or failure to recover after watering',
      ],
      causes: [
        'Soil- or water-borne pathogens favoured by prolonged saturation',
        'Infected plants, potting mix, soil, water and unclean containers',
        'Cold or overheated soil, root injury and pots without drainage',
      ],
      lookAlikes: [
        'Bacterial wilt, waterlogging without infection and severe vine-weevil feeding',
        'Physical root restriction, salt damage and drought stress',
        'Crown gall or a buried, girdling root',
      ],
      firstAid: [
        'Stop automatic watering and remove the plant from standing water.',
        'Slide the root ball out carefully and photograph roots and the crown before trimming.',
        'Isolate the plant and the removed potting mix; clean the pot and tools after inspection.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Stop conditions that feed the problem',
          steps: [
            'Use a free-draining pot and mix, correct compaction and keep the crown at the correct planting depth.',
            'Remove collapsed tissue. Trim only clearly dead roots with a clean blade; badly rotted plants rarely recover.',
            'Do not reuse the contaminated mix or pass it to other plants.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.professionalCare,
          title: 'Confirm recurring root disease',
          steps: [
            'Send a fresh sample of the transition between healthy and diseased tissue to a plant clinic.',
            'Ask about locally registered root-treatment products and whether a test will change the outcome.',
            'In a landscape tree or recurrent crop, obtain professional diagnosis before removing soil or nearby plants.',
          ],
        ),
      ],
      prevention: [
        'Use clean pots, drainage holes and a mix suited to the species.',
        'Do not overwater, compact soil or leave containers in saucers.',
        'Use resistant plants and locally clean stock; remove confirmed diseased plants and roots.',
      ],
      escalation: [
        'A woody perennial, large plant or food crop is collapsing from the crown.',
        'Damage continues in several pots that should have similar watering.',
        'A regulatory root pathogen or honey fungus is possible in the area.',
      ],
      safetyNote: 'There is no universal home cure for root rot. Fungicides usually cannot restore dead roots, and unnecessary treatment can make a declining plant worse.',
      references: [
        'RHS Advice: root problems and Phytophthora root rot',
        'University extension root-rot fact sheets',
        'Local plant diagnostic laboratory or arborist',
      ],
      relatedIds: [
        'overwatering-root-stress',
        'damping-off',
        'bacterial-wilt',
        'bacterial-soft-rot',
      ],
    ),
    PlantHealthEntry(
      id: 'overwatering-root-stress',
      title: 'Overwatering and suffocated roots',
      scientificName: 'Abiotic waterlogging stress',
      category: PlantProblemCategory.waterRoots,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Saturated soil displaces air from root zones, causing yellowing and wilting that can be mistaken for thirst or nutrient shortage.',
      symptoms: [
        'Yellow leaves, especially lower or older leaves, while the soil stays wet',
        'Wilting or limp growth despite frequent watering',
        'Brown, soft roots, a sour smell, surface algae or a collapsed potting mix',
        'White crust or a musty smell from accumulated salts in a wet pot',
      ],
      causes: [
        'Water applied more often than the root zone can take it up',
        'A pot without drainage, compacted soil or a pot standing in water',
        'A container much larger than the root ball or a broken-down dense mix',
      ],
      lookAlikes: [
        'Root rot caused by a pathogen',
        'Nitrogen deficiency, naturally ageing leaves or low light',
        'Drought stress in a plant whose soil has been overwatered and lost oxygen',
      ],
      firstAid: [
        'Pause watering and empty any saucer or cachepot that holds water.',
        'Check moisture and roots below the surface; do not judge by the dry top layer alone.',
        'Move the plant to bright indirect light and withhold further water until the species-appropriate mix needs it.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Restore air around the roots',
          steps: [
            'Ensure drainage holes are open and repot only when the mix is less wet, using a suitable free-draining mix.',
            'Keep the pot at the depth used for that plant and avoid a standing tray of water.',
            'Adjust watering to the plant, pot, root volume, temperature and season rather than a fixed schedule.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Assess root damage',
          steps: [
            'Healthy roots are usually firm and pale; dead roots are dark, soft or strongly scented.',
            'Remove only dead tissue with a clean tool, and seek advice if much of the root system is affected.',
            'Do not feed a wilted, waterlogged plant until new growth and roots are recovering.',
          ],
        ),
      ],
      prevention: [
        'Use a pot only slightly larger than the root system and a mix with suitable drainage.',
        'Check moisture below the surface before watering and adjust for season and weather.',
        'Empty cachepots and saucers after watering and never stack a water-filled tray under a pot.',
      ],
      escalation: [
        'The plant collapses quickly, the crown is soft or most roots are dark and dead.',
        'Several plants from the same source fail after watering or repotting.',
        'A large tree or shrub wilts in wet ground and professional root testing is needed.',
      ],
      safetyNote: 'Do not add fertilizer, fungicide or a home remedy to saturated soil. This can burn stressed roots further and obscure the original problem.',
      references: [
        'RHS Advice: watering and root problems',
        'University extension overwatering and root-rot guidance',
        'Local extension service for landscape plants',
      ],
      relatedIds: [
        'root-crown-rot',
        'damping-off',
        'nitrogen-deficiency',
        'fertilizer-salt-injury',
      ],
    ),
    PlantHealthEntry(
      id: 'damping-off',
      title: 'Damping-off of seedlings',
      scientificName:
          'Pythium, Rhizoctonia, Fusarium, Phytophthora and related pathogens',
      category: PlantProblemCategory.waterRoots,
      urgency: PlantProblemUrgency.prompt,
      summary: 'A group of seedling diseases that rot the stem at soil level, causing thin seedlings to topple or fail to emerge.',
      symptoms: [
        'Failure of some seeds to emerge despite normal germination conditions',
        'Water-soaked brown areas at the base of a thin seedling',
        'Seedlings collapse or bend at the soil line and die',
        'Pinched or damaged roots and poor growth after surviving the initial stage',
      ],
      causes: [
        'Several soil-borne pathogens in overwet, poorly drained growing media',
        'Crowded seedlings, heavy watering and cool or overheated conditions',
        'Contaminated trays, benches, tools, pots, water and reused mix',
      ],
      lookAlikes: [
        'Legume emergence problems and shallow planting',
        'Stem injury, damping from cold or a dry seedling that later collapses',
        'Fungus gnat, root aphid or vine-weevil damage at the root zone',
      ],
      firstAid: [
        'Remove collapsed seedlings and the surrounding medium; do not tug or compost loose stems in place.',
        'Stop misting and allow the surface to dry between careful waterings.',
        'Separate the remaining healthy seedlings and sanitise the tray or pot before reuse.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Create cleaner seedling conditions',
          steps: [
            'Use fresh sterile or pasteurised, free-draining propagation mix and clean containers.',
            'Sow at the recommended depth, avoid overcrowding and provide gentle airflow without a cold draft.',
            'Water gently at the base in the morning and prevent trays from standing in water.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use preventive controls only where appropriate',
          steps: [
            'Commercial seed and growing-media suppliers may offer a labelled seed treatment for specific damping-off pathogens.',
            'Do not apply a garden fungicide to edible seedlings unless the label explicitly permits that crop and setting.',
            'Recurring losses usually require better sanitation and moisture control before another treatment.',
          ],
        ),
      ],
      prevention: [
        'Buy fresh mix and clean or disinfect reusable trays according to product directions.',
        'Avoid dense sowing and overwatering; use bottom watering only when the crop and stage allow.',
        'Keep stored seed dry and remove failed seedlings promptly.',
      ],
      escalation: [
        'A large proportion of a crop collapses in one day.',
        'Damping-off continues despite fresh mix, clean trays and corrected moisture.',
        'A protected or commercial crop needs pathogen testing and integrated control advice.',
      ],
      safetyNote: 'Do not use concentrated bleach, vinegar or unlabelled disinfectants on seeds, mix or the rooting zone. Follow exact sanitation-product labels and never mix chemicals.',
      references: [
        'University extension damping-off fact sheets',
        'RHS Advice: seedlings and damping-off',
        'Local seed or nursery diagnostic service',
      ],
      relatedIds: [
        'root-crown-rot',
        'overwatering-root-stress',
        'fungus-gnats',
        'bacterial-soft-rot',
      ],
    ),
    PlantHealthEntry(
      id: 'leaf-scorch-edema',
      title: 'Leaf scorch and edema',
      scientificName: 'Abiotic light, water and transpiration stress',
      category: PlantProblemCategory.environment,
      urgency: PlantProblemUrgency.routine,
      summary: 'Two non-infectious problems often mistaken for disease: tissue burned by excess light, heat or salt, and blisters caused by unusually rapid water uptake.',
      symptoms: [
        'Bleached, tan or crisp patches mainly on leaves facing bright light or heat',
        'Brown tips and margins without a separate spreading fungal growth',
        'Tiny water-soaked blisters, corky bumps or rough patches on leaf undersides',
        'A combination of overwatering, low light and high water uptake for edema',
      ],
      causes: [
        'A sudden move into stronger sun or heat reflected from glass',
        'Fertilizer or irrigation salt accumulating at leaf edges',
        'For edema, roots taking up water faster than the leaves can transpire it',
      ],
      lookAlikes: [
        'Fungal and bacterial leaf spots',
        'Nutrient toxicity, herbicide injury and cold damage',
        'Natural leaf texture or gland-like structures on some plants',
      ],
      firstAid: [
        'Identify whether the pattern is on the sun-facing side, leaf edge or underside before treating.',
        'Remove only fully dead tissue; scorched and blistered tissue will not turn green again.',
        'Check light, temperature, watering and fertilizer history, then change one factor at a time.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Correct the physical cause',
          steps: [
            'Move a scorched plant away from intense midday sun and heat-reflecting glass, introducing stronger light gradually where appropriate.',
            'For edema, water only when the plant needs it and improve light and airflow instead of misting the bumps.',
            'Flush excess soluble salts only when drainage is excellent and the plant is not waterlogged.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Protect new growth',
          steps: [
            'Keep future foliage out of sudden extreme exposure and use an appropriate shade or curtain during a heat wave.',
            'Do not cut healthy tissue to remove every small blemish; severe pruning creates more stress.',
            'Wait for several weeks of corrected care before judging recovery.',
          ],
        ),
      ],
      prevention: [
        'Acclimate plants to brighter conditions gradually and match them to species needs.',
        'Avoid overfertilising and irrigating with water that is unusually saline for the crop.',
        'Use a suitable pot, watering rhythm and light level rather than treating the symptom alone.',
      ],
      escalation: [
        'Damage continues after the environmental cause has been corrected.',
        'Spots are spreading or have halos, holes or growth and may not be scorch or edema.',
        'A crop shows widespread tip burn after a new fertilizer or irrigation source was introduced.',
      ],
      safetyNote: 'No pesticide treats physical scorch or edema. Before buying a spray, rule out a spreading infection, fertiliser injury and herbicide exposure.',
      references: [
        'University extension abiotic plant-disorder guides',
        'RHS Advice: leaf scorch and environmental problems',
        'Local greenhouse or ornamental-plant extension service',
      ],
      relatedIds: [
        'fungal-leaf-spot',
        'fertilizer-salt-injury',
        'overwatering-root-stress',
        'spider-mites',
      ],
    ),
    PlantHealthEntry(
      id: 'herbicide-injury',
      title: 'Herbicide drift and carryover injury',
      scientificName:
          'Abiotic chemical injury from growth-regulator or other herbicides',
      category: PlantProblemCategory.environment,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Weed killers can damage plants through spray drift, contaminated equipment, manure, compost or residue in soil. There is no universal antidote.',
      symptoms: [
        'Cupped, curled, twisted or strap-like new leaves',
        'Yellowing, bleaching, distorted stems or parallel vein discoloration',
        'Damage following mowing, spraying, nearby treatment or a new compost source',
        'Symptoms that appear widely rather than following a single disease pattern',
      ],
      causes: [
        'Wind, vapour or spray drift from a nearby weed treatment',
        'Residue on tools, mowing equipment, clothing, pots or watering cans',
        'Persistent herbicide in manure, compost, mulch, soil or imported planting material',
      ],
      lookAlikes: [
        'Virus, broad-mite, thrips or aphid distortion',
        'Nutrient imbalance, water stress and natural fasciation',
        'Fungal or bacterial disease that affects only part of a plant',
      ],
      firstAid: [
        'Stop all possible exposure and photograph the pattern, including healthy and affected plants.',
        'Do not add fertilizer, compost or another pesticide trying to correct distorted growth.',
        'Remove newly suspected contaminated material only if it can be done without further exposure.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Prevent further exposure',
          steps: [
            'Identify the exact product and use location before deciding whether the diagnosis is plausible.',
            'Decontaminate tools and equipment using the product label directions; never improvise a chemical bath.',
            'Stop using a suspect compost, manure, mulch or irrigation source until the source is investigated.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.professionalCare,
          title: 'Get exposure-specific advice',
          steps: [
            'Ask an extension agronomist, plant clinic or local agricultural authority about the product, dose history and symptom timing.',
            'Some persistent herbicides can affect a site for more than one season.',
            'Keep records and report suspected drift where local law or a neighbouring party may be affected.',
          ],
        ),
      ],
      prevention: [
        'Read the herbicide label for susceptible nearby plants, drift precautions and disposal.',
        'Do not spray in wind or when temperature or inversion conditions increase drift.',
        'Keep weed killers, grass clippings and manure separate from clean pots and plant media.',
      ],
      escalation: [
        'Multiple plant species show distortion or bleaching after a shared event.',
        'Livestock, pets, children or a food crop may have been exposed to a pesticide.',
        'A large planting or suspected persistent soil herbicide needs specialist assessment.',
      ],
      safetyNote: 'If a person or animal may have ingested or been exposed to a herbicide, contact a poison centre, emergency service or veterinarian immediately and use the product label information.',
      references: [
        'Local agricultural extension and pesticide authority guidance',
        'University extension herbicide-injury fact sheets',
        'Product label and first-aid information for the suspected product',
      ],
      relatedIds: [
        'mosaic-virus',
        'thrips',
        'fertilizer-salt-injury',
        'leaf-scorch-edema',
      ],
    ),
    PlantHealthEntry(
      id: 'nitrogen-deficiency',
      title: 'Nitrogen deficiency',
      scientificName: 'Abiotic nutrient deficiency',
      category: PlantProblemCategory.nutrition,
      urgency: PlantProblemUrgency.routine,
      summary: 'A lack of available nitrogen commonly causes older leaves to pale first, but waterlogging, low light and natural ageing can look similar.',
      symptoms: [
        'Uniform pale green to yellow older leaves while new growth stays greener',
        'Smaller leaves and slower growth in a plant that is otherwise stable',
        'Early leaf drop or a thin, weak canopy',
        'No dead spots, webbing, fuzzy growth or a strong root-rott smell',
      ],
      causes: [
        'Insufficient available nitrogen in the growing medium or soil',
        'Repeated heavy leaching, usually in containers or high-rain environments',
        'Low light or waterlogged roots that prevent normal uptake',
      ],
      lookAlikes: [
        'Natural ageing of one or a few lower leaves',
        'Overwatering, low light, pH lockout and general root stress',
        'Iron or magnesium deficiency and the beginning of several diseases',
      ],
      firstAid: [
        'Do not fertilise until moisture, drainage, light and roots have been checked.',
        'Compare the age of affected leaves with new growth and look for pests or disease signs.',
        'If a nutrient issue is likely, use a soil or growing-medium test when the stakes justify it.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Correct the uptake problem',
          steps: [
            'Restore appropriate drainage, watering and light before adding more nutrients.',
            'Check that the plant is in a suitable root volume and that the medium has not broken down.',
            'Allow a clear pattern of new growth to develop before repeatedly changing the fertilizer.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Use a balanced, appropriate fertilizer',
          steps: [
            'Choose a fertilizer suitable for the species and growth stage rather than using a high-nitrogen product by guesswork.',
            'Follow the product label for rate and frequency; excess salts can damage roots and make a deficiency worse.',
            'Flush old container mix only when the plant is not waterlogged and drainage is excellent.',
          ],
        ),
      ],
      prevention: [
        'Feed established plants during active growth according to species and product directions.',
        'Use fresh, appropriate potting mix and replace or refresh a medium when it no longer drains or holds structure.',
        'Avoid a fixed high-nitrogen schedule regardless of season, light or plant growth.',
      ],
      escalation: [
        'A crop or collection declines rapidly despite corrected care and appropriate feeding.',
        'Leaf yellowing affects new growth, is patchy or includes spots, wilt or pests.',
        'A soil test shows a severe imbalance, toxicity or a nutrient cannot be corrected in the current medium.',
      ],
      safetyNote: 'More fertilizer is not a universal treatment. Overfertilising can burn roots, create salt injury, attract pests and pollute water.',
      references: [
        'University extension plant-nutrition guidance',
        'Local soil-testing laboratory or agricultural extension service',
        'RHS Advice: plant nutrition and fertilizer',
      ],
      relatedIds: [
        'interveinal-chlorosis',
        'overwatering-root-stress',
        'fertilizer-salt-injury',
        'aphids',
      ],
    ),
    PlantHealthEntry(
      id: 'interveinal-chlorosis',
      title: 'Interveinal chlorosis',
      scientificName:
          'Abiotic iron, manganese or magnesium availability problem',
      category: PlantProblemCategory.nutrition,
      urgency: PlantProblemUrgency.routine,
      summary: 'Leaves turn yellow while veins remain green. The leaf age and soil pH can help narrow the cause, but a photo alone cannot identify the nutrient.',
      symptoms: [
        'Yellow tissue between green veins, often forming a fine network pattern',
        'Iron-related pattern usually begins on the youngest leaves',
        'Magnesium-related pattern usually begins on older leaves',
        'Severe cases progress to brown patches, curling or leaf drop',
      ],
      causes: [
        'High soil pH making iron or manganese less available',
        'A genuine magnesium shortage in older leaves',
        'Wet, cold or damaged roots unable to take up nutrients',
        'Competing roots, poor drainage or an unsuitable long-term container mix',
      ],
      lookAlikes: [
        'Downy mildew, virus patterns and mite damage',
        'Nitrogen deficiency, which usually affects the whole older leaf more evenly',
        'Natural variegation and genetic leaf patterns',
      ],
      firstAid: [
        'Note whether the newest or oldest leaves are affected and compare several leaves.',
        'Check drainage, root health and whether the growing medium or water is unusually alkaline.',
        'Avoid repeated iron or magnesium products until the cause is better supported.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Make existing nutrients available',
          steps: [
            'Correct waterlogging, root damage and compaction before changing fertilizer.',
            'Confirm the species-specific target pH and test the medium or water before changing it; then use a species-appropriate medium or locally recommended method.',
            'Replace unsuitable container mix rather than repeatedly adding amendments to a full pot.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.registeredProduct,
          title: 'Correct a confirmed shortage',
          steps: [
            'Use a chelated iron or other nutrient product only when the deficiency and product suitability are reasonably clear.',
            'Follow label rates because chelated nutrients can still cause root injury or become unavailable over time.',
            'Reassess new growth after several weeks; old yellow leaves will not normally return to green.',
          ],
        ),
      ],
      prevention: [
        'Match the plant and growing-medium pH to the species.',
        'Use suitable irrigation water and avoid excessive lime or alkaline compost where the plant is sensitive.',
        'Keep roots aerated and fertilise moderately with a balanced product.',
      ],
      escalation: [
        'Symptoms continue after drainage, pH and nutrient status have been checked.',
        'New leaves become severely distorted or die rapidly.',
        'A crop shows widespread chlorosis with a poor yield and needs a professional test.',
      ],
      safetyNote: 'A vitamin or iron remedy is not a diagnosis. Repeated nutrient additions can create toxic salts and make the original root or pH problem worse.',
      references: [
        'University extension micronutrient and pH guidance',
        'Local soil-testing laboratory',
        'RHS Advice: yellow leaves and plant nutrition',
      ],
      relatedIds: [
        'nitrogen-deficiency',
        'overwatering-root-stress',
        'fertilizer-salt-injury',
        'mosaic-virus',
      ],
    ),
    PlantHealthEntry(
      id: 'fertilizer-salt-injury',
      title: 'Fertilizer and irrigation-salt injury',
      scientificName: 'Abiotic soluble-salt toxicity',
      category: PlantProblemCategory.nutrition,
      urgency: PlantProblemUrgency.prompt,
      summary: 'Excess dissolved salts draw water from roots and burn leaf edges. It commonly follows overfertilising, dry potting mix or saline water.',
      symptoms: [
        'Crisp brown leaf tips and margins, sometimes with a clear green base',
        'Wilting even when the potting mix appears moist',
        'A white salt crust on soil, pot rims or watering-well surfaces',
        'Root tips that are brown, while older roots may remain lighter',
      ],
      causes: [
        'More fertilizer or compost than the plant and medium can buffer',
        'Repeated shallow watering that leaves salts concentrated at the surface',
        'Saline irrigation or water, or fertiliser stored near vulnerable roots',
        'A pot without adequate drainage that traps and concentrates salts',
      ],
      lookAlikes: [
        'Drought scorch, low humidity and wind damage',
        'Salt spray injury, herbicide damage and natural leaf-edge browning',
        'Root rot or a damaged root system',
      ],
      firstAid: [
        'Stop fertilizer and check moisture, drainage and the source of irrigation water.',
        'Do not add more fertilizer to dry medium or attempt to correct everything with a foliar spray.',
        'Remove a heavily crusted surface layer of old mix without removing healthy roots.',
      ],
      treatments: [
        PlantTreatment(
          type: PlantTreatmentType.environment,
          title: 'Dilute and drain excess salts',
          steps: [
            'Apply clean, low-salinity water slowly only when drainage is open and the root ball is not already saturated.',
            'Let excess water drain completely and empty any container beneath the pot.',
            'Repeat irrigation and fertility according to the medium, plant and product labels rather than daily.',
          ],
        ),
        PlantTreatment(
          type: PlantTreatmentType.physical,
          title: 'Replace unusable medium',
          steps: [
            'Repot a severely affected plant into fresh, suitable free-draining mix when the old medium is very salty.',
            'Handle roots gently and prune only dead, clearly brown tissue with a clean tool.',
            'Do not repot a plant that is already severely waterlogged until excess water has drained.',
          ],
        ),
      ],
      prevention: [
        'Use the fertilizer label rate and calibrate rather than estimating by handfuls.',
        'Choose low-salinity irrigation where possible and test highly saline water.',
        'Keep fertiliser away from roots, drains and water sources and never use a full container undiluted.',
      ],
      escalation: [
        'A field, greenhouse or irrigation system is causing widespread tip burn.',
        'Symptoms continue after the salt source and drainage are corrected.',
        'Plant collapse or root loss suggests salt injury may have combined with root disease.',
      ],
      safetyNote: 'Fertiliser can injure people and pets as well as plants. Store it in its original container, keep it away from water and food, and wash hands after handling.',
      references: [
        'University extension fertilizer-salt injury guides',
        'Local irrigation-water quality laboratory',
        'RHS Advice: fertilizer use and plant care',
      ],
      relatedIds: [
        'overwatering-root-stress',
        'nitrogen-deficiency',
        'leaf-scorch-edema',
        'root-crown-rot',
      ],
    ),
  ];

  static const Map<String, String> categoryGuidance = {
    'Fungal': 'Remove infected material, reduce leaf wetness and crowding, then use only a product labelled for the confirmed host and fungus.',
    'Bacterial': 'Bacterial infections often cannot be cured. Limit spread with sanitation, clean stock and avoiding wet handling; copper is preventive for some diseases, not a universal cure.',
    'Viral': 'Viruses cannot be cured with household sprays. Isolate suspected plants, control vectors and clean tools; confirmation is valuable before major losses.',
    'Pests': 'Find the pest and its life stage, correct plant stress, exclude or physically remove it, and use a labelled product only when monitoring shows it is needed.',
    'Water & roots': 'Check moisture below the surface, drainage and roots before adding food or medicine. Saturated and very dry root zones can cause similar wilting.',
    'Environment': 'Changing one physical factor can stop damage but will not restore dead tissue. Look for a spread pattern before assuming every blemish is environmental.',
    'Nutrition': 'Leaf colour does not diagnose a nutrient by itself. Check light, water, roots and pH, then use a test or a measured fertilizer rather than repeated remedies.',
  };

  static const Map<String, String> quickReferenceIds = {
    'powdery-mildew': 'powdery-mildew',
    'downy-mildew': 'downy-mildew',
    'rust': 'rust',
    'anthracnose': 'anthracnose',
    'grey-mould': 'gray-mold',
    'damping-off': 'damping-off',
    'root-crown-rot': 'root-rot',
    'bacterial-leaf-spot': 'bacterial-leaf-spot',
    'mosaic-virus': 'mosaic-virus',
    'spider-mites': 'spider-mites',
    'aphids': 'aphids',
    'thrips': 'thrips',
    'whiteflies': 'whiteflies',
    'scale-mealybugs': 'scale-mealybugs',
    'fungus-gnats': 'fungus-gnats',
    'nitrogen-deficiency': 'nitrogen-deficiency',
    'interveinal-chlorosis': 'iron-chlorosis',
  };

  static String? quickReferenceIdFor(String id) => quickReferenceIds[id];

  static final Map<String, PlantHealthEntry> _byId = {
    for (final entry in all) entry.id: entry,
  };

  static PlantHealthEntry? byId(String id) => _byId[id];

  static String _normalizeSearchText(String value) => value
      .toLowerCase()
      .replaceAll('grey', 'gray')
      .replaceAll('mould', 'mold');

  static List<PlantHealthEntry> search(
    String query, {
    PlantProblemCategory? category,
  }) {
    final normalized = _normalizeSearchText(query.trim());
    final terms = normalized
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();

    return all
        .where((entry) {
          if (category != null && entry.category != category) return false;
          if (terms.isEmpty) return true;
          final searchable = _normalizeSearchText(entry.searchableText);
          return terms.every(searchable.contains);
        })
        .toList(growable: false);
  }
}
