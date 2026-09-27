import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Generates reproducible, labelled leaf images.
///
/// Used by:
///  - the Science Fair demo benchmark (measured, not fabricated)
///  - the Experiment Lab (side-by-side healthy vs affected)
///  - offline development/testing on machines without a camera
///
/// Everything is synthetic, so results are deterministic and shareable.
class SyntheticSamples {
  SyntheticSamples._();

  static const int width = 480;
  static const int height = 480;

  /// Renders a scene with one or more leaves. [effect] controls symptoms.
  static img.Image leaf({
    required int seed,
    SymptomEffect effect = SymptomEffect.healthy,
    List<double>? hueOffset,
    bool blur = false,
    double darkness = 1.0,
  }) {
    final rnd = math.Random(seed);
    final im = img.Image(width: width, height: height);

    // Gentle background gradient.
    for (var y = 0; y < height; y++) {
      final t = y / height;
      final base = 244 - (t * 14);
      for (var x = 0; x < width; x++) {
        final n = (rnd.nextDouble() - 0.5) * 6;
        final v = (base + n).round().clamp(0, 255);
        im.setPixelRgb(x, y, v, v + 2, v - 4);
      }
    }

    final leaves = effect == SymptomEffect.noPlant
        ? <_Leaf>[]
        : _leafLayout(rnd);
    for (final leaf in leaves) {
      _drawLeaf(im, rnd, leaf, effect);
    }

    if (effect == SymptomEffect.noPlant) {
      // Fill frame with the plain scene + a small grey object.
      for (var n = 0; n < 4; n++) {
        final cx = rnd.nextInt(width);
        final cy = rnd.nextInt(height);
        _drawBlob(im, rnd, cx.toDouble(), cy.toDouble(),
            (40 + rnd.nextInt(50)).toDouble(), const [128, 128, 132]);
      }
    }

    if (blur) {
      final blurred = img.gaussianBlur(im, radius: 3);
      return _applyDarkness(blurred, darkness);
    }
    return _applyDarkness(im, darkness);
  }

  static img.Image _applyDarkness(img.Image im, double darkness) {
    if (darkness >= 0.999) return im;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        im.setPixelRgb(
          x,
          y,
          (p.r * darkness).round(),
          (p.g * darkness).round(),
          (p.b * darkness).round(),
        );
      }
    }
    return im;
  }

  static List<_Leaf> _leafLayout(math.Random rnd) {
    final count = 1 + rnd.nextInt(2);
    final out = <_Leaf>[];
    for (var i = 0; i < count; i++) {
      out.add(_Leaf(
        cx: width * (0.30 + rnd.nextDouble() * 0.4),
        cy: height * (0.30 + rnd.nextDouble() * 0.4),
        rx: 62 + rnd.nextDouble() * 45,
        ry: 46 + rnd.nextDouble() * 26,
        rotation: rnd.nextDouble() * math.pi,
        greenHue: 100 + rnd.nextDouble() * 25,
      ));
    }
    return out;
  }

  static void _drawLeaf(
    img.Image im,
    math.Random rnd,
    _Leaf leaf,
    SymptomEffect effect,
  ) {
    final cos = math.cos(leaf.rotation);
    final sin = math.sin(leaf.rotation);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Inverse-rotate the point into leaf space.
        final dx = x - leaf.cx;
        final dy = y - leaf.cy;
        final lx = dx * cos + dy * sin;
        final ly = -dx * sin + dy * cos;
        final nx = lx / leaf.rx;
        final ny = ly / leaf.ry;
        final d2 = nx * nx + ny * ny;
        if (d2 > 1.0) continue;

        // Edge softness (slightly transparent margins).
        final edge = d2 > 0.78 ? (1.0 - d2) / 0.22 : 1.0;

        double h = leaf.greenHue;
        double s = 0.55 + (rnd.nextDouble() - 0.5) * 0.08;
        double v = 0.58 + (rnd.nextDouble() - 0.5) * 0.07;

        // Central vein: darker line along the long axis.
        final vein = (ny.abs() < 0.12) ? 0.06 : 0.0;

        // Secondary veins: faint darker arcs.
        final secVein = (math.sin(ny * math.pi * 3).abs() < 0.10 &&
                lx.abs() > leaf.rx * 0.1)
            ? 0.04
            : 0.0;

        // Symptom painting.
        switch (effect) {
          case SymptomEffect.healthy:
            break;
          case SymptomEffect.spotting:
            if (_chance(rnd, 0.15)) {
              h = 18 + rnd.nextDouble() * 12;
              s = 0.5;
              v = 0.28 + rnd.nextDouble() * 0.14;
            }
          case SymptomEffect.chlorosis:
            // Interveinal yellowing spread over much of the leaf.
            if (_chance(rnd, 0.5)) {
              h = h * 0.35 + 52 * 0.65;
              s = s.clamp(0.3, 1.0) * 1.25;
              v = v + 0.24;
            }
          case SymptomEffect.diseased:
            if (_chance(rnd, 0.06)) {
              h = 20 + rnd.nextDouble() * 18;
              s = 0.6;
              v = 0.22 + rnd.nextDouble() * 0.2;
            } else if (_chance(rnd, 0.08)) {
              h = 55;
              s = 0.72;
              v = 0.85;
            }
          case SymptomEffect.noPlant:
            break;
        }

        var rgb = _hsvToRgb(h, s.clamp(0.0, 1.0), v.clamp(0.0, 1.0));
        rgb = _scale(rgb, 1.0 - vein - secVein);
        rgb = _scale(rgb, edge);
        final grain = (rnd.nextDouble() - 0.5) * 10;
        final cr = (rgb[0] + grain).round().clamp(0, 255);
        final cg = (rgb[1] + grain).round().clamp(0, 255);
        final cb = (rgb[2] + grain).round().clamp(0, 255);
        im.setPixelRgb(x, y, cr, cg, cb);
      }
    }

    // Brown necrotic patch + scattered spots for 'diseased'.
    if (effect == SymptomEffect.diseased) {
      final px = leaf.cx + (rnd.nextDouble() - 0.5) * leaf.rx * 1.2;
      final py = leaf.cy + (rnd.nextDouble() - 0.5) * leaf.ry * 1.2;
      _drawBlob(im, rnd, px, py, leaf.rx * 0.35, const [105, 66, 34], count: 5);
    }
  }

  static bool _chance(math.Random rnd, double p) => rnd.nextDouble() < p;

  static List<int> _scale(List<int> c, double f) => [
        (c[0] * f).round(),
        (c[1] * f).round(),
        (c[2] * f).round(),
      ];

  static void _drawBlob(
    img.Image im,
    math.Random rnd,
    double cx,
    double cy,
    double radius,
    List<int> color, {
    int count = 1,
  }) {
    for (var b = 0; b < count; b++) {
      final bx = cx + (rnd.nextDouble() - 0.5) * radius * 0.6;
      final by = cy + (rnd.nextDouble() - 0.5) * radius * 0.6;
      final rr = radius * (0.4 + rnd.nextDouble() * 0.6);
      for (var y = (by - rr).floor(); y <= (by + rr).ceil(); y++) {
        for (var x = (bx - rr).floor(); x <= (bx + rr).ceil(); x++) {
          if (x < 0 || y < 0 || x >= width || y >= height) continue;
          final d = math.sqrt((x - bx) * (x - bx) + (y - by) * (y - by));
          final edge = (1 - d / rr).clamp(0.0, 1.0);
          if (edge <= 0) continue;
          final p = im.getPixel(x, y);
          final blendF = (edge * 0.75).clamp(0.0, 1.0);
          final n = (rnd.nextDouble() - 0.5) * 14;
          im.setPixelRgb(
            x,
            y,
            (color[0] * blendF + p.r * (1 - blendF) + n).round().clamp(0, 255),
            (color[1] * blendF + p.g * (1 - blendF) + n).round().clamp(0, 255),
            (color[2] * blendF + p.b * (1 - blendF) + n).round().clamp(0, 255),
          );
        }
      }
    }
  }

  /// Converts an HSV colour (h in degrees) back to an RGB triple.
  static List<int> _hsvToRgb(double h, double s, double v) {
    final c = v * s;
    final hp = (h % 360) / 60;
    final x = c * (1 - (hp % 2 - 1).abs());
    final m = v - c;
    double r = 0, g = 0, b = 0;
    if (hp < 1) {
      r = c;
      g = x;
    } else if (hp < 2) {
      r = x;
      g = c;
    } else if (hp < 3) {
      g = c;
      b = x;
    } else if (hp < 4) {
      g = x;
      b = c;
    } else if (hp < 5) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    return [
      ((r + m) * 255).round(),
      ((g + m) * 255).round(),
      ((b + m) * 255).round(),
    ];
  }
}

enum SymptomEffect { healthy, spotting, chlorosis, diseased, noPlant }

/// Maps demo sample names to generated images (single source of truth).
class SyntheticSamplesFacade {
  SyntheticSamplesFacade._();

  static img.Image byLabel(String label, int seed) {
    switch (label) {
      case 'healthy':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.healthy,
        );
      case 'spotting':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.spotting,
        );
      case 'chlorosis':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.chlorosis,
        );
      case 'diseased':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.diseased,
        );
      case 'blurry':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.healthy,
          blur: true,
        );
      case 'dark':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.diseased,
          darkness: 0.18,
        );
      case 'no_plant':
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.noPlant,
        );
      default:
        return SyntheticSamples.leaf(
          seed: seed,
          effect: SymptomEffect.healthy,
        );
    }
  }

  static const List<String> allLabels = [
    'healthy',
    'spotting',
    'chlorosis',
    'diseased',
    'blurry',
    'dark',
    'no_plant',
  ];
}

class _Leaf {
  const _Leaf({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required this.rotation,
    required this.greenHue,
  });

  final double cx;
  final double cy;
  final double rx;
  final double ry;
  final double rotation;
  final double greenHue;
}