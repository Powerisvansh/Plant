import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/home/home_shell.dart';
import 'services/analysis/analyze_service.dart';
import 'services/image_files.dart';
import 'state/providers.dart';

/// Root widget of PlantDoctor.
///
/// Controllers are created in [main] and handed to the app; services are
/// provided so screens can read them with `context.read`.
class PlantDoctorApp extends StatelessWidget {
  const PlantDoctorApp({
    super.key,
    required this.settings,
    required this.history,
    required this.plants,
  });

  final SettingsController settings;
  final HistoryController history;
  final PlantsController plants;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: plants),
        Provider<AnalyzeService>(
          create: (_) => AnalyzeService(ImageFiles()),
        ),
      ],
      child: MaterialApp(
        title: 'PlantDoctor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
  }
}