import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'database/database.dart';
import 'services/startup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupService = StartupService()..initialize();
  final database = await AppDatabase.open();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        startupServiceProvider.overrideWithValue(startupService),
      ],
      child: const MindBubbleApp(),
    ),
  );
}
