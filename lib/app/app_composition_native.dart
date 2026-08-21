import 'dart:async';
import 'dart:io';

import 'package:dartloom_autostart/dartloom_autostart.dart';
import 'package:dartloom_autostart_launch_at_startup/dartloom_autostart_launch_at_startup.dart';
import 'package:dartloom_logging_logger/dartloom_logging_logger.dart';
import 'package:dartloom_settings_secure_storage/dartloom_settings_secure_storage.dart';
import 'package:dartloom_settings_shared_preferences/dartloom_settings_shared_preferences.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:dartloom_singleton_socket/dartloom_singleton_socket.dart';
import 'package:dartloom_sync/dartloom_sync.dart' hide SyncService;
import 'package:dartloom_sync_etag/dartloom_sync_etag.dart';
import 'package:dartloom_sync_flutter/dartloom_sync_flutter.dart';
import 'package:dartloom_sync_storage/dartloom_sync_storage.dart';
import 'package:dartloom_sync_webdav/dartloom_sync_webdav.dart';
import 'package:dartloom_sync_workmanager/dartloom_sync_workmanager.dart';
import 'package:flutter/foundation.dart';

import '../services/bubble_document_store.dart';
import '../services/daily_selection_cache.dart';
import '../services/device_identity_service.dart';
import '../services/startup_service.dart';
import '../services/sync_service.dart';
import 'app_paths.dart';
import 'app_services.dart';

Future<AppServices> createApplicationServices({bool background = false}) async {
  final singleton = background
      ? null
      : SocketSingleInstanceService(identity: 'dev.mindbubble.mind_bubble');
  await singleton?.ensureSingleInstance();
  final settings = SharedPreferencesSettingsStore();
  final secrets = const SecureSettingsStore();
  final logger = LoggerAppLogger();
  final paths = await MindBubblePaths.resolve();
  final objects = await FileObjectStore.open(root: paths.businessRoot);
  final metadata = await FileObjectStore.open(root: paths.metadataRoot);
  final journaled = await JournaledObjectStore.open(
    objects: objects,
    metadata: metadata,
  );
  final identity = await DeviceIdentity.load();
  final documents = await BubbleDocumentStore.open(
    identity,
    objectStore: journaled,
  );
  final dailyCache = await DailySelectionCache.open();
  final scope = await SyncProfileScope.open(settings, 'mindbubble');
  final signals = background ? null : FlutterSyncRuntimeSignals();
  await signals?.start();

  final sync = SyncCoordinator(
    instanceName: 'mindbubble',
    policy: SyncPolicyCodec.resolve(_syncPolicy, _platformName),
    profiles: SettingsSyncProfileRepository(
      instanceName: 'mindbubble',
      metadata: settings,
      secretsStore: secrets,
      scope: scope,
    ),
    localFactory: JournaledObjectStoreLocalReplicaFactory(journaled),
    stateRepository: SettingsReconciliationStateRepository(
      settings,
      instanceName: 'mindbubble',
    ),
    reconciler: const EtagReconciler(),
    backends: {
      'webdav': WebDavBackendFactory(
        defaultRootPath: 'MindBubble/v2/bubbles',
        createMissingCollections: true,
        hierarchical: false,
        probeDepthInfinity: false,
        connectTimeout: const Duration(seconds: 10),
        requestTimeout: const Duration(seconds: 30),
        maxParallelRequests: 4,
      ),
    },
    runtimeSignals: signals,
    backgroundScheduler: background
        ? null
        : WorkmanagerSyncBackgroundScheduler(
            callbackDispatcher: mindBubbleSyncCallbackDispatcher,
          ),
  );
  await sync.start();

  AutostartService? autostart;
  if (!background && _isDesktop) {
    autostart = LaunchAtStartupService(
      appName: 'mind_bubble',
      appPath: Platform.resolvedExecutable,
      packageName: 'dev.mindbubble.mind_bubble',
    );
  }
  final startup = StartupService(autostart);
  startup.initialize();
  final facade = SyncService(
    delegate: sync,
    settings: settings,
    secrets: secrets,
    scope: scope,
    logger: logger,
  );

  return AppServices(
    identity: identity,
    documents: documents,
    dailyCache: dailyCache,
    sync: facade,
    settings: settings,
    logger: logger,
    startup: startup,
    dispose: () async {
      await facade.dispose();
      await singleton?.dispose();
      await signals?.dispose();
      await scope.dispose();
      await journaled.close();
    },
  );
}

@pragma('vm:entry-point')
void mindBubbleSyncCallbackDispatcher() {
  executeDartloomSyncWorker((_) async {
    final services = await createApplicationServices(background: true);
    return DartloomSyncWorkerSession(
      run: () async => (await services.sync.syncNow()).isSuccess,
      dispose: services.dispose,
    );
  });
}

bool get _isDesktop => {
  TargetPlatform.windows,
  TargetPlatform.macOS,
  TargetPlatform.linux,
}.contains(defaultTargetPlatform);

String get _platformName => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'android',
  TargetPlatform.iOS => 'ios',
  TargetPlatform.windows => 'windows',
  TargetPlatform.macOS => 'macos',
  TargetPlatform.linux => 'linux',
  _ => 'windows',
};

const _syncPolicy = <String, Object?>{
  'mode': 'automatic',
  'triggers': {
    'startup': true,
    'resume': true,
    'connectivity_restored': true,
    'local_write': {'enabled': true, 'debounce': '2s', 'max_delay': '10s'},
  },
  'discovery': {
    'remote_changes': 'auto',
    'poll_interval': '5m',
    'safety_reconcile_interval': '15m',
  },
  'execution': {
    'timeout': '2m',
    'busy_behavior': 'coalesce_then_rerun',
    'max_parallel_transfers': 4,
    'max_object_size': '20mb',
  },
  'retry': {
    'strategy': 'exponential',
    'initial_delay': '5s',
    'fixed_delay': '30s',
    'sequence': ['5s', '30s', '2m', '10m'],
    'multiplier': 3,
    'max_delay': '10m',
    'jitter': '20%',
    'max_attempts': 0,
  },
  'conflicts': {'strategy': 'preserve', 'delete_vs_update': 'conflict'},
  'state': {'base_payload': 'always', 'tombstone_retention': '30d'},
  'profiles': {'sync_on_activate': true, 'existing_data': 'attach_to_default'},
  'platforms': {
    'android': {
      'background': {
        'enabled': true,
        'enqueue_on_pending': true,
        'periodic_interval': '15m',
        'flex_interval': '5m',
        'network': 'connected',
        'requires_network': true,
        'timeout': '2m',
      },
    },
    'ios': {
      'background': {
        'enabled': true,
        'enqueue_on_pending': true,
        'network': 'connected',
        'requires_network': true,
        'timeout': '25s',
        'earliest_begin': '15m',
      },
    },
  },
};
