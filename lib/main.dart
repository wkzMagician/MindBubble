import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:dartloom_storage/dartloom_storage.dart';

import 'app/app.dart';
import 'app/dartloom_factories.dart';
import 'capabilities/capabilities.dart';
import 'services/bubble_document_store.dart';
import 'services/daily_selection_cache.dart';
import 'services/device_identity_service.dart';
import 'services/startup_service.dart';
import 'services/local_data_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDataBackupService.createInitialBackup();
  await initializeDartloom(customFactories: dartloomApplicationFactories);
  final startupService = StartupService()..initialize();
  final identity = await DeviceIdentity.load();
  final documentStore = await BubbleDocumentStore.open(
    identity,
    replicaStore: Dartloom.get<ReplicaStore>(name: 'markdown'),
  );
  final dailyCache = await DailySelectionCache.open();
  runApp(
    ProviderScope(
      overrides: [
        deviceIdentityProvider.overrideWithValue(identity),
        bubbleDocumentStoreProvider.overrideWithValue(documentStore),
        dailySelectionCacheProvider.overrideWithValue(dailyCache),
        startupServiceProvider.overrideWithValue(startupService),
      ],
      child: const MindBubbleApp(),
    ),
  );
}
