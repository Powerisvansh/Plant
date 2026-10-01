import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../models/knowledge_models.dart';

/// Read-only access to the bundled offline knowledge base.
///
/// The database ships inside the app as `assets/plant_knowledge/plantdoctor.db`
/// and is copied into the app's documents directory on first run. It is opened
/// read-only: the knowledge base is a build artefact, and nothing in the app
/// may edit it. The user's own scans and saved plants live in a separate
/// database.
///
/// Two rules shape this class:
///
///  * the whole database is never loaded into memory - every read is an indexed
///    query with a LIMIT, and search uses the FTS5 index;
///  * a section with no rows returns an empty list or null, never a
///    substituted or generated value, so the UI can state what is missing.
class KnowledgeRepository {
  KnowledgeRepository._(this._db, this.manifest);

  final sqflite.Database _db;
  final KnowledgeManifest manifest;

  static const String assetPath = 'assets/plant_knowledge/plantdoctor.db';
  static const String localFileName = 'plantdoctor_knowledge.db';

  static KnowledgeRepository? _instance;
  static Object? lastError;

  static KnowledgeRepository? get instance => _instance;
  static bool get isAvailable => _instance != null;

  /// Versions and counts read from the `meta` table of the shipped database.
  static Future<KnowledgeRepository> open() async {
    if (_instance != null) return _instance!;
    try {
      final path = await _materialise();
      final db = await sqflite.openDatabase(
        path,
        readOnly: true,
        singleInstance: true,
      );
      final manifest = await _readManifest(db);
      _instance = KnowledgeRepository._(db, manifest);
      lastError = null;
      return _instance!;
    } catch (error) {
      lastError = error;
      rethrow;
    }
  }

  static Future<void> close() async {
    await _instance?._db.close();
    _instance = null;
  }

  /// Copies the bundled asset out of the APK on first run.
  ///
  /// The asset path changes whenever the knowledge base is rebuilt, so the
  /// bundle is re-copied whenever the database version differs from the copy
  /// already on disk. That keeps a shipped update from being shadowed by a
  /// stale local file.
  static Future<String> _materialise() async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File(p.join(dir.path, localFileName));
    final stamp = File(p.join(dir.path, '$localFileName.version'));

    final assetBytes = await rootBundle.load(assetPath);
    final assetVersion = _versionFromBytes(assetBytes);

    if (await target.exists() && await stamp.exists()) {
      final existing = (await stamp.readAsString()).trim();
      if (existing == assetVersion) return target.path;
    }

    await target.writeAsBytes(assetBytes.buffer.asUint8List(), flush: true);
    await stamp.writeAsString(assetVersion, flush: true);
    return target.path;
  }

  /// A cheap content fingerprint so the copy step can tell whether the bundled
  /// database changed. Length plus a hash of the head and tail avoids reading
  /// the whole file twice on every launch.
  static String _versionFromBytes(ByteData bytes) {
    final length = bytes.lengthInBytes;
    var hash = 0x811c9dc5;
    final sample = <int>[
      for (var i = 0; i < 64 && i < length; i++) bytes.getUint8(i),
      for (var i = (length - 64).clamp(0, length); i < length; i++)
        bytes.getUint8(i),
    ];
    for (final byte in sample) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '$length-$hash';
  }

  static Future<KnowledgeManifest> _readManifest(sqflite.Database db) async {
    final rows = await db.query('meta');
    final map = <String, String>{
      for (final row in rows) '${row['key']}': '${row['value']}',
    };
    int countOf(String table) => int.tryParse(map['count.$table'] ?? '') ?? 0;
    return KnowledgeManifest(
      dataRelease: map['data_release'],
      schemaVersion: int.tryParse(map['schema_version'] ?? ''),
      databaseVersion: int.tryParse(map['database_version'] ?? ''),
      buildDate: map['build_date'],
      plantCount: countOf('plants'),
      diseaseCount: countOf('diseases'),
      pestCount: countOf('pests'),
      deficiencyCount: countOf('nutrient_deficiencies'),
      stressCount: countOf('environmental_stresses'),
      treatmentCount: countOf('treatments'),
      preventionCount: countOf('prevention_methods'),
      toxicityCount: countOf('toxicity_profiles'),
      sourceCount: countOf('sources'),
    );
  }

  Future<List<Map<String, Object?>>> _query(
    String sql, [
    List<Object?>? args,
  ]) => _db.rawQuery(sql, args);

  /// Tables that are part of the current schema but ship with zero rows, or
  /// that a later release may drop. Queried behind an existence check so an
  /// absent table degrades to "no data" instead of throwing at the user.
  final Set<String> _knownTables = <String>{};

  Future<bool> _hasTable(String name) async {
    if (_knownTables.isEmpty) {
      final rows = await _query(
        "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
      );
      _knownTables.addAll(rows.map((r) => '${r['name']}'));
    }
    return _knownTables.contains(name);
  }

  Future<List<Map<String, Object?>>> _queryIfPresent(
    String table,
    String sql, [
    List<Object?>? args,
  ]) async {
    if (!await _hasTable(table)) return const [];
    try {
      return await _query(sql, args);
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------------------ plants

  static const String _plantColumns = '''
    p.id, p.slug, p.scientific_name, p.common_name, p.canonical_name, p.genus,
    p.species, p.family, p.order_name, p.class_name, p.phylum, p.kingdom,
    p.authorship, p.taxonomic_status, p.description,
    p.identification_features, p.growth_habit, p.plant_height,
    p.toxicity_status, p.verification_status, p.last_verified
  ''';

  Future<List<String>> _vernacularNames(int plantId) async {
    final rows = await _query(
      "SELECT name FROM plant_names WHERE plant_id = ? AND name_type IN "
      "('vernacular','common') AND name IS NOT NULL AND trim(name) <> '' "
      "ORDER BY is_primary DESC, id LIMIT 12",
      [plantId],
    );
    return rows.map((r) => '${r['name']}').toList(growable: false);
  }

  Future<KnowledgePlant?> plantBySlug(String slug) async {
    final rows = await _query(
      'SELECT $_plantColumns FROM plants p WHERE p.slug = ? LIMIT 1',
      [slug],
    );
    if (rows.isEmpty) return null;
    return _toPlant(rows.first);
  }

  Future<KnowledgePlant?> plantById(int id) async {
    final rows = await _query(
      'SELECT $_plantColumns FROM plants p WHERE p.id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return _toPlant(rows.first);
  }

  /// Resolves the canonical binomial for a model class such as
  /// "Tomato" -> "Solanum lycopersicum". Used to attach a recognition result to
  /// a real knowledge record.
  Future<KnowledgePlant?> plantByScientificName(String scientificName) async {
    final rows = await _query(
      'SELECT $_plantColumns FROM plants p WHERE lower(p.canonical_name) = '
      'lower(?) LIMIT 1',
      [scientificName.trim()],
    );
    if (rows.isEmpty) return null;
    return _toPlant(rows.first);
  }

  Future<KnowledgePlant?> _toPlant(Map<String, Object?> row) async =>
      KnowledgePlant.fromRow(
        row,
        vernacularNames: await _vernacularNames(row['id']! as int),
      );

  /// Converts raw rows into plants, skipping any row that fails to map.
  Future<List<KnowledgePlant>> _plantsFrom(
    List<Map<String, Object?>> rows,
  ) async {
    final plants = await Future.wait(rows.map(_toPlant));
    return plants.whereType<KnowledgePlant>().toList(growable: false);
  }

  /// Free-text search over common, local, scientific and synonym names.
  ///
  /// Uses the FTS5 `plants_fts` index when the query looks like a word query,
  /// and falls back to indexed LIKE clauses for partial or punctuated input.
  /// Never scans the table.
  Future<List<KnowledgePlant>> search(String rawQuery, {int limit = 40}) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return const [];
    final capped = limit.clamp(1, 200);

    final fts = _ftsQuery(query);
    if (fts != null) {
      try {
        final rows = await _queryIfPresent(
          'plants_fts',
          'SELECT $_plantColumns FROM plants_fts f '
              'JOIN plants p ON p.id = f.plant_id '
              'WHERE plants_fts MATCH ? ORDER BY rank LIMIT ?',
          [fts, capped],
        );
        if (rows.isNotEmpty) {
          return await _plantsFrom(rows);
        }
      } catch (_) {
        // A malformed FTS expression must never break search; fall through.
      }
    }

    final like = '%${query.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final rows = await _query(
      'SELECT $_plantColumns FROM plants p WHERE '
      'p.common_name LIKE ? ESCAPE \'\\\' OR '
      'p.scientific_name LIKE ? ESCAPE \'\\\' OR '
      'p.canonical_name LIKE ? ESCAPE \'\\\' OR '
      'p.genus LIKE ? ESCAPE \'\\\' OR '
      'p.family LIKE ? ESCAPE \'\\\' OR '
      'p.id IN (SELECT plant_id FROM plant_names '
      '         WHERE name LIKE ? ESCAPE \'\\\' AND name_type <> \'scientific\') '
      'ORDER BY (p.common_name IS NULL OR p.common_name = \'\') ASC, '
      '         p.common_name COLLATE NOCASE, p.id LIMIT ?',
      [like, like, like, like, like, like, capped],
    );
    return _plantsFrom(rows);
  }

  /// Builds a safe FTS5 MATCH expression by quoting each token. Everything the
  /// user types is treated as a literal string, so a stray quote or operator
  /// cannot produce a syntax error or an unintended query.
  static String? _ftsQuery(String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll('"', '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '"$t"*').join(' AND ');
  }

  // -------------------------------------------------------------- retrieval

  Future<List<KnowledgeTrait>> traitsFor(int plantId) async {
    final rows = await _query(
      'SELECT trait, value FROM plant_characteristics WHERE plant_id = ? '
      'AND value IS NOT NULL AND trim(value) <> \'\' ORDER BY trait LIMIT 60',
      [plantId],
    );
    return rows
        .map((r) => KnowledgeTrait('${r['trait']}', '${r['value']}'))
        .toList(growable: false);
  }

  Future<List<KnowledgeDistribution>> distributionFor(int plantId) async {
    final rows = await _query(
      'SELECT region, kind FROM plant_distribution WHERE plant_id = ? '
      'AND region IS NOT NULL AND trim(region) <> \'\' ORDER BY region LIMIT 40',
      [plantId],
    );
    return rows
        .map(
          (r) => KnowledgeDistribution('${r['region']}', r['kind'] as String?),
        )
        .toList(growable: false);
  }

  Future<KnowledgeGrowth?> growthFor(int plantId) async {
    final rows = await _queryIfPresent(
      'plant_growth',
      'SELECT * FROM plant_growth WHERE plant_id = ? LIMIT 1',
      [plantId],
    );
    if (rows.isEmpty) return null;
    return KnowledgeGrowth.fromRow(rows.first);
  }

  /// Rooftop siting guidance, or null when the species has no record.
  ///
  /// Table-gated: an asset bundle predating the rooftop data has no such
  /// table, and a missing table must read as "no data" rather than throw.
  Future<KnowledgeRooftop?> rooftopFor(int plantId) async {
    final rows = await _queryIfPresent(
      'plant_rooftop',
      'SELECT * FROM plant_rooftop WHERE plant_id = ? LIMIT 1',
      [plantId],
    );
    if (rows.isEmpty) return null;
    return KnowledgeRooftop.fromRow(rows.first);
  }

  Future<List<KnowledgeDisease>> diseasesFor(int plantId) async {
    final rows = await _query(
      'SELECT d.* FROM diseases d '
      'JOIN plant_diseases pd ON pd.disease_id = d.id '
      'WHERE pd.plant_id = ? ORDER BY d.name LIMIT 60',
      [plantId],
    );
    return rows.map((r) => KnowledgeDisease.fromRow(r)).toList(growable: false);
  }

  Future<List<KnowledgePest>> pestsFor(int plantId) async {
    final rows = await _query(
      'SELECT pe.* FROM pests pe '
      'JOIN plant_pests pp ON pp.pest_id = pe.id '
      'WHERE pp.plant_id = ? ORDER BY pe.name LIMIT 60',
      [plantId],
    );
    return rows.map((r) => KnowledgePest.fromRow(r)).toList(growable: false);
  }

  Future<List<KnowledgeDeficiency>> deficienciesFor(int plantId) async {
    final linked = await _queryIfPresent(
      'plant_nutrient_deficiencies',
      'SELECT nd.* FROM nutrient_deficiencies nd '
          'JOIN plant_nutrient_deficiencies pnd ON pnd.nutrient_id = nd.id '
          'WHERE pnd.plant_id = ? ORDER BY nd.nutrient LIMIT 40',
      [plantId],
    );
    if (linked.isNotEmpty) {
      return linked
          .map((r) => KnowledgeDeficiency.fromRow(r))
          .toList(growable: false);
    }
    // No per-plant link row exists in this release, so return the general
    // reference list. It is a reference, not a diagnosis: the UI labels it as
    // "general reference, not matched to this plant".
    final all = await _query(
      'SELECT * FROM nutrient_deficiencies ORDER BY nutrient LIMIT 40',
    );
    return all
        .map((r) => KnowledgeDeficiency.fromRow(r))
        .toList(growable: false);
  }

  Future<List<KnowledgeStress>> stressesFor(int plantId) async {
    final linked = await _queryIfPresent(
      'stress_symptoms',
      'SELECT es.* FROM environmental_stresses es '
          'JOIN stress_symptoms ss ON ss.stress_id = es.id '
          'WHERE ss.plant_id = ? ORDER BY es.name LIMIT 40',
      [plantId],
    );
    if (linked.isNotEmpty) {
      return linked
          .map((r) => KnowledgeStress.fromRow(r))
          .toList(growable: false);
    }
    final all = await _query(
      'SELECT * FROM environmental_stresses ORDER BY name LIMIT 40',
    );
    return all.map((r) => KnowledgeStress.fromRow(r)).toList(growable: false);
  }

  /// Label-gated treatment records. Returns an empty list in this release, and
  /// the caller must then show the "unavailable" notice.
  Future<List<KnowledgeTreatment>> treatmentsFor(int plantId) async {
    final rows = await _queryIfPresent(
      'treatment_plant_scope',
      'SELECT t.* FROM treatments t '
          'JOIN treatment_plant_scope s ON s.treatment_id = t.id '
          'WHERE s.plant_id = ? '
          'AND t.recommended_dosage IS NOT NULL AND trim(t.recommended_dosage) <> \'\' '
          'AND t.label_url IS NOT NULL AND trim(t.label_url) <> \'\' '
          'AND t.label_page_reference IS NOT NULL '
          'AND trim(t.label_page_reference) <> \'\' '
          'AND t.last_verified IS NOT NULL AND trim(t.last_verified) <> \'\' '
          'ORDER BY t.name LIMIT 40',
      [plantId],
    );
    return rows
        .map((r) => KnowledgeTreatment.fromRow(r))
        .toList(growable: false);
  }

  Future<List<KnowledgeTreatment>> treatmentsForDisease(int diseaseId) async {
    final rows = await _queryIfPresent(
      'treatment_targets',
      'SELECT t.* FROM treatments t '
          'JOIN treatment_targets tg ON tg.treatment_id = t.id '
          'WHERE tg.disease_id = ? '
          'AND t.recommended_dosage IS NOT NULL AND trim(t.recommended_dosage) <> \'\' '
          'AND t.label_url IS NOT NULL AND trim(t.label_url) <> \'\' '
          'AND t.last_verified IS NOT NULL AND trim(t.last_verified) <> \'\' '
          'ORDER BY t.name LIMIT 40',
      [diseaseId],
    );
    return rows
        .map((r) => KnowledgeTreatment.fromRow(r))
        .toList(growable: false);
  }

  Future<List<KnowledgeSource>> allSources() async {
    final rows = await _query('SELECT * FROM sources ORDER BY name LIMIT 50');
    return rows.map((r) => KnowledgeSource.fromRow(r)).toList(growable: false);
  }

  Future<List<KnowledgeSource>> sourcesFor(int plantId) async {
    final rows = await _queryIfPresent(
      'data_provenance',
      'SELECT DISTINCT s.* FROM sources s '
          'WHERE s.id IN (SELECT source_id FROM data_provenance '
          '               WHERE table_name = \'plants\' AND record_id = ?) '
          '   OR s.id = (SELECT source_id FROM plants WHERE id = ?) '
          'ORDER BY s.name LIMIT 20',
      [plantId, plantId],
    );
    return rows.map((r) => KnowledgeSource.fromRow(r)).toList(growable: false);
  }

  /// The full profile the specification's retrieval step asks for, in one call.
  Future<KnowledgeProfile?> profileForSlug(String slug) async {
    final plant = await plantBySlug(slug);
    if (plant == null) return null;
    return profileFor(plant);
  }

  Future<KnowledgeProfile> profileFor(KnowledgePlant plant) async {
    final results = await Future.wait<Object?>([
      traitsFor(plant.id),
      distributionFor(plant.id),
      growthFor(plant.id),
      diseasesFor(plant.id),
      pestsFor(plant.id),
      deficienciesFor(plant.id),
      stressesFor(plant.id),
      treatmentsFor(plant.id),
      sourcesFor(plant.id),
      rooftopFor(plant.id),
    ]);

    final growth = results[2] as KnowledgeGrowth?;
    return KnowledgeProfile(
      plant: plant,
      traits: results[0] as List<KnowledgeTrait>,
      distribution: results[1] as List<KnowledgeDistribution>,
      growth: growth,
      diseases: results[3] as List<KnowledgeDisease>,
      pests: results[4] as List<KnowledgePest>,
      deficiencies: results[5] as List<KnowledgeDeficiency>,
      stresses: results[6] as List<KnowledgeStress>,
      treatments: results[7] as List<KnowledgeTreatment>,
      sources: results[8] as List<KnowledgeSource>,
      rooftop: results[9] as KnowledgeRooftop?,
      toxicityStatus: plant.toxicityStatus,
      toxicityWarning: plant.toxicityKnown
          ? null
          : 'Do not consume or use medicinally without independent '
                'verification.',
      hasCultivationData: growth?.hasAnyData ?? false,
    );
  }

  // ---------------------------------------------------------------- lookups

  Future<List<KnowledgeDisease>> searchDiseases(
    String query, {
    int limit = 30,
  }) async => (await _searchBy('diseases', query, limit, const [
    'name',
    'pathogen_name',
    'description',
    'visual_symptoms',
    'symptoms',
  ])).map(KnowledgeDisease.fromRow).toList(growable: false);

  Future<List<KnowledgePest>> searchPests(
    String query, {
    int limit = 30,
  }) async => (await _searchBy('pests', query, limit, const [
    'name',
    'scientific_name',
    'description',
    'damage_symptoms',
    'appearance',
  ])).map(KnowledgePest.fromRow).toList(growable: false);

  Future<List<KnowledgeDeficiency>> searchDeficiencies(
    String query, {
    int limit = 30,
  }) async => (await _searchBy('nutrient_deficiencies', query, limit, const [
    'nutrient',
    'symbol',
    'description',
    'visual_signs',
  ])).map(KnowledgeDeficiency.fromRow).toList(growable: false);

  Future<List<KnowledgeStress>> searchStresses(
    String query, {
    int limit = 30,
  }) async => (await _searchBy('environmental_stresses', query, limit, const [
    'name',
    'description',
    'visual_signs',
  ])).map(KnowledgeStress.fromRow).toList(growable: false);

  Future<List<Map<String, Object?>>> _searchBy(
    String table,
    String query,
    int limit,
    List<String> columns,
  ) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final like = '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final clause = columns.map((c) => '$c LIKE ? ESCAPE \'\\\'').join(' OR ');
    final args = <Object?>[for (var i = 0; i < columns.length; i++) like];
    return _query('SELECT * FROM $table WHERE $clause ORDER BY name LIMIT ?', [
      ...args,
      limit.clamp(1, 200),
    ]);
  }

  /// A light-weight catalogue for the browse list, ordered so that species with
  /// a common name come first.
  Future<List<KnowledgePlant>> browse({int limit = 60, int offset = 0}) async {
    final rows = await _query(
      'SELECT $_plantColumns FROM plants p '
      'ORDER BY (p.common_name IS NULL OR p.common_name = \'\') ASC, '
      'p.common_name COLLATE NOCASE LIMIT ? OFFSET ?',
      [limit.clamp(1, 200), offset],
    );
    return _plantsFrom(rows);
  }
}

/// Version and row counts of the shipped knowledge base.
class KnowledgeManifest {
  const KnowledgeManifest({
    this.dataRelease,
    this.schemaVersion,
    this.databaseVersion,
    this.buildDate,
    this.plantCount = 0,
    this.diseaseCount = 0,
    this.pestCount = 0,
    this.deficiencyCount = 0,
    this.stressCount = 0,
    this.treatmentCount = 0,
    this.preventionCount = 0,
    this.toxicityCount = 0,
    this.sourceCount = 0,
  });

  final String? dataRelease;
  final int? schemaVersion;
  final int? databaseVersion;
  final String? buildDate;
  final int plantCount;
  final int diseaseCount;
  final int pestCount;
  final int deficiencyCount;
  final int stressCount;
  final int treatmentCount;
  final int preventionCount;
  final int toxicityCount;
  final int sourceCount;

  bool get hasVerifiedDosageData => treatmentCount > 0;
  bool get hasToxicityData => toxicityCount > 0;
}
