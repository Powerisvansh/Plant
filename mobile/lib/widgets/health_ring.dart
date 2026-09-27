import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Colour of the health ring band for a given index.
Color healthColor(int index) {
  final t = (index / 100).clamp(0.0, 1.0);
  final i = t < 1 ? (t * (AppColors.healthGradient.length - 1)).floor() : AppColors.healthGradient.length - 2;
  final f = t < 1 ? t * (AppColors.healthGradient.length - 1) - i : 1.0;
  final a = AppColors.healthGradient[i];
  final b = AppColors.healthGradient[i + 1];
  return Color.lerp(a, b, f)!;
}

/// Circular health index gauge used on the results and records.
class HealthRing extends StatelessWidget {
  const HealthRing({
    super.key,
    required this.index,
    this.size = 88,
    this.stroke = 8,
    this.label,
    this.annotation,
  });

  final int index;
  final double size;
  final double stroke;
  final String? label;
  final String? annotation;

  @override
  Widget build(BuildContext context) {
    final color = healthColor(index);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: index / 100,
              strokeWidth: stroke,
              backgroundColor: AppColors.border,
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$index',
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (label != null)
                Text(
                  label!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: color, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ],
      ),
    );
  }
}