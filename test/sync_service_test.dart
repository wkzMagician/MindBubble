import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_sync/dartloom_sync.dart' as dartloom;
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/sync_service.dart';
import 'package:mind_bubble/services/webdav_transport.dart';

void main() {
  test('a bubble round trips through one Markdown document', () {
    final bubble = Bubble(
      id: 'bubble-1',
      title: 'Title',
      description: '## Body\n\nText\n\n---\n\nMore text',
      createdAt: DateTime.fromMillisecondsSinceEpoch(10),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(20),
      appearanceFrequency: 5,
      shownByDevice: {
        'device-a': BubbleShowStats(
          count: 2,
          lastShownAt: DateTime.fromMillisecondsSinceEpoch(15),
        ),
      },
    );

    final raw = BubbleDocumentCodec.encode(bubble, updatedBy: 'device-a');
    final restored = BubbleDocumentCodec.decode(raw, expectedId: 'bubble-1');

    expect(restored.bubble.title, 'Title');
    expect(restored.bubble.description, bubble.description);
    expect(restored.bubble.appearanceFrequency, 5);
    expect(restored.bubble.shownCount, 2);
  });

  group('typed Dartloom facade', () {
    late Directory temporary;
    late _FakeDartloomSync delegate;
    late _MemoryWebDav remote;
    late SyncService service;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('stage8-sync-');
      delegate = _FakeDartloomSync();
      remote = _MemoryWebDav();
      service = SyncService(
        delegate: delegate,
        supportRoot: temporary,
        transportFactory: (_) => remote,
        configFile: File('${temporary.path}/webdav-config.json'),
        legacyConfigFile: File('${temporary.path}/webdav_config.json'),
        migrationMarkerFile: File('${temporary.path}/migration.json'),
      );
    });

    tearDown(() async {
      await delegate.dispose();
      await temporary.delete(recursive: true);
    });

    test('forwards typed snapshots and maps typed reports', () async {
      final observed = <dartloom.SyncSnapshot>[];
      final subscription = service.states.listen(observed.add);
      addTearDown(subscription.cancel);

      await service.configureWebDav(
        serverUrl: 'https://example.test/dav/',
        username: 'user',
        appPassword: 'secret',
      );
      delegate.emit(
        dartloom.SyncSnapshot(
          phase: dartloom.SyncPhase.succeeded,
          localRevision: 4,
          activeProfileId: 'default',
          lastSuccessAt: DateTime.utc(2026, 8, 14),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await service.syncNow();

      expect(observed.single.phase, dartloom.SyncPhase.succeeded);
      expect(service.lastSyncedAt, DateTime.utc(2026, 8, 14));
      expect(delegate.syncCalls, 1);

      delegate.report = const dartloom.SyncRunReport(
        trigger: dartloom.SyncTrigger.manual,
        failure: dartloom.SyncFailure(
          dartloom.SyncFailureKind.authentication,
          'authentication failed',
        ),
      );
      await expectLater(
        service.syncNow(),
        throwsA(
          isA<SyncException>().having(
            (error) => error.kind,
            'kind',
            SyncErrorKind.authentication,
          ),
        ),
      );
    });

    test('uses typed conflicts and typed resolution choices', () async {
      delegate.conflicts = [
        dartloom.SyncConflict(
          id: 'default::bubble-1.md',
          key: 'bubble-1.md',
          local: Uint8List.fromList(utf8.encode('local')),
          remote: Uint8List.fromList(utf8.encode('remote')),
        ),
      ];

      final conflicts = await service.listConflicts();
      expect(conflicts.single.key, 'bubble-1.md');

      await service.resolveConflict(
        conflicts.single.id,
        ConflictResolution.remote,
      );
      expect(delegate.resolved.single.$1, 'default::bubble-1.md');
      expect(
        delegate.resolved.single.$2.choice,
        dartloom.SyncConflictChoice.useRemote,
      );
    });

    test(
      'migrates plaintext config into profile secrets then removes it',
      () async {
        final plaintext = File('${temporary.path}/webdav-config.json');
        await plaintext.writeAsString(
          jsonEncode({
            'serverUrl': 'https://example.test/dav/',
            'username': 'legacy-user',
            'appPassword': 'legacy-secret',
          }),
        );

        final loaded = await service.loadConfig();

        expect(loaded?.serverUrl, 'https://example.test/dav/');
        expect(loaded?.username, 'legacy-user');
        expect(loaded?.appPassword, isEmpty);
        expect(delegate.lastDraft?.backend, 'webdav');
        expect(delegate.lastDraft?.secrets, {'password': 'legacy-secret'});
        expect(delegate.lastDraft?.options, {
          'base_url': 'https://example.test/dav/',
          'username': 'legacy-user',
        });
        expect(await plaintext.exists(), isFalse);
        expect(
          await File('${temporary.path}/migration.json').readAsString(),
          isNot(contains('legacy-secret')),
        );
      },
    );

    test(
      'new remote wins, only missing files copy, and source is unchanged',
      () async {
        remote.put('/MindBubble/v2/bubbles/old-only.md', 'old-only');
        remote.put('/MindBubble/v2/bubbles/shared.md', 'legacy-shared');
        remote.put('/MindBubble/bubbles/shared.md', 'new-shared');
        remote.put('/MindBubble/bubbles/new-only.md', 'new-only');
        final sourceBefore = remote.snapshot('/MindBubble/v2/bubbles');

        final report = await service.migrateLegacyRemote(
          const WebDavConfig(
            serverUrl: 'https://example.test/dav/',
            username: 'user',
            appPassword: 'secret',
          ),
        );

        expect(report.discovered, 2);
        expect(report.copied, 1);
        expect(report.newWins, 1);
        expect(report.failures, isEmpty);
        expect(remote.text('/MindBubble/bubbles/old-only.md'), 'old-only');
        expect(remote.text('/MindBubble/bubbles/shared.md'), 'new-shared');
        expect(remote.snapshot('/MindBubble/v2/bubbles'), sourceBefore);
        expect(remote.deleteCalls, isEmpty);

        final writes = remote.writeCalls.length;
        final repeated = await service.migrateLegacyRemote(
          const WebDavConfig(
            serverUrl: 'https://example.test/dav/',
            username: 'user',
            appPassword: 'secret',
          ),
        );
        expect(repeated.copied, 1);
        expect(remote.writeCalls, hasLength(writes));

        final marker =
            jsonDecode(
                  await File('${temporary.path}/migration.json').readAsString(),
                )
                as Map<String, Object?>;
        expect(marker['version'], 1);
        expect(marker['source'], '/MindBubble/v2/bubbles');
        expect(marker['target'], '/MindBubble/bubbles');
        expect(marker['copied'], 1);
        expect(marker['newWins'], 1);
        expect(marker['failures'], isEmpty);
      },
    );

    test('migration records sanitized failures and safely retries', () async {
      remote.put('/MindBubble/v2/bubbles/retry.md', 'source');
      remote.failWrites.add('/MindBubble/bubbles/retry.md');

      final first = await service.migrateLegacyRemote(
        const WebDavConfig(
          serverUrl: 'https://example.test/dav/',
          username: 'user',
          appPassword: 'secret',
        ),
      );
      expect(first.isComplete, isFalse);
      expect(first.failures.single, {'key': 'retry.md', 'category': 'network'});

      remote.failWrites.clear();
      final second = await service.migrateLegacyRemote(
        const WebDavConfig(
          serverUrl: 'https://example.test/dav/',
          username: 'user',
          appPassword: 'secret',
        ),
      );
      expect(second.isComplete, isTrue);
      expect(second.copied, 1);
      expect(remote.text('/MindBubble/v2/bubbles/retry.md'), 'source');
      expect(remote.text('/MindBubble/bubbles/retry.md'), 'source');
    });
  });
}

final class _FakeDartloomSync implements dartloom.SyncService {
  final _states = StreamController<dartloom.SyncSnapshot>.broadcast();
  var current = const dartloom.SyncSnapshot.initial();
  var report = const dartloom.SyncRunReport(
    trigger: dartloom.SyncTrigger.manual,
  );
  var profiles = const [
    dartloom.SyncProfile(
      id: 'default',
      label: 'Local',
      backend: '',
      isActive: true,
    ),
  ];
  List<dartloom.SyncConflict> conflicts = [];
  dartloom.SyncProfileDraft? lastDraft;
  final resolved = <(String, dartloom.SyncConflictResolution)>[];
  int syncCalls = 0;

  void emit(dartloom.SyncSnapshot value) {
    current = value;
    _states.add(value);
  }

  @override
  dartloom.SyncSnapshot get snapshot => current;
  @override
  Stream<dartloom.SyncSnapshot> get states => _states.stream;
  @override
  Future<void> start() async {}
  @override
  Future<dartloom.SyncRunReport> syncNow() async {
    syncCalls++;
    return report;
  }

  @override
  Future<List<dartloom.SyncProfile>> listProfiles() async => profiles;
  @override
  Future<dartloom.SyncProfile> saveProfile(
    dartloom.SyncProfileDraft draft,
  ) async {
    lastDraft = draft;
    final saved = dartloom.SyncProfile(
      id: draft.id ?? 'generated',
      label: draft.label,
      backend: draft.backend,
      options: draft.options,
      isActive: profiles.any(
        (profile) =>
            profile.id == (draft.id ?? 'generated') && profile.isActive,
      ),
    );
    profiles = [saved];
    return saved;
  }

  @override
  Future<void> activateProfile(String profileId) async {
    profiles = [
      for (final profile in profiles)
        dartloom.SyncProfile(
          id: profile.id,
          label: profile.label,
          backend: profile.backend,
          options: profile.options,
          isActive: profile.id == profileId,
        ),
    ];
  }

  @override
  Future<void> deleteProfile(
    String profileId, {
    required bool deleteLocalData,
  }) async {}
  @override
  Future<List<dartloom.SyncConflict>> listConflicts() async => conflicts;
  @override
  Future<void> resolveConflict(
    String conflictId,
    dartloom.SyncConflictResolution resolution,
  ) async {
    resolved.add((conflictId, resolution));
    conflicts.removeWhere((conflict) => conflict.id == conflictId);
  }

  @override
  Future<void> dispose() => _states.close();
}

final class _MemoryFile {
  _MemoryFile(String value) : bytes = Uint8List.fromList(utf8.encode(value));

  Uint8List bytes;
}

final class _MemoryWebDav implements WebDavTransport {
  final files = <String, _MemoryFile>{};
  final writeCalls = <String>[];
  final deleteCalls = <String>[];
  final failWrites = <String>{};

  void put(String remotePath, String value) {
    files[remotePath] = _MemoryFile(value);
  }

  String? text(String remotePath) {
    final file = files[remotePath];
    return file == null ? null : utf8.decode(file.bytes);
  }

  Map<String, String> snapshot(String directory) => {
    for (final entry in files.entries)
      if (entry.key.startsWith('$directory/'))
        entry.key: utf8.decode(entry.value.bytes),
  };

  @override
  Future<void> ensureDirectory(String remotePath) async {}

  @override
  Future<List<WebDavResource>> list(String remotePath) async {
    final prefix = '$remotePath/';
    return [
      for (final entry in files.entries)
        if (entry.key.startsWith(prefix) &&
            !entry.key.substring(prefix.length).contains('/'))
          WebDavResource(
            path: entry.key,
            name: entry.key.substring(prefix.length),
            isDirectory: false,
            etag: '"etag"',
          ),
    ];
  }

  @override
  Future<WebDavReadResult> read(String remotePath) async {
    final file = files[remotePath];
    if (file == null) {
      throw const WebDavTransportException('GET', statusCode: 404);
    }
    return WebDavReadResult(Uint8List.fromList(file.bytes), '"etag"');
  }

  @override
  Future<String?> write(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool createOnly = false,
    String contentType = 'application/octet-stream',
  }) async {
    writeCalls.add(remotePath);
    if (failWrites.contains(remotePath)) {
      throw const WebDavTransportException('PUT', statusCode: 503);
    }
    if (createOnly && files.containsKey(remotePath)) {
      throw const WebDavTransportException('PUT', statusCode: 412);
    }
    files[remotePath] = _MemoryFile(utf8.decode(bytes));
    return '"etag"';
  }

  @override
  Future<void> delete(String remotePath, {String? ifMatch}) async {
    deleteCalls.add(remotePath);
    files.remove(remotePath);
  }

  @override
  void close() {}
}
