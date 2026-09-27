import 'package:flutter/material.dart';

import 'app.dart';
import 'services/storage/app_database.dart';
import 'services/storage/settings_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController(SettingsService());
  final db = await AppDatabase.open();
  final history = HistoryController(db);
  final plants = PlantsController(db);
  await Future.wait([
    settings.load(),
    history.load(),
    plants.load(),
  ]);
  runApp(PlantDoctorApp(settings: settings, history: history, plants: plants));
}