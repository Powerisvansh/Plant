import 'package:flutter/foundation.dart';

import '../models/scan_models.dart';
import '../services/storage/app_database.dart';
import '../services/storage/settings_service.dart';

/// Holds app settings and re-persists them.
class SettingsController extends ChangeNotifier {
  SettingsController(this._service) : _settings = const AppSettings(
          showDisclaimers: true,
          scienceFairMode: false,
        );

  final SettingsService _service;
  AppSettings _settings;

  AppSettings get settings => _settings;

  Future<void> load() async {
    _settings = await _service.load();
    notifyListeners();
  }

  Future<void> setShowDisclaimers(bool value) async {
    _settings = _settings.copyWith(showDisclaimers: value);
    notifyListeners();
    await _service.save(_settings);
  }

  Future<void> setScienceFairMode(bool value) async {
    _settings = _settings.copyWith(scienceFairMode: value);
    notifyListeners();
    await _service.save(_settings);
  }
}

/// Cached list of saved scans (history).
class HistoryController extends ChangeNotifier {
  HistoryController(this._db);

  final AppDatabase _db;
  List<ScanRecord> _scans = const [];

  List<ScanRecord> get scans => _scans;

  bool get isLoaded => _loaded;
  bool _loaded = false;

  Future<void> load() async {
    _scans = await _db.allScans();
    _loaded = true;
    notifyListeners();
  }

  Future<void> addScan(ScanRecord scan) async {
    await _db.insertScan(scan);
    _scans = await _db.allScans();
    notifyListeners();
  }

  Future<void> updateNotes(String id, String notes) async {
    await _db.updateScanNotes(id, notes);
    final idx = _scans.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      final old = _scans[idx];
      _scans[idx] = ScanRecord(
        id: old.id,
        createdAt: old.createdAt,
        thumbPath: old.thumbPath,
        imagePaths: old.imagePaths,
        imageSubjects: old.imageSubjects,
        plantGuess: old.plantGuess,
        scientificGuess: old.scientificGuess,
        identificationConfidence: old.identificationConfidence,
        identificationUncertain: old.identificationUncertain,
        healthIndex: old.healthIndex,
        overallCondition: old.overallCondition,
        observedIndicators: old.observedIndicators,
        causeLabels: old.causeLabels,
        followUp: old.followUp,
        notes: notes,
        savedPlantId: old.savedPlantId,
      );
      notifyListeners();
    }
  }

  Future<void> attachToPlant(String scanId, String plantId) async {
    await _db.attachScanToPlant(scanId, plantId);
  }

  Future<void> deleteScan(String id) async {
    await _db.deleteScan(id);
    _scans = await _db.allScans();
    notifyListeners();
  }

  Future<List<ScanRecord>> scansForPlant(String plantId) =>
      _db.scansForPlant(plantId);
}

/// Cached list of the user's saved plants.
class PlantsController extends ChangeNotifier {
  PlantsController(this._db);

  final AppDatabase _db;
  List<SavedPlant> _plants = const [];

  List<SavedPlant> get plants => _plants;

  Future<void> load() async {
    _plants = await _db.allPlants();
    notifyListeners();
  }

  Future<SavedPlant> addPlant({
    required String name,
    required String species,
    required int healthIndex,
    required String photoPath,
    String notes = '',
  }) async {
    final plant = SavedPlant(
      id: _newId(),
      name: name,
      species: species,
      createdAt: DateTime.now(),
      notes: notes,
      currentHealthIndex: healthIndex,
      photoPath: photoPath,
    );
    await _db.insertPlant(plant);
    _plants = await _db.allPlants();
    notifyListeners();
    return plant;
  }

  Future<void> updateHealthIndex(String id, int index) async {
    await _db.updatePlant(id, healthIndex: index);
    _plants = await _db.allPlants();
    notifyListeners();
  }

  Future<void> updateNotes(String id, String notes) async {
    await _db.updatePlant(id, notes: notes);
    _plants = await _db.allPlants();
    notifyListeners();
  }

  Future<void> deletePlant(String id) async {
    await _db.detachScansFromPlant(id);
    await _db.deletePlant(id);
    _plants = await _db.allPlants();
    notifyListeners();
  }

  SavedPlant? byId(String id) {
    for (final p in _plants) {
      if (p.id == id) return p;
    }
    return null;
  }

  static String _newId() =>
      'p${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';
}

String newScanId() =>
    's${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';