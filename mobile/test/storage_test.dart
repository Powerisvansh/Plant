import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:plantdoctor/core/constants.dart';
import 'package:plantdoctor/models/scan_models.dart';
import 'package:plantdoctor/services/storage/app_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dir = await sqflite.getDatabasesPath();
    await sqflite.databaseFactory
        .deleteDatabase('$dir/${StorageKeys.dbName}');
  });

  test('AppDatabase round-trips a scan and a plant', () async {
    final db = await AppDatabase.open();
    try {
      final now = DateTime.now();
      final scan = ScanRecord(
        id: 's_test_1',
        createdAt: now,
        thumbPath: '/x/working_0.jpg',
        imagePaths: const ['/x/working_0.jpg', '/x/working_1.jpg'],
        imageSubjects: const ['Whole plant', 'Leaf close-up'],
        plantGuess: 'Basil',
        scientificGuess: 'Ocimum basilicum',
        identificationConfidence: 0.42,
        identificationUncertain: true,
        healthIndex: 76,
        overallCondition: 'Needs attention',
        observedIndicators: const ['Yellow discoloration'],
        causeLabels: const ['Possible nutrient-related stress'],
        followUp: 'Balcony\nTwice a week',
        notes: '',
        savedPlantId: null,
      );
      await db.insertScan(scan);

      final loaded = await db.scanById('s_test_1');
      expect(loaded, isNotNull);
      expect(loaded!.plantGuess, 'Basil');
      expect(loaded.identificationUncertain, isTrue);
      expect(loaded.imagePaths, hasLength(2));
      expect(loaded.observedIndicators, contains('Yellow discoloration'));
      expect(loaded.followUp, contains('Twice a week'));

      final plant = SavedPlant(
        id: 'p_test_1',
        name: 'Basil',
        species: 'Ocimum basilicum',
        createdAt: now,
        notes: 'sunny windowsill',
        currentHealthIndex: 76,
        photoPath: '/x/working_0.jpg',
      );
      await db.insertPlant(plant);
      await db.attachScanToPlant('s_test_1', 'p_test_1');

      final plantScans = await db.scansForPlant('p_test_1');
      expect(plantScans, hasLength(1));
      expect(plantScans.first.plantGuess, 'Basil');

      await db.updateScanNotes('s_test_1', 'Repotted');
      expect((await db.scanById('s_test_1'))!.notes, 'Repotted');

      await db.updatePlant('p_test_1', healthIndex: 60);
      final updated = (await db.allPlants()).firstWhere((p) => p.id == 'p_test_1');
      expect(updated.currentHealthIndex, 60);

      await db.deleteScan('s_test_1');
      await db.deletePlant('p_test_1');
      expect(await db.scanById('s_test_1'), isNull);
      expect(await db.allPlants(), isEmpty);
    } finally {
      await db.close();
    }
  });
}