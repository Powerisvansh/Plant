import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns where photos live on disk.
///
/// Layout inside the app documents directory:
///   scans/{scanId}/original_{i}.{ext}
///   scans/{scanId}/working_{i}.jpg      (<= 640 px, used everywhere)
/// Every file is local; nothing is uploaded unless a future cloud service
/// explicitly says so in the UI.
class ImageFiles {
  ImageFiles({this._overrideRoot});

  final String? _overrideRoot;

  Future<String> resolveRoot() async {
    final root = _overrideRoot;
    if (root != null) return root;
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static void ensureDir(String path) {
    final d = Directory(path);
    if (!d.existsSync()) d.createSync(recursive: true);
  }

  Future<String> scanDir(String scanId) async {
    final root = await resolveRoot();
    final dir = p.join(root, 'scans', scanId);
    ensureDir(dir);
    return dir;
  }

  /// Copies a captured/picked file into the scan folder (original copy).
  Future<String> copyOriginal(String scanId, int index, String sourcePath) async {
    final dir = await scanDir(scanId);
    final ext = p.extension(sourcePath).isNotEmpty
        ? p.extension(sourcePath)
        : '.jpg';
    final dest = p.join(dir, 'original_$index$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// Saves a reduced-size working copy used for display + analysis.
  Future<String> saveWorking(String scanId, int index, img.Image working) async {
    final dir = await scanDir(scanId);
    final dest = p.join(dir, 'working_$index.jpg');
    await File(dest).writeAsBytes(img.encodeJpg(working, quality: 88));
    return dest;
  }

  Future<String> copyWorkingTo(String sourcePath, String scanId) async {
    return copyOriginal(scanId, 0, sourcePath);
  }

  Future<Uint8List> readAsBytes(String path) => File(path).readAsBytes();

  Future<void> deleteScanDir(String scanId) async {
    final dir = await scanDir(scanId);
    if (Directory(dir).existsSync()) {
      await Directory(dir).delete(recursive: true);
    }
  }

  /// Best-effort deletion of the original source file after import.
  static Future<void> tidyUp(String sourcePath) async {
    try {
      final f = File(sourcePath);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // The temporary file is not ours to fail on.
    }
  }

  /// Creates a pseudo random generator derived from a seed (stable across runs
  /// so the science-fair demo is reproducible).
  static math.Random seededRandom(int seed) => math.Random(seed);
}