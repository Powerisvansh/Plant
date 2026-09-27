import 'package:image/image.dart' as img;

import '../../models/analysis_models.dart';
import '../../models/scan_models.dart';
import '../image_files.dart';
import '../identification/plant_classifier.dart';
import '../synthetic_samples.dart';
import 'analysis_engine.dart';

/// One input photo for a scan.
typedef ScanInput = ({String path, ImageSubjectType subject});

/// Orchestrates the full analysis pipeline for 1-4 photos.
///
///   decode -> downscale -> save working copy -> quality gate -> measure
///   -> combine health -> health index -> morphology identification
class AnalyzeService {
  AnalyzeService(this.files);

  final ImageFiles files;

  /// Analyses real photo files stored on disk.
  Future<AnalysisBundle> analyze({
    required String scanId,
    required List<ScanInput> inputs,
  }) async {
    final sw = Stopwatch()..start();

    final perImage = <LeafAnalysis>[];
    final quality = <ImageQualityReport>[];
    final workingPaths = <String>[];
    final originalPaths = <String>[];
    final subjects = <ImageSubjectType>[];

    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final bytes = await files.readAsBytes(input.path);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException(
            'The selected image could not be read as a photo.');
      }
      final prepared = AnalysisEngine.prepare(decoded);
      final workingPath = await files.saveWorking(scanId, i, prepared);
      workingPaths.add(workingPath);
      originalPaths.add(input.path);
      subjects.add(input.subject);

      quality.add(AnalysisEngine.checkQuality(prepared));
      perImage.add(AnalysisEngine.analyzeSingle(prepared));
    }

    final health = AnalysisEngine.assess(perImage);
    final index = AnalysisEngine.computeIndex(perImage);
    final identification = PlantClassifier.classify(perImage);

    sw.stop();

    return AnalysisBundle(
      perImage: perImage,
      health: health,
      index: index,
      identification: identification,
      originalPaths: originalPaths,
      workingPaths: workingPaths,
      subjects: subjects,
      qualityReports: quality,
      measuredMetrics: {
        'inference_ms': sw.elapsedMilliseconds,
        'images': perImage.length,
      },
      inferenceMillis: sw.elapsedMilliseconds,
    );
  }

  /// Analyses named synthetic sample flags (science fair / experiment lab).
  Future<AnalysisBundle> analyzeSynthetic({
    required String scanId,
    required List<({String label, int seed, ImageSubjectType subject})> inputs,
  }) async {
    final mapped = <ScanInput>[];
    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final image = SyntheticSamplesFacade.byLabel(input.label, input.seed);
      final prepared = AnalysisEngine.prepare(image);
      final workPath = await files.saveWorking(scanId, i, prepared);
      mapped.add((path: workPath, subject: input.subject));
    }
    return analyze(scanId: scanId, inputs: mapped);
  }

  /// Runs the engine on an in-memory image (used by tests and the lab).
  static LeafAnalysis quickMeasure(img.Image prepared) =>
      AnalysisEngine.analyzeSingle(prepared);

  static ImageQualityReport quickQuality(img.Image prepared) =>
      AnalysisEngine.checkQuality(prepared);
}