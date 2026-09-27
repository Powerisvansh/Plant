import 'dart:math' as math;
import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates PlantDoctor launcher icons: a realistic green leaf with a
/// visible midrib and lateral veins on a rounded gradient tile.
///
/// Every bucket is rendered at 4x resolution then downscaled with an
/// alpha-aware average, so rounded corners stay transparent and edges are
/// anti-aliased.
///
/// Run with:  dart run tool/generate_assets.dart
void main() {
  final root = Directory.current.path;
  final res = '$root/android/app/src/main/res';

  const sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  for (final entry in sizes.entries) {
    final icon = renderIcon(entry.value);
    final dir = '$res/${entry.key}';
    File('$dir/ic_launcher.png').writeAsBytesSync(img.encodePng(icon));
    print('wrote ${entry.key}/ic_launcher.png (${entry.value}px)');
  }
}

/// Renders the app icon at the requested size in pixels.
img.Image renderIcon(int size) {
  const ss = 4;
  final fs = size * ss;
  final fine = img.Image(width: fs, height: fs);

  _drawBackground(fine, fs);
  _drawLeaf(fine, fs);
  _drawStem(fine, fs);

  return _downscaleAlpha(fine, size, size);
}

/// Alpha-aware box downscale: average RGB weighted by alpha, average alpha
/// alone. Keeps transparent corners transparent and colours accurate.
img.Image _downscaleAlpha(img.Image src, int tw, int th) {
  final out = img.Image(width: tw, height: th);
  final sw = src.width, sh = src.height;
  for (var y = 0; y < th; y++) {
    final y0 = (y * sh / th).floor();
    final y1 = math.min(sh, (((y + 1) * sh / th).ceil()));
    for (var x = 0; x < tw; x++) {
      final x0 = (x * sw / tw).floor();
      final x1 = math.min(sw, ((x + 1) * sw / tw).ceil());
      var r = 0.0, g = 0.0, b = 0.0, aSum = 0.0;
      for (var sy = y0; sy < y1; sy++) {
        for (var sx = x0; sx < x1; sx++) {
          final p = src.getPixel(sx, sy);
          r += p.r * p.a;
          g += p.g * p.a;
          b += p.b * p.a;
          aSum += p.a;
        }
      }
      if (aSum <= 0) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        final n = (x1 - x0) * (y1 - y0);
        out.setPixelRgba(
          x,
          y,
          (r / aSum).round().clamp(0, 255),
          (g / aSum).round().clamp(0, 255),
          (b / aSum).round().clamp(0, 255),
          (aSum / n).round().clamp(0, 255),
        );
      }
    }
  }
  return out;
}

// ------------------------------------------------------------------ helpers

double _distToSegment(double px, double py, double ax, double ay, double bx, double by) {
  final abx = bx - ax, aby = by - ay;
  final apx = px - ax, apy = py - ay;
  final len2 = abx * abx + aby * aby;
  final t = len2 == 0 ? 0.0 : ((apx * abx + apy * aby) / len2).clamp(0.0, 1.0);
  final cx = ax + t * abx, cy = ay + t * aby;
  final dx = px - cx, dy = py - cy;
  return math.sqrt(dx * dx + dy * dy);
}

/// Blends a pixel towards white (0..1 amount).
void _lighten(img.Image im, int x, int y, double amt) {
  final p = im.getPixel(x, y);
  if (p.a == 0) return;
  im.setPixelRgb(
    x,
    y,
    (p.r.toInt() + (255 - p.r.toInt()) * amt).toInt(),
    (p.g.toInt() + (255 - p.g.toInt()) * amt).toInt(),
    (p.b.toInt() + (255 - p.b.toInt()) * amt).toInt(),
  );
}

// ----------------------------------------------------------------- background

void _drawBackground(img.Image im, int fs) {
  final radius = fs * 0.22;
  for (var y = 0; y < fs; y++) {
    for (var x = 0; x < fs; x++) {
      final inTile = (x >= radius && x <= fs - radius) ||
          (y >= radius && y <= fs - radius) ||
          _inCircle(x, y, radius, radius, radius) ||
          _inCircle(x, y, fs - radius, radius, radius) ||
          _inCircle(x, y, radius, fs - radius, radius) ||
          _inCircle(x, y, fs - radius, fs - radius, radius);
      if (!inTile) {
        im.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }

      // Vertical gradient: deep forest at top -> lighter green at bottom,
      // plus a soft radial highlight near the top-left.
      final t = y / fs;
      final rr = 0x1B + (0x2E - 0x1B) * t;
      final gg = 0x5E + (0x7D - 0x5E) * t;
      final bb = 0x20 + (0x32 - 0x20) * t;
      final rdx = (x - fs * 0.28);
      final rdy = (y - fs * 0.22);
      final glow = math.exp(-(rdx * rdx + rdy * rdy) / (2 * fs * fs * 0.28));
      im.setPixelRgb(
        x,
        y,
        (rr + (0x43 - rr) * 0.55 * glow).toInt().clamp(0, 255),
        (gg + (0xA0 - gg) * 0.55 * glow).toInt().clamp(0, 255),
        (bb + (0x47 - bb) * 0.55 * glow).toInt().clamp(0, 255),
      );
    }
  }
}

bool _inCircle(int x, int y, double cx, double cy, double r) {
  final dx = x - cx, dy = y - cy;
  return dx * dx + dy * dy <= r * r;
}

// --------------------------------------------------------------------- leaf

void _drawLeaf(img.Image im, int fs) {
  final S = fs.toDouble();
  // Fitted geometry so the whole leaf stays inside the tile.
  final baseY = S * 0.63;
  final len = S * 0.50;
  final halfW = S * 0.235;
  final tipY = baseY - len;
  final angle = -0.30; // slight right lean
  final cosA = math.cos(angle), sinA = math.sin(angle);

  // Leaf blade: lens profile (pointed at base and tip).
  for (var y = 0; y < fs; y++) {
    for (var x = 0; x < fs; x++) {
      final dx = x - S / 2, dy = y - baseY;
      final lx = dx * cosA - dy * sinA;
      final ly = dx * sinA + dy * cosA;
      final t = -ly / len; // 0 at base, 1 at tip
      if (t <= 0.0 || t >= 1.0) continue;
      final w = halfW * math.sin(math.pi * t);
      if (lx.abs() > w) continue;

      final edge = (lx.abs() / w).clamp(0.0, 1.0);
      final baseV = 0.40 + 0.18 * t;
      final shade = (baseV + 0.16 * edge).clamp(0.0, 0.85).toDouble();
      final gr = (0x2E + (0x9C - 0x2E) * shade).round().clamp(0, 255);
      final gg = (0x7D + (0xD8 - 0x7D) * shade).round().clamp(0, 255);
      final gb = (0x32 + (0x9C - 0x32) * shade).round().clamp(0, 255);
      im.setPixelRgb(x, y, gr, gg, gb);
    }
  }

  // Veins (drawn in the same un-rotated leaf space).
  final veins = <(double, double, double, double)>[];
  const pairs = [0.14, 0.26, 0.40, 0.54, 0.68, 0.82];
  for (final t in pairs) {
    final vy = baseY - len * t;
    final w = halfW * math.sin(math.pi * t);
    final vlen = 0.62 * w;
    final rise = 0.34 * vlen;
    veins.add((0.0, vy, w * 0.82, vy - rise));
    veins.add((0.0, vy, -w * 0.82, vy - rise));
  }

  for (var y = 0; y < fs; y++) {
    for (var x = 0; x < fs; x++) {
      final p = im.getPixel(x, y);
      if (p.a == 0) continue;
      final dx = x - S / 2, dy = y - baseY;
      final lx = dx * cosA - dy * sinA;
      final ly = dx * sinA + dy * cosA;
      final t = -ly / len;
      if (t <= 0.02 || t >= 0.98) continue;

      final w = halfW * math.sin(math.pi * t);
      if (lx.abs() > w * 1.02) continue;

      // Midrib (slightly bowed left-right for a natural look).
      var dMid = double.infinity;
      final bow = w * 0.06;
      for (var i = 0; i <= 16; i++) {
        final t0 = i / 16, t1 = (i + 1) / 16;
        final x0 = bow * math.sin(math.pi * t0);
        final x1v = bow * math.sin(math.pi * t1);
        final y0 = baseY - len * t0, y1v = baseY - len * t1;
        dMid = math.min(
          dMid,
          _distToSegment(lx, ly, x0, y0, x1v, y1v),
        );
      }

      var dVein = double.infinity;
      for (final v in veins) {
        dVein = math.min(dVein, _distToSegment(lx, ly, v.$1, v.$2, v.$3, v.$4));
      }

      if (dMid < w * 0.085 || dVein < w * 0.040) {
        im.setPixelRgb(x, y, 0x14, 0x4A, 0x1F);
      }
    }
  }

  // Soft glossy highlight on the upper-left of the blade.
  for (var y = 0; y < fs; y++) {
    for (var x = 0; x < fs; x++) {
      final p = im.getPixel(x, y);
      if (p.a == 0) continue;
      final dx = x - S / 2, dy = y - baseY;
      final lx = dx * cosA - dy * sinA;
      final ly = dx * sinA + dy * cosA;
      final t = -ly / len;
      if (t < 0.06 || t > 0.9) continue;
      final w = halfW * math.sin(math.pi * t);
      if (lx.abs() > w * 0.82) continue;
      final spot =
          math.exp(-((lx - w * 0.20) * (lx - w * 0.20)) / (w * w * 0.16));
      _lighten(im, x, y, 0.30 * spot);
    }
  }
}

// --------------------------------------------------------------------- stem

void _drawStem(img.Image im, int fs) {
  final S = fs.toDouble();
  final baseY = S * 0.63;
  final angle = -0.30;
  final cosA = math.cos(angle), sinA = math.sin(angle);
  final stemLen = S * 0.17;

  for (var y = 0; y < fs; y++) {
    for (var x = 0; x < fs; x++) {
      // Inverse rotation to leaf space, origin at leaf base.
      final dx = (x - S / 2) * cosA + (y - baseY) * sinA;
      final dy = -(x - S / 2) * sinA + (y - baseY) * cosA;
      if (dy <= 0 || dy > stemLen) continue;
      final t = dy / stemLen;
      final half = S * 0.026 * (1 - 0.38 * t);
      final lean = -S * 0.035 * t;
      if ((dx - lean).abs() > half) continue;
      im.setPixelRgb(x, y, 0x18, 0x50, 0x1E);
    }
  }
}