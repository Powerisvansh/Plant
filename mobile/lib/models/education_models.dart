import 'package:flutter/material.dart';

/// One educational topic card in the Learn section.
class LearnTopic {
  const LearnTopic({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.sections,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// Ordered heading + body pairs rendered on the detail page.
  final List<(String, String)> sections;

  String get intro => sections.isEmpty ? '' : sections.first.$2;
}

/// A short, verifiable plant-care tip shown on the Home screen.
class PlantTip {
  const PlantTip({required this.title, required this.body});

  final String title;
  final String body;
}