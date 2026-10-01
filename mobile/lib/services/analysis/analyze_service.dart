import 'package:image/image.dart' as img;

import '../../models/analysis_models.dart';
import '../../models/scan_models.dart';
import '../identification/identification_service.dart';
import '../image_files.dart';
import '../ml/plant_model.dart';
import '../synthetic_samples.dart';
import 'analysis_engine.dart';

/// One input photo for a scan.
typedef ScanInput = ({String path, ImageSubjectType subject});

/// Orchestrates the full analysis pipeline for 1-4 photos.
///
///   decode -> downscale -> save working copy -> quality gate -> measure
///   -> on-device model (when bundled) -> combine -> health index
///
/// Identification is model-first; the leaf-shape screening is only a clearly
/// labelled fallback, and neither path may invent a species name.
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

    // Load the bundled model once; null when this build ships no model.
    final model = await PlantModelService.load();
    final modelResults = <List<ModelPrediction>?>[];

    for (var i = 0; i < inputs.length; i++) {
      final input = inputs[i];
      final bytes = await files.readAsBytes(input.path);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException(
          'The selected image could not be read as a photo.',
        );
      }
      final prepared = AnalysisEngine.prepare(decoded);
      final workingPath = await files.saveWorking(scanId, i, prepared);
      workingPaths.add(workingPath);
      originalPaths.add(input.path);
      subjects.add(input.subject);

      final report = AnalysisEngine.checkQuality(prepared);
      quality.add(report);
      perImage.add(AnalysisEngine.analyzeSingle(prepared));

      // First non-plant gate: photos with no plant-like pixels never reach the
      // classifier. (The model's own confidence floor is the second gate.)
      if (model != null) {
        try {
          modelResults.add(
            report.issues.contains(QualityIssue.plantNotDetected)
                ? null
                : model.topK(prepared, k: 5),
          );
        } catch (_) {
          modelResults.add(null);
        }
      }
    }

    final health = AnalysisEngine.assess(perImage);
    final index = AnalysisEngine.computeIndex(perImage);
    final outcome = IdentificationService.combine(
      perImage: perImage,
      qualityReports: quality,
      modelResults: modelResults.isEmpty
          ? List<List<ModelPrediction>?>.filled(perImage.length, null)
          : modelResults,
    );

    sw.stop();

    return AnalysisBundle(
      perImage: perImage,
      health: health,
      index: index,
      identification: outcome.plant,
      conditionScreen: outcome.condition,
      originalPaths: originalPaths,
      workingPaths: workingPaths,
      subjects: subjects,
      qualityReports: quality,
      measuredMetrics: {
        'inference_ms': sw.elapsedMilliseconds,
        'images': perImage.length,

        'model_loaded': model != null ? 1 : 0,
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
