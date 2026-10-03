import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the plant category system against the *built* database rather than a
/// mock, because the point of these assertions is that every staged species
/// actually landed in a real user-facing category.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    // The FFI factory resolves a relative path against its own working
    // directory, so the bundled asset is opened by absolute path. This reads
    // the same file the app packages, never a fixture.
    final asset = File('assets/plant_knowledge/plantdoctor.db').absolute.path;
    expect(File(asset).existsSync(), isTrue,
        reason: 'the knowledge bundle must ship inside the app assets');
    db = await sqflite.openDatabase(
      asset,
      options: sqflite.OpenDatabaseOptions(readOnly: true),
    );
  });

  tearDownAll(() async => db.close());

  test('every plant has at least one category and exactly one primary', () async {
    final plants = (await db.rawQuery('SELECT COUNT(*) AS n FROM plants'))
        .first['n'] as int;
    final categorised = (await db.rawQuery(
            'SELECT COUNT(DISTINCT plant_id) AS n FROM plant_category_map'))
        .first['n'] as int;
    final primary = (await db.rawQuery(
            "SELECT COUNT(*) AS n FROM plant_category_map WHERE is_primary = 1"))
        .first['n'] as int;

    expect(categorised, plants,
        reason: 'a plant with no category would vanish from every filter');
    expect(primary, plants,
        reason: 'each plant needs exactly one primary label for its browse card');
  });

  test('category vocabulary covers the use cases a grower browses by', () async {
    final codes = (await db.rawQuery('SELECT code FROM plant_categories'))
        .map((r) => r['code'] as String)
        .toSet();

    for (final expected in [
      'FOOD_CROP',
      'CEREAL',
      'PULSE',
      'OILSEED',
      'VEGETABLE',
      'FRUIT',
      'SPICE',
      'HERB',
      'ORNAMENTAL',
      'TREE',
      'WEED',
      'SUCCULENT',
    ]) {
      expect(codes, contains(expected),
          reason: '$expected is a category growers browse by');
    }
  });

  test('every category code referenced by a mapping is defined', () async {
    final orphans = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM plant_category_map m '
            'LEFT JOIN plant_categories c ON c.id = m.category_id '
            'WHERE c.id IS NULL'))
        .first['n'] as int;
    expect(orphans, 0);
  });

  test('a curated food crop carries its crop attributes', () async {
    final rows = await db.rawQuery(
        "SELECT p.canonical_name, c.crop_role, c.edible_part, c.sowing_season "
        "FROM plants p JOIN plant_crops c ON c.plant_id = p.id "
        "WHERE p.canonical_name LIKE 'Abelmoschus esculentus%'");
    expect(rows, isNotEmpty, reason: 'okra is a curated food crop');
    final okra = rows.first;
    expect(okra['crop_role'], isNotEmpty);
    expect(okra['edible_part'], isNotEmpty);
    expect(okra['sowing_season'], isNotEmpty,
        reason: 'Indian practice distinguishes kharif, rabi and summer');
  });

  test('food crops are tagged as food crops and vegetables', () async {
    final veg = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM plant_category_map m "
        "JOIN plant_categories c ON c.id = m.category_id "
        "WHERE c.code = 'VEGETABLE'");
    expect((veg.first['n'] as int), greaterThan(50));

    final okra = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM plants p "
        "JOIN plant_category_map m ON m.plant_id = p.id "
        "JOIN plant_categories c ON c.id = m.category_id "
        "WHERE p.canonical_name LIKE 'Abelmoschus esculentus%' "
        "AND c.code IN ('FOOD_CROP','VEGETABLE')");
    expect(okra.first['n'], greaterThanOrEqualTo(2),
        reason: 'a vegetable is both a food crop and a vegetable');
  });

  test('non-edible groups such as ornamental and tree are populated', () async {
    for (final code in ['ORNAMENTAL', 'TREE', 'WEED']) {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM plant_category_map m '
          'JOIN plant_categories c ON c.id = m.category_id '
          'WHERE c.code = ?',
          [code]);
      expect((rows.first['n'] as int), greaterThan(10),
          reason: '$code must hold real species, not be an empty shell');
    }
  });

  test('categories never claim a species the import does not have', () async {
    final bad = (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM plant_category_map m '
            'LEFT JOIN plants p ON p.id = m.plant_id WHERE p.id IS NULL'))
        .first['n'] as int;
    expect(bad, 0);
  });
}