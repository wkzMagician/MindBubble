import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:dartloom_settings/dartloom_settings.dart';

import '../services/bubble_document_store.dart';
import '../services/daily_selection_cache.dart';
import '../services/device_identity_service.dart';
import '../services/startup_service.dart';
import '../services/sync_service.dart';

final class AppServices {
  const AppServices({
    required this.identity,
    required this.documents,
    required this.dailyCache,
    required this.sync,
    required this.settings,
    required this.logger,
    required this.startup,
    required this.dispose,
  });

  final DeviceIdentity identity;
  final BubbleDocumentStore documents;
  final DailySelectionCache dailyCache;
  final SyncService sync;
  final SettingsStore settings;
  final AppLogger logger;
  final StartupService startup;
  final Future<void> Function() dispose;
}
