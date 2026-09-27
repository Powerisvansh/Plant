import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../../core/constants.dart';
import '../../models/analysis_models.dart';

/// Core on-device visual analysis engine.
///
/// Everything here is deterministic, documented and reproducible:
///  - RGB/HSL colour analysis for chlorosis (yellow), necrosis (brown)
///  - a Variance-of-Laplacian focus estimate for the blur check
///  - flood-fill connected components to locate leaves and damage clusters
///  - a clearly bounded experimental Health Index (NOT a scientific standard)
///
/// Screens output only. The engine never claims to confirm a biological
/// diagnosis from a single photo.
class AnalysisEngine {
  AnalysisEngine._();

  /// Downscale + normalise so all downstream work is fast.
  static img.Image prepare(img.Image source) {
    var im = source;
    final longest = math.max(im.width, im.height);
    if (longest > AppConstants.analysisMaxDimension) {
      final scale = AppConstants.analysisMaxDimension / longest;
      im = img.copyResize(
        im,
        width: (im.width * scale).round(),
        height: (im.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return im;
  }

  // ------------------------------------------------------------------ public

  /// Quality gate: dark / blurry / too small / no plant / obstructed.
  static ImageQualityReport checkQuality(img.Image prepared) {
    final grid = _Grid.build(prepared);
    final brightness = grid.meanLuma;
    final blur = _laplacianVariance(prepared);
    final plant = grid.plantCoverage;

    final issues = <QualityIssue>[];
    if (brightness < 0.16) issues.add(QualityIssue.tooDark);
    if (blur < 14) issues.add(QualityIssue.tooBlurry);
    if (prepared.width < 220 || prepared.height < 220) {
      issues.add(QualityIssue.tooSmall);
    }
    if (plant < 0.02) issues.add(QualityIssue.plantNotDetected);
    if (grid.dominantColorCoverage > 0.55 && plant < 0.06) {
      issues.add(QualityIssue.extremeObstruction);
    }

    return ImageQualityReport(
      usable: issues.isEmpty,
      issues: issues,
      brightness: brightness,
      blurScore: blur,
    );
  }

  /// Full per-image measurement pass.
  static LeafAnalysis analyzeSingle(img.Image prepared) {
    final grid = _Grid.build(prepared);
    final total = grid.width * grid.height;

    final components = _plantComponents(grid);
    final damage = _damageClusters(grid);

    double medianAspect = 0.0;
    double medianRoundness = 0.0;
    final aspects = <double>[];
    final roundness = <double>[];
    for (final c in components) {
      if (c.area * _Grid.step2 < 60) continue;
      final bw = c.maxX - c.minX;
      final bh = c.maxY - c.minY;
      if (bw < 6 || bh < 6) continue;
      aspects.add((math.max(bw, bh) / math.max(1, math.min(bw, bh)))
          .clamp(1.0, 15.0)
          .toDouble());
      final maxDim = math.max(bw, bh);
      final areaPx = c.area * _Grid.step2 * _Grid.step2;
      roundness.add((4 * areaPx) / (math.pi * maxDim * maxDim));
    }
    if (aspects.isNotEmpty) {
      aspects.sort();
      roundness.sort();
      medianAspect = aspects[aspects.length ~/ 2];
      medianRoundness = roundness[roundness.length ~/ 2];
    }

    return LeafAnalysis(
      yellowFraction: grid.yellow / total,
      brownFraction: grid.brown / total,
      greenFraction: grid.green / total,
      darkFraction: grid.dark / total,
      spottedFraction: grid.spots / total,
      meanBrightness: grid.meanLuma,
      blurScore: _laplacianVariance(prepared),
      plantDetected: (grid.green + grid.yellow) > total * 0.02,
      plantCoverage: (grid.green + grid.yellow + grid.brown) / total,
      textureVariation:
          (grid.green + grid.yellow) > total * 0.02
              ? _textureVariation(prepared)
              : 0,
      leafAspectRatio: medianAspect,
      leafRoundness: medianRoundness,
      edgeDensity: grid.edgeDensity,
      evidence: _buildEvidence(prepared, components, damage, grid),
    );
  }

  /// Combine measurements from 1..4 photos into one health screening.
  static HealthReport assess(List<LeafAnalysis> images) {
    if (images.isEmpty) {
      return const HealthReport(
        overallCondition: 'No image available',
        statements: [],
        observedIndicators: ['Nothing was analysed'],
        possibleCauses: [],
        uncertaintyExplanation:
            'Cannot screen without at least one usable photo.',
        nutrientNotes: [],
        safeCareGuidance: [
          'Add at least one sharp photo of the plant and its affected leaves.',
          'Check light, soil moisture and root health before treating anything.',
        ],
        safeMedicineGuidance: [
          'Do not use a product until the crop, plant and problem are confirmed against the label.',
          'No product dosage is displayed here; follow the label and local farm guidance.',
        ],
        warningFlags: [
          'Diagnosis is uncertain without a clear image.',
          'Do not guess chemicals or dose rates.',
        ],
      );
    }

    final active = images.where((a) => a.plantDetected).toList();
    if (active.isEmpty) {
      return const HealthReport(
        overallCondition: 'No plant detected',
        statements: ['The photos did not contain a clearly visible plant.'],
        observedIndicators: ['No plant pixels could be identified'],
        possibleCauses: [],
        uncertaintyExplanation:
            'Analysis cannot start because no plant was found in the photo.',
        nutrientNotes: [],
        safeCareGuidance: [
          'Take a closer photo of a whole leaf or the whole plant.',
          'Improve lighting and avoid blurry or heavily obstructed shots.',
        ],
        safeMedicineGuidance: [
          'No treatment recommendation is given without a clear plant image.',
          'Check the product label and local extension advice before applying anything.',
        ],
        warningFlags: [
          'No diagnosis is possible from this image yet.',
          'Do not estimate product or dose rates from a blurry photo.',
        ],
      );
    }

    double mean(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    double rel(double fraction, double cov) =>
        cov <= 0.01 ? 0 : (fraction / cov).clamp(0.0, 1.0);

    // Plant-relative shares (fraction of the visible plant tissue affected).
    final covMean = mean(active.map((a) => a.plantCoverage).toList());
    final yellow = mean(active.map((a) => rel(a.yellowFraction, a.plantCoverage)).toList());
    final brown = mean(active.map((a) => rel(a.brownFraction, a.plantCoverage)).toList());
    final spot = mean(active.map((a) => rel(a.spottedFraction, a.plantCoverage)).toList());
    final dark = mean(active.map((a) => a.darkFraction).toList());
    final texture = mean(active.map((a) => a.textureVariation).toList());

    final minGreen = active
        .map((a) => rel(a.greenFraction, a.plantCoverage))
        .reduce(math.min);
    final maxDamage = active
        .map((a) => rel(a.damagedFraction, a.plantCoverage))
        .reduce(math.max);

    final indicators = <String>[];
    if (yellow > 0.12) indicators.add('Yellow discoloration');
    if (brown > 0.12) indicators.add('Brown areas / lesions');
    if (spot > 0.10) indicators.add('Irregular leaf regions / spots');
    if (dark > 0.25) indicators.add('Dark or shadowed leaf regions');
    if (texture > 60) indicators.add('Unusual surface texture');
    if (indicators.isEmpty) indicators.add('No strong visible damage');

    final causes = _symptomFingerprint(
      yellow: yellow,
      brown: brown,
      spot: spot,
      dark: dark,
      minGreen: minGreen,
      maxDamage: maxDamage,
    );

    final nutrientNotes = <String>[];
    if (yellow >= 0.15) {
      nutrientNotes.add(
        'Yellowing between the veins can suggest a magnesium or iron issue; '
        'uniform yellowing of older leaves is more typical of nitrogen. '
        'Symptoms alone cannot confirm this.',
      );
    }
    if (brown >= 0.12) {
      nutrientNotes.add(
        'Brown edges can relate to potassium, over-feeding or watering '
        'stress. Confirm with soil and growing conditions before acting.',
      );
    }
    if (nutrientNotes.isEmpty) {
      nutrientNotes.add(
        'No nutrient-linked symptom was strong enough to mention here.',
      );
    }

    final safeCareGuidance = <String>{
      'Check soil moisture and drainage before changing anything else.',
      'Remove only clearly dead, severely damaged or heavily diseased leaves with clean tools.',
      'Improve air circulation and spacing around the plant to reduce stress and spread.',
      'Water at the soil level rather than wetting leaves unless the plant needs it for a specific reason.',
      'Do not apply chemical treatment until the exact plant and problem are checked against the product label.',
      'If symptoms are spreading or the plant is valuable, ask a local extension service or plant clinic for confirmation.',
    }.toList();

    final safeMedicineGuidance = <String>{
      'Use only a product label that is approved for the exact plant and problem.',
      'No dose rates are included here; all rate and timing decisions must follow the label and local extension advice.',
      'Check quarantine, re-entry and harvest restrictions before using any product.',
      'Never mix products unless the label explicitly allows it.',
    }.toList();

    final warningFlags = <String>{
      'This screening is not a confirmed diagnosis.',
      'Do not guess chemical strength, dilution or timing.',
      'If damage is spreading rapidly, get local agronomy or extension support.',
    }.toList();

    return HealthReport(
      overallCondition:
          _overallCondition(yellow, brown, spot, dark, covMean, images.length),
      statements: [
        'Based on ${active.length} of ${images.length} photo(s) with a visible plant.',
        ...indicators.take(2).map((i) => 'Observed: $i.'),
        if (causes.isNotEmpty)
          'Most likely explanation by visual pattern: ${causes.first.label}.',
      ],
      observedIndicators: indicators,
      possibleCauses: causes,
      uncertaintyExplanation:
          'This is an AI-assisted visual screening, not a laboratory '
          'diagnosis. Visible signs have several possible biological causes, '
          'so treat the suggestions below as hypotheses to verify.',
      nutrientNotes: nutrientNotes,
      safeCareGuidance: safeCareGuidance,
      safeMedicineGuidance: safeMedicineGuidance,
      warningFlags: warningFlags,
    );
  }

  /// Experimental PlantDoctor Health Index (0-100).
  ///
  /// Components (100 = ideal) and documented weights:
  ///  - color condition:      25%   (little chlorosis)
  ///  - visible damage:       30%   (low yellow+brown+spot)
  ///  - spot/lesion area:     20%   (clean leaf surface)
  ///  - leaf integrity:       15%   (good plant coverage)
  ///  - texture deviation:    10%   (consistent surface)
  static HealthIndex computeIndex(List<LeafAnalysis> images) {
    final active = images.where((a) => a.plantDetected).toList();
    if (active.isEmpty || images.isEmpty) {
      return const HealthIndex(
        score: 0,
        grade: HealthGrade.poor,
        components: {
          'Color condition': 0,
          'Visible damage': 0,
          'Spot area': 0,
          'Leaf integrity': 0,
          'Texture': 0,
        },
      );
    }

    double mean(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    // Color/damage/spot are measured on the PLANT TISSUE, not the frame:
    // a small plant that is half-yellow should not score better than a large
    // one. Fractions are normalised by plant coverage before scoring.
    double rel(double fraction, double cov) =>
        cov <= 0.01 ? 0 : (fraction / cov).clamp(0.0, 1.0);

    final color = 100 *
        (1 - mean(active.map((a) => rel(a.yellowFraction, a.plantCoverage)).toList()) / 0.45);
    final damage = 100 *
        (1 - mean(active.map((a) => rel(a.damagedFraction, a.plantCoverage)).toList()) / 0.4);
    final spot = 100 *
        (1 - mean(active.map((a) => rel(a.spottedFraction, a.plantCoverage)).toList()) / 0.25);
    final integrity = 100 *
        (mean(active.map((a) => a.plantCoverage).toList()).clamp(0.05, 0.7) / 0.7);
    final texture = 100 *
        (1 - mean(active.map((a) => a.textureVariation).toList()).clamp(0.0, 120) / 120);

    final score = (0.25 * color +
            0.30 * damage +
            0.20 * spot +
            0.15 * integrity +
            0.10 * texture)
        .round()
        .clamp(0, 100)
        .toInt();

    return HealthIndex(
      score: score,
      grade: _gradeFor(score),
      components: {
        'Color condition': color.roundToDouble(),
        'Visible damage': damage.roundToDouble(),
        'Spot/lesion area': spot.roundToDouble(),
        'Leaf integrity': integrity.roundToDouble(),
        'Texture deviation': texture.roundToDouble(),
      },
    );
  }

  // ------------------------------------------------------------- internals

  static HealthGrade _gradeFor(int score) {
    if (score >= 85) return HealthGrade.excellent;
    if (score >= 70) return HealthGrade.good;
    if (score >= 50) return HealthGrade.needsAttention;
    if (score >= 30) return HealthGrade.concerning;
    return HealthGrade.poor;
  }

  static String _overallCondition(
    double yellow,
    double brown,
    double spot,
    double dark,
    double covMean,
    int imageCount,
  ) {
    if (imageCount == 0) return 'No image available';
    if (covMean <= 0.01) return 'No plant detected';
    final damage = yellow + brown + spot;
    if (damage < 0.15 && yellow < 0.2 && spot < 0.12) return 'Looks healthy';
    if (damage < 0.28) return 'Minor differences';
    if (damage < 0.5) {
      return 'Needs attention';
    }
    if (dark > 0.4) return 'Poor visibility / needs attention';
    return 'Significant visible changes';
  }

  /// Maps observed signals to ranked, honest hypotheses.
  static List<CauseCandidate> _symptomFingerprint({
    required double yellow,
    required double brown,
    required double spot,
    required double dark,
    required double minGreen,
    required double maxDamage,
  }) {
    final out = <CauseCandidate>[];

    double clamp01(double v) => v.clamp(0.0, 1.0).toDouble();

    if (yellow >= 0.12) {
      out.add(CauseCandidate(
        label: 'Possible nutrient-related stress',
        confidence: clamp01(0.55 + yellow * 1.2),
        explanation:
            'Widespread yellowing (chlorosis) is a common but non-specific '
            'sign. It frequently relates to nutrient availability, watering '
            'or root conditions, and sometimes to leaf age.',
        nutrients: ['Nitrogen', 'Magnesium', 'Iron'],
      ));
      out.add(CauseCandidate(
        label: 'Possible watering / environmental stress',
        confidence: clamp01(0.40 + yellow * 0.8),
        explanation:
            'Over- or under-watering and poor light commonly produce '
            'yellowing. Check soil moisture and light before anything else.',
        nutrients: [],
      ));
    }

    if (brown >= 0.10 || spot >= 0.08) {
      out.add(CauseCandidate(
        label: 'Possible fungal-like leaf symptoms',
        confidence: clamp01(0.45 + (brown + spot) * 1.4),
        explanation:
            'Irregular brown areas and spots are consistent with several '
            'leaf-infecting fungi, but also with residue burns, pest damage '
            'and age. Identification of the organism is not possible from '
            'this photo alone.',
        nutrients: [],
      ));
    }
    if (brown >= 0.10) {
      out.add(CauseCandidate(
        label: 'Possible leaf burn / environmental damage',
        confidence: clamp01(0.30 + brown),
        explanation:
            'Brown tissue can come from sun scorch, heat or chemical '
            'exposure. Placement history matters here.',
        nutrients: [],
      ));
    }
    if (brown + spot >= 0.15 && minGreen < 0.55) {
      out.add(CauseCandidate(
        label: 'Possible pest damage',
        confidence: clamp01(0.30 + (brown + spot)),
        explanation:
            'Thinning, speckled or chewed-looking tissue is associated with '
            'pests. Inspect the underside of leaves and stems for insects.',
        nutrients: [],
      ));
    }
    if (dark >= 0.45 && yellow < 0.15) {
      out.add(CauseCandidate(
        label: 'Photo too dark to judge',
        confidence: clamp01(0.35 + dark * 0.4),
        explanation:
            'A large share of the photo is dark. Some leaves or symptoms may '
            'not have been visible at all during screening.',
        nutrients: [],
      ));
    }

    if (out.isEmpty) {
      out.add(const CauseCandidate(
        label: 'Healthy appearance',
        confidence: 0.6,
        explanation: 'No strong symptom pattern was detected in the photos.',
        nutrients: [],
      ));
    }

    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out.take(4).toList();
  }

  // --------------------------------------------------------- low-level math

  static double _luma(num r, num g, num b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

  /// Variance of Laplacian on a small grayscale version. Larger = sharper.
  /// Computed on a *nearest-neighbour* downscale so edges survive; the metric
  /// is calibrated on sharp vs blurred synthetic and real photos.
  static double _laplacianVariance(img.Image im) {
    final small = img.copyResize(
      im,
      width: 220,
      interpolation: img.Interpolation.nearest,
    );
    final g = img.grayscale(small);
    var sum = 0.0, sumSq = 0.0;
    var n = 0;
    for (var y = 1; y < g.height - 1; y++) {
      for (var x = 1; x < g.width - 1; x++) {
        final p = g.getPixel(x, y);
        final c = _luma(p.r, p.g, p.b);
        final lap = _lumaOf(g, x + 1, y) +
            _lumaOf(g, x - 1, y) +
            _lumaOf(g, x, y + 1) +
            _lumaOf(g, x, y - 1) -
            4 * c;
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    if (n == 0) return 0;
    final variance = (sumSq - (sum * sum) / n) / n;
    return math.sqrt(variance) * 0.55;
  }

  static double _lumaOf(img.Image im, int x, int y) {
    final p = im.getPixelSafe(x, y);
    return _luma(p.r, p.g, p.b);
  }

  static double _textureVariation(img.Image im) {
    var sum = 0.0;
    var count = 0;
    for (var y = 2; y < im.height - 2; y += 6) {
      for (var x = 2; x < im.width - 2; x += 6) {
        var localSum = 0.0, localSq = 0.0, n = 0;
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final p = im.getPixel(x + dx, y + dy);
            final v = _luma(p.r, p.g, p.b);
            localSum += v;
            localSq += v * v;
            n++;
          }
        }
        final variance = (localSq - localSum * localSum / n) / n;
        sum += math.sqrt(variance);
        count++;
      }
    }
    return count == 0 ? 0 : (sum / count) * 0.35;
  }

  /// Builds the evidence boxes drawn over the photo (normalised 0..1 space).
  static List<EvidenceRegion> _buildEvidence(
    img.Image im,
    List<_Component> components,
    List<_DamageCluster> damage,
    _Grid grid,
  ) {
    final w = im.width, h = im.height;
    final out = <EvidenceRegion>[];
    if (w == 0 || h == 0) return out;

    for (final c in components.take(4)) {
      out.add(EvidenceRegion(
        rect: _normRect(c.minX, c.minY, c.maxX, c.maxY, w, h),
        kind: 'leaf-area',
        score: (grid.green + grid.yellow + grid.brown) /
            (grid.width * grid.height) *
            1.0,
      ));
    }

    for (final d in damage.take(5)) {
      final totalPx = d.area * _Grid.step2 * _Grid.step2;
      if (totalPx < 50) continue;
      out.add(EvidenceRegion(
        rect: _normRect(d.minX, d.minY, d.maxX, d.maxY, w, h),
        kind: d.kind,
        score: (totalPx / (w * h)).clamp(0.0, 1.0).toDouble(),
      ));
    }
    return out;
  }

  static Rect _normRect(num l, num t, num r, num b, int w, int h) {
    const pad = 6;
    return Rect.fromLTRB(
      ((l * _Grid.step2 - pad) / w).clamp(0.0, 1.0).toDouble(),
      ((t * _Grid.step2 - pad) / h).clamp(0.0, 1.0).toDouble(),
      ((r * _Grid.step2 + pad) / w).clamp(0.0, 1.0).toDouble(),
      ((b * _Grid.step2 + pad) / h).clamp(0.0, 1.0).toDouble(),
    );
  }

  // ------------------------------------------------------------- flood-fill

  /// Connected components of plant pixels (4-connectivity) on the grid.
  static List<_Component> _plantComponents(_Grid grid) {
    final gw = grid.width, gh = grid.height;
    final visited = List<bool>.filled(gw * gh, false);
    final out = <_Component>[];

    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        if (visited[y * gw + x] || !grid.plantAt(x, y)) continue;
        var area = 0;
        var minX = x, maxX = x, minY = y, maxY = y;
        final queue = <int>[y * gw + x];
        visited[y * gw + x] = true;
        while (queue.isNotEmpty) {
          final idx = queue.removeLast();
          final cx = idx % gw;
          final cy = idx ~/ gw;
          area++;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;
          for (final (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]) {
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            final nIdx = ny * gw + nx;
            if (!visited[nIdx] && grid.plantAt(nx, ny)) {
              visited[nIdx] = true;
              queue.add(nIdx);
            }
          }
        }
        if (area >= 3) {
          out.add(_Component(
            area: area,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
          ));
        }
      }
    }
    out.sort((a, b) => b.area.compareTo(a.area));
    return out;
  }

  /// Yellow/brown clusters inside the plant mask, ranked by size.
  static List<_DamageCluster> _damageClusters(_Grid grid) {
    final gw = grid.width, gh = grid.height;
    final visited = List<bool>.filled(gw * gh, false);
    final out = <_DamageCluster>[];

    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        final l = grid.labelAt(x, y);
        if (visited[y * gw + x] || (l != _Label.yellow && l != _Label.brown)) {
          continue;
        }
        var area = 0, yCount = 0, bCount = 0;
        var minX = x, maxX = x, minY = y, maxY = y;
        final queue = <int>[y * gw + x];
        visited[y * gw + x] = true;
        while (queue.isNotEmpty) {
          final idx = queue.removeLast();
          final cx = idx % gw;
          final cy = idx ~/ gw;
          area++;
          final ll = grid.labelAt(cx, cy);
          if (ll == _Label.yellow) yCount++;
          if (ll == _Label.brown) bCount++;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;
          for (final (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]) {
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            final nIdx = ny * gw + nx;
            if (visited[nIdx]) continue;
            final nl = grid.labelAt(nx, ny);
            if (nl == _Label.yellow || nl == _Label.brown) {
              visited[nIdx] = true;
              queue.add(nIdx);
            }
          }
        }
        if (area >= 3) {
          out.add(_DamageCluster(
            area: area,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            yellowCount: yCount,
            brownCount: bCount,
            kind: yCount >= bCount ? 'yellow' : 'brown',
          ));
        }
      }
    }
    out.sort((a, b) => b.area.compareTo(a.area));
    return out;
  }
}

enum _Label { dark, green, yellow, brown, none }

/// Downsampled RGB + classification grid used by the measurements.
/// cell (x, y) corresponds to original pixel (x*step, y*step).
class _Grid {
  _Grid._(this.width, this.height, this._r, this._g, this._b, this._label);

  static const int step = 2;
  static const int step2 = 2;

  final int width;
  final int height;
  final List<List<int>> _r;
  final List<List<int>> _g;
  final List<List<int>> _b;
  final List<List<_Label>> _label;

  int green = 0;
  int yellow = 0;
  int brown = 0;
  int dark = 0;
  int spots = 0;
  double meanLuma = 0;

  factory _Grid.build(img.Image im) {
    final gw = (im.width / step).ceil();
    final gh = (im.height / step).ceil();
    final r = List.generate(gh, (_) => List<int>.filled(gw, 0));
    final g = List.generate(gh, (_) => List<int>.filled(gw, 0));
    final b = List.generate(gh, (_) => List<int>.filled(gw, 0));
    final label = List.generate(gh, (_) => List<_Label>.filled(gw, _Label.none));

    var lumaSum = 0.0;
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        final p = im.getPixelSafe(x * step, y * step);
        r[y][x] = p.r.toInt();
        g[y][x] = p.g.toInt();
        b[y][x] = p.b.toInt();
        label[y][x] = classify(p.r, p.g, p.b);
        lumaSum += _lumaOfPixel(p.r, p.g, p.b);
      }
    }

    final grid = _Grid._(gw, gh, r, g, b, label)
      ..meanLuma = lumaSum / (gw * gh) / 255.0;

    // Count labels + detect interior spots/lesions (non-green regions fully
    // surrounded by healthy green tissue).
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        switch (grid._label[y][x]) {
          case _Label.green:
            grid.green++;
          case _Label.yellow:
            grid.yellow++;
          case _Label.brown:
            grid.brown++;
          case _Label.dark:
            grid.dark++;
          case _Label.none:
            break;
        }
        final l = grid._label[y][x];
        if (l != _Label.green &&
            l != _Label.dark &&
            _isInteriorDamage(grid, x, y)) {
          grid.spots++;
        }
      }
    }
    return grid;
  }

  bool plantAt(int x, int y) {
    final l = _label[y][x];
    return l == _Label.green || l == _Label.yellow || l == _Label.brown;
  }

  _Label labelAt(int x, int y) => _label[y][x];

  double get plantCoverage => (green + yellow + brown) / (width * height);

  /// If a single off-plant colour covers most of the frame, something may be
  /// blocking the lens (e.g. a finger or case).
  double get dominantColorCoverage {
    const buckets = 24;
    final counts = List<int>.filled(buckets, 0);
    var n = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (_label[y][x] != _Label.none) continue;
        final rr = _r[y][x], gg = _g[y][x], bb = _b[y][x];
        final maxC = math.max(math.max(rr, gg), bb);
        final minC = math.min(math.min(rr, gg), bb);
        final delta = maxC - minC;
        if (delta < 8) continue; // near-grey background is fine
        var hB = 0.0;
        if (maxC == rr) {
          hB = 60 * ((((gg - bb) / delta)) % 6);
        } else if (maxC == gg) {
          hB = 60 * ((((bb - rr) / delta) + 2));
        } else {
          hB = 60 * ((((rr - gg) / delta) + 4));
        }
        if (hB < 0) hB += 360;
        counts[((hB / 360) * buckets).floor().clamp(0, buckets - 1).toInt()]++;
        n++;
      }
    }
    if (n == 0) return 0;
    var maxCount = 0;
    for (final c in counts) {
      if (c > maxCount) maxCount = c;
    }
    return maxCount / n;
  }

  /// Fraction of plant pixels sitting directly next to a background/boundary
  /// pixel - a rough proxy for how "veined" / lobed the foliage is.
  double get edgeDensity {
    final gw = width, gh = height;
    if (gw < 3 || gh < 3) return 0;
    var edges = 0, n = 0;
    for (var y = 0; y < gh; y += 2) {
      for (var x = 0; x < gw; x += 2) {
        if (!plantAt(x, y)) continue;
        n++;
        final right = x + 1 < gw ? plantAt(x + 1, y) : false;
        final down = y + 1 < gh ? plantAt(x, y + 1) : false;
        if (!right || !down) edges++;
      }
    }
    return n == 0 ? 0 : edges / n * 100;
  }

  static double _lumaOfPixel(num r, num g, num b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

  static _Label classify(num r, num g, num b) {
    final maxC = math.max(math.max(r, g), b) / 255.0;
    final minC = math.min(math.min(r, g), b) / 255.0;
    final delta = maxC - minC;
    final v = maxC;
    if (v < 0.18) return _Label.dark;

    double h = 0;
    if (delta < 0.02) {
      h = 0;
    } else if (maxC == r / 255.0) {
      h = 60 * ((((g - b) / 255.0) / delta) % 6);
    } else if (maxC == g / 255.0) {
      h = 60 * ((((b - r) / 255.0) / delta) + 2);
    } else {
      h = 60 * ((((r - g) / 255.0) / delta) + 4);
    }
    if (h < 0) h += 360;
    final s = maxC < 0.001 ? 0 : delta / maxC;

    if (s >= 0.12 && v <= 0.95) {
      // Yellow (chlorotic) tissue first: lime-green leaves (h ~ 60-90) read
      // as "yellow-ish" - the earliest, most common visible stress sign.
      if (h >= 40 && h <= 90 && s >= 0.22 && v >= 0.33) return _Label.yellow;
      if (h >= 90 && h <= 170) return _Label.green;
      if ((h <= 42 || h >= 330) && s >= 0.12 && v <= 0.52) {
        return _Label.brown;
      }
    }
    return _Label.none;
  }

  /// Interior damage tiles: non-green regions fully surrounded by healthy-
  /// looking green tissue. These are the "irregular spots" of a screening.
  /// Diffuse yellowing (chlorosis) floods the leaf, so yellow only counts as
  /// a spot when it is a tight island (3 of 4 orthogonal neighbours green);
  /// brown lesions count at 2 of 4.
  static bool _isInteriorDamage(_Grid grid, int x, int y) {
    final l = grid._label[y][x];
    if (l == _Label.green || l == _Label.dark) return false;
    final gw = grid.width, gh = grid.height;
    final coords = [(x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)];
    var greenAround = 0, n = 0;
    for (final (nx, ny) in coords) {
      if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
      n++;
      if (grid._label[ny][nx] == _Label.green) greenAround++;
    }
    if (n < 3) return false;
    return l == _Label.yellow ? greenAround >= 3 : greenAround >= 2;
  }
}

class _Component {
  const _Component({
    required this.area,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int area;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
}

class _DamageCluster {
  const _DamageCluster({
    required this.area,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.yellowCount,
    required this.brownCount,
    required this.kind,
  });

  final int area;
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final int yellowCount;
  final int brownCount;
  final String kind;
}