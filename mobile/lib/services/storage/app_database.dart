import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../core/constants.dart';
import '../../models/scan_models.dart';

/// Opens (or creates) the local SQLite database and owns its schema.
///
/// Schema is trivially small: `scans` and `plants` tables. List columns are
/// stored as JSON text.
class AppDatabase {
  AppDatabase._(this._db);

  final sqflite.Database _db;

  static Future<AppDatabase> open() async {
    final dir = await sqflite.getDatabasesPath();
    final path = p.join(dir, StorageKeys.dbName);
    final db = await sqflite.openDatabase(
      path,
      version: StorageKeys.dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scans (
            id TEXT PRIMARY KEY,
            created_at INTEGER NOT NULL,
            thumb_path TEXT,
            image_paths TEXT,
            image_subjects TEXT,
            plant_guess TEXT,
            scientific_guess TEXT,
            id_confidence REAL,
            id_uncertain INTEGER,
            health_index INTEGER,
            condition TEXT,
            indicators TEXT,
            causes TEXT,
            follow_up TEXT,
            notes TEXT,
            saved_plant_id TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE plants (
            id TEXT PRIMARY KEY,
            name TEXT,
            species TEXT,
            created_at INTEGER NOT NULL,
            notes TEXT,
            health_index INTEGER,
            photo TEXT
          )
        ''');
      },
    );
    return AppDatabase._(db);
  }

  static String encodeList(List<String> list) =>
      jsonEncode(list);

  static List<String> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    return v.map((e) => e.toString()).toList();
  }

  // --------------------------------------------------------------- scans

  Future<void> insertScan(ScanRecord s) async {
    await _db.insert('scans', s.toMap()
      ..['image_paths'] = encodeList(s.imagePaths)
      ..['image_subjects'] = encodeList(s.imageSubjects)
      ..['indicators'] = encodeList(s.observedIndicators)
      ..['causes'] = encodeList(s.causeLabels));
  }

  Future<List<ScanRecord>> allScans() async {
    final rows = await _db.query('scans', orderBy: 'created_at DESC');
    return rows.map(ScanRecord.fromMap).toList();
  }

  Future<ScanRecord?> scanById(String id) async {
    final rows = await _db.query('scans', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ScanRecord.fromMap(rows.first);
  }

  Future<void> updateScanNotes(String id, String notes) async {
    await _db.update('scans', {'notes': notes}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> attachScanToPlant(String scanId, String plantId) async {
    await _db.update(
      'scans',
      {'saved_plant_id': plantId},
      where: 'id = ?',
      whereArgs: [scanId],
    );
  }

  Future<void> deleteScan(String id) async {
    await _db.delete('scans', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ScanRecord>> scansForPlant(String plantId) async {
    final rows = await _db.query(
      'scans',
      where: 'saved_plant_id = ?',
      whereArgs: [plantId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ScanRecord.fromMap).toList();
  }

  // --------------------------------------------------------------- plants

  Future<void> insertPlant(SavedPlant plant) async {
    await _db.insert('plants', plant.toMap());
  }

  Future<List<SavedPlant>> allPlants() async {
    final rows = await _db.query('plants', orderBy: 'created_at DESC');
    return rows.map(SavedPlant.fromMap).toList();
  }

  Future<void> updatePlant(
    String id, {
    String? name,
    String? species,
    String? notes,
    int? healthIndex,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (species != null) data['species'] = species;
    if (notes != null) data['notes'] = notes;
    if (healthIndex != null) data['health_index'] = healthIndex;
    if (data.isEmpty) return;
    await _db.update('plants', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePlant(String id) async {
    await _db.delete('plants', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> detachScansFromPlant(String plantId) async {
    await _db.update(
      'scans',
      {'saved_plant_id': null},
      where: 'saved_plant_id = ?',
      whereArgs: [plantId],
    );
  }

  Future<void> close() => _db.close();
}