import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/theme/app_theme.dart';
import '../models/analysis_models.dart';

/// Paints the analysis evidence (yellow/brown/spot boxes) over a working
/// photo. Rect coordinates are in working-pixel space; the overlay scales
/// them to the displayed widget size.
class EvidenceOverlay extends StatefulWidget {
  const EvidenceOverlay({
    super.key,
    required this.imagePath,
    required this.evidence,
  });

  final String imagePath;
  final List<EvidenceRegion> evidence;

  @override
  State<EvidenceOverlay> createState() => _EvidenceOverlayState();
}

class _EvidenceOverlayState extends State<EvidenceOverlay> {
  int? _width;
  int? _height;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || !mounted) return;
      setState(() {
        _width = decoded.width;
        _height = decoded.height;
      });
    } catch (_) {
      // Keep the fallback box; detection simply won't draw.
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _width, h = _height;
    final valid = widget.imagePath.isNotEmpty && File(widget.imagePath).existsSync();
    if (!valid) return _FallbackBox();
    return AspectRatio(
      aspectRatio: ((w ?? 1) / (h ?? 1)).clamp(0.4, 2.4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaleX = constraints.maxWidth / (w ?? 1);
          final scaleY = constraints.maxHeight / (h ?? 1);
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(widget.imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _FallbackBox(),
              ),
              if (w != null && h != null && widget.evidence.isNotEmpty)
                CustomPaint(
                  painter: _EvidencePainter(
                    evidence: widget.evidence,
                    scaleX: scaleX,
                    scaleY: scaleY,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EvidencePainter extends CustomPainter {
  const _EvidencePainter({
    required this.evidence,
    required this.scaleX,
    required this.scaleY,
  });

  final List<EvidenceRegion> evidence;
  final double scaleX;
  final double scaleY;

  @override
  void paint(Canvas canvas, Size size) {
    for (final region in evidence.take(12)) {
      final rect = Rect.fromLTRB(
        region.rect.left * scaleX,
        region.rect.top * scaleY,
        region.rect.right * scaleX,
        region.rect.bottom * scaleY,
      );
      if (rect.width < 2 || rect.height < 2) continue;
      final color = switch (region.kind) {
        'yellow' => const Color(0xFFF9A825),
        'brown' => const Color(0xFF8D6E63),
        'spot' => const Color(0xFFD81B60),
        _ => AppColors.teal,
      };
      final paint = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, paint);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_EvidencePainter oldDelegate) =>
      oldDelegate.evidence != evidence ||
      oldDelegate.scaleX != scaleX ||
      oldDelegate.scaleY != scaleY;
}

class _FallbackBox extends StatelessWidget {
  const _FallbackBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.eco_outlined, size: 48, color: AppColors.primaryLight),
      ),
    );
  }
}