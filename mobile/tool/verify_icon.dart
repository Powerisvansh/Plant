import 'package:image/image.dart' as img;
import 'generate_assets.dart';

// [M] outside tile (alpha 0)  [.] tile background  [l] leaf blade
// [v] veins (dark green)      [h] highlight/bright
void main() {
  final im = renderIcon(96);
  final s = im.width;
  print('note: size ${s}x${s}. Run from mobile/ so tool/generate_assets.dart resolves.');

  for (var y = 0; y < s; y += 2) {
    var line = '';
    for (var x = 0; x < s; x += 2) {
      final p = im.getPixel(x, y);
      if (p.a == 0) { line += ' '; continue; }
      final g = p.g.toInt();
      final r = p.r.toInt();
      // dark green-ish = vein / dark
      if (r < 80 && g < 130) { line += 'v'; continue; }
      // bright green = leaf blade
      if (g > 160 && g > r + 30) { line += 'L'; continue; }
      // mid green = leaf edge / background boundary
      if (g > 90 && g > r + 10) { line += 'l'; continue; }
      line += '.';
    }
    print(line);
  }
}