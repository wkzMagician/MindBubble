import 'dart:io';

import 'package:dartloom/dartloom.dart';
import 'package:dartloom_singleton_socket/dartloom_singleton_socket.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'services/bubble_document_store.dart';
import 'services/daily_selection_cache.dart';
import 'services/device_identity_service.dart';
import 'services/startup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mount Flutter immediately while filesystem and Dartloom services start.
  // An exception before runApp used to appear as a permanent white screen.
  runApp(StartupBootstrap(initialize: _initializeApp()));
}

Future<Widget> _initializeApp() async {
  try {
    final singleton = SocketSingleInstanceService(
      identity: 'dev.mindbubble.mind_bubble',
    );
    await singleton.ensureSingleInstance();

    final documents = (await getApplicationDocumentsDirectory()).absolute;
    final ObjectStore objectStore = await FileObjectStore.open(
      root: Directory(path.join(documents.path, 'MindBubble', 'bubbles')),
    );
    final identity = await DeviceIdentity.load();
    final documentStore = await BubbleDocumentStore.open(
      identity,
      objectStore: objectStore,
    );
    final dailyCache = await DailySelectionCache.open();
    final startupService = StartupService()..initialize();

    return ProviderScope(
      overrides: [
        deviceIdentityProvider.overrideWithValue(identity),
        bubbleDocumentStoreProvider.overrideWithValue(documentStore),
        dailySelectionCacheProvider.overrideWithValue(dailyCache),
        startupServiceProvider.overrideWithValue(startupService),
      ],
      child: const MindBubbleApp(),
    );
  } on Object catch (error, stackTrace) {
    return StartupFailureApp(error: error, stackTrace: stackTrace);
  }
}
