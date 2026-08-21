import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_composition_native.dart';
import 'services/bubble_document_store.dart';
import 'services/daily_selection_cache.dart';
import 'services/device_identity_service.dart';
import 'services/startup_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mount Flutter immediately while filesystem and Dartloom services start.
  // An exception before runApp used to appear as a permanent white screen.
  runApp(StartupBootstrap(initialize: _initializeApp()));
}

Future<Widget> _initializeApp() async {
  try {
    final services = await createApplicationServices();

    return ProviderScope(
      overrides: [
        deviceIdentityProvider.overrideWithValue(services.identity),
        bubbleDocumentStoreProvider.overrideWithValue(services.documents),
        dailySelectionCacheProvider.overrideWithValue(services.dailyCache),
        startupServiceProvider.overrideWithValue(services.startup),
        syncServiceProvider.overrideWithValue(services.sync),
      ],
      child: const MindBubbleApp(),
    );
  } on Object catch (error, stackTrace) {
    return StartupFailureApp(error: error, stackTrace: stackTrace);
  }
}
