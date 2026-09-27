import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Small rounded photo attached to a grid tile (with graceful fallback).
class PlantThumbnail extends StatelessWidget {
  const PlantThumbnail({
    super.key,
    required this.path,
    this.borderRadius = 10,
  });

  final String path;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final valid = path.isNotEmpty && File(path).existsSync();
    final fallback = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: const Icon(Icons.eco_outlined, color: AppColors.primary),
    );
    if (!valid) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.file(
        File(path),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}