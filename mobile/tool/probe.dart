import 'package:image/image.dart' as img;
import 'generate_assets.dart';

void main() {
  final im = renderIcon(96);
  final s = im.width;
  for (final (x, y) in [(0, 0), (1, 1), (3, 3), (10, 10), (48, 2)]) {
    final p = im.getPixel(x, y);
    print('($x,$y) -> r=${p.r} g=${p.g} b=${p.b} a=${p.a}');
  }
}