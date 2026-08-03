import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'services/bubble_document_store.dart';
import 'services/daily_selection_cache.dart';
import 'services/device_identity_service.dart';
import 'services/startup_service.dart';
import 'services/sync_state_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupService = StartupService()..initialize();
  final identity = await DeviceIdentity.load();
  final documentStore = await BubbleDocumentStore.open(identity);
  final dailyCache = await DailySelectionCache.open();
  final syncState = await SyncStateStore.open();
  runApp(
    ProviderScope(
      overrides: [
        deviceIdentityProvider.overrideWithValue(identity),
        bubbleDocumentStoreProvider.overrideWithValue(documentStore),
        dailySelectionCacheProvider.overrideWithValue(dailyCache),
        syncStateStoreProvider.overrideWithValue(syncState),
        startupServiceProvider.overrideWithValue(startupService),
      ],
      child: const MindBubbleApp(),
    ),
  );
}
