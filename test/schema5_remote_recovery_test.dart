import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:dartloom_sync_etag/dartloom_sync_etag.dart';
import 'package:dartloom_sync_storage/dartloom_sync_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/mindbubble_replica_store.dart';
import 'package:mind_bubble/services/shared_mcp_journal.dart';

void main() {
  test(
    'root loss and external changes recover without remote mutation',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      await fixture.store.writeBytes('a.md', _bytes('remote-a'));
      await fixture.store.writeBytes('b.md', _bytes('remote-b'));
      await const EtagReconciler().reconcile(fixture.request());
      final remoteBefore = fixture.remote.snapshot();
      final writesBefore = fixture.remote.writeCount;
      final deletesBefore = fixture.remote.deleteCount;

      await fixture.local.close();
      await fixture.store.close();
      await fixture.business.delete(recursive: true);
      await fixture.reopen();
      var report = await const EtagReconciler().reconcile(fixture.request());
      expect(report.downloaded, 2);
      expect(fixture.remote.snapshot(), remoteBefore);

      await _deleteWithRetry(
        File('${fixture.business.path}${Platform.pathSeparator}a.md'),
      );
      await File(
        '${fixture.business.path}${Platform.pathSeparator}b.md',
      ).writeAsString('external edit');
      await File(
        '${fixture.business.path}${Platform.pathSeparator}new.md',
      ).writeAsString('external new');
      report = await const EtagReconciler().reconcile(fixture.request());

      expect(report.downloaded, 2);
      expect(
        await File(
          '${fixture.business.path}${Platform.pathSeparator}a.md',
        ).readAsString(),
        'remote-a',
      );
      expect(
        await File(
          '${fixture.business.path}${Platform.pathSeparator}b.md',
        ).readAsString(),
        'remote-b',
      );
      expect(
        await File(
          '${fixture.business.path}${Platform.pathSeparator}new.md',
        ).readAsString(),
        'external new',
      );
      expect(fixture.remote.snapshot(), remoteBefore);
      expect(fixture.remote.writeCount, writesBefore);
      expect(fixture.remote.deleteCount, deletesBefore);
    },
  );

  test('explicit delete propagates and remote update conflicts', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.store.writeBytes('delete.md', _bytes('delete'));
    await fixture.store.writeBytes('conflict.md', _bytes('base'));
    await const EtagReconciler().reconcile(fixture.request());

    fixture.remote.externalWrite('conflict.md', _bytes('remote update'));
    await fixture.store.delete('delete.md');
    await fixture.store.delete('conflict.md');
    final report = await const EtagReconciler().reconcile(fixture.request());
    final conflicts = await fixture.state.conflicts('default');

    expect(report.deletedRemotely, 1);
    expect(report.conflicts, 1);
    expect(fixture.remote.values, isNot(contains('delete.md')));
    expect(utf8.decode(fixture.remote.values['conflict.md']!), 'remote update');
    expect(conflicts.single.key, 'conflict.md');
    expect(conflicts.single.local, isNull);
  });
}

final class _Fixture {
  _Fixture._(
    this.sandbox,
    this.business,
    this.metadata,
    this.journal,
    this.remote,
    this.state,
  );

  final Directory sandbox;
  final Directory business;
  final Directory metadata;
  final Directory journal;
  final _MemoryRemote remote;
  final _MemoryState state;
  late MindBubbleReplicaStore store;
  late LocalReplica local;

  static Future<_Fixture> open() async {
    final sandbox = await Directory.systemTemp.createTemp(
      'mindbubble-recovery-',
    );
    final fixture = _Fixture._(
      sandbox,
      Directory('${sandbox.path}${Platform.pathSeparator}bubbles'),
      Directory('${sandbox.path}${Platform.pathSeparator}metadata'),
      Directory('${sandbox.path}${Platform.pathSeparator}journal'),
      _MemoryRemote(),
      _MemoryState(),
    );
    await fixture.reopen();
    return fixture;
  }

  Future<void> reopen() async {
    final files = await FileDirectoryStore.open(
      root: business.absolute,
      metadataRoot: metadata.absolute,
      hierarchical: false,
    );
    store = MindBubbleReplicaStore(
      files: files,
      journal: SharedMcpJournal(
        documentRoot: business.absolute,
        journalRoot: journal.absolute,
      ),
    );
    local = await ReplicaStoreLocalReplicaFactory(store).open('default');
  }

  SyncReconcileRequest request() => SyncReconcileRequest(
    profileId: 'default',
    trigger: SyncTrigger.manual,
    local: local,
    remote: remote,
    state: state,
    policy: SyncPolicyCodec.resolve(_policy, 'windows'),
    now: DateTime.utc(2026, 8, 14),
  );

  Future<void> close() async {
    await local.close();
    await store.close();
    await remote.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  }
}

final class _MemoryRemote implements RemoteReplica {
  final values = <String, Uint8List>{};
  final _versions = <String, String>{};
  int _revision = 0;
  int writeCount = 0;
  int deleteCount = 0;

  @override
  String get identity => 'mindbubble-test-remote';
  @override
  RemoteReplicaCapabilities get capabilities => const RemoteReplicaCapabilities(
    deltaScan: false,
    changeFeed: false,
    conditionalWrites: true,
  );
  @override
  Stream<void>? get changeHints => null;
  Map<String, String> snapshot() => {
    for (final entry in values.entries) entry.key: base64Encode(entry.value),
  };
  void externalWrite(String key, Uint8List data) {
    values[key] = Uint8List.fromList(data);
    _versions[key] = 'v${++_revision}';
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<RemoteScan> scan({String? cursor}) async => RemoteScan(
    kind: SyncScanKind.full,
    objects: [
      for (final entry in _versions.entries)
        RemoteObjectMetadata(key: entry.key, version: entry.value),
    ],
    complete: true,
  );
  @override
  Future<RemoteObject?> read(String key) async => values[key] == null
      ? null
      : RemoteObject(
          key: key,
          data: Uint8List.fromList(values[key]!),
          version: _versions[key]!,
        );
  @override
  Future<String> write(
    String key,
    Uint8List data, {
    RemoteWriteCondition? condition,
  }) async {
    _check(key, condition);
    writeCount++;
    externalWrite(key, data);
    return _versions[key]!;
  }

  @override
  Future<void> delete(String key, {RemoteWriteCondition? condition}) async {
    _check(key, condition);
    deleteCount++;
    values.remove(key);
    _versions.remove(key);
  }

  void _check(String key, RemoteWriteCondition? condition) {
    if (condition is RemoteCreateCondition && values.containsKey(key)) {
      throw RemotePreconditionException(key);
    }
    if (condition is RemoteVersionCondition &&
        _versions[key] != condition.version) {
      throw RemotePreconditionException(key);
    }
  }

  @override
  Future<void> close() async {}
}

final class _MemoryState implements ReconciliationStateRepository {
  SyncState value = const SyncState();
  @override
  Future<SyncState> load(String profileId) async => value;
  @override
  Future<void> save(String profileId, SyncState state) async => value = state;
  @override
  Future<List<SyncConflict>> conflicts(String profileId) async =>
      value.conflicts.values.map((stored) => stored.value).toList();
  @override
  Future<void> resolve(
    String profileId,
    String conflictId,
    SyncConflictResolution resolution,
  ) async {}
}

Future<void> _deleteWithRetry(File file) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    try {
      await file.delete();
      return;
    } on FileSystemException {
      if (attempt == 39) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

final _policy = <String, Object?>{
  'mode': 'manual',
  'triggers': {
    'startup': false,
    'resume': false,
    'connectivity_restored': false,
    'local_write': {'enabled': false, 'debounce': '2s', 'max_delay': '10s'},
  },
  'discovery': {
    'remote_changes': 'disabled',
    'poll_interval': '60s',
    'safety_reconcile_interval': '15m',
  },
  'execution': {
    'timeout': '2m',
    'busy_behavior': 'reject',
    'max_parallel_transfers': 1,
    'max_object_size': '20mb',
  },
  'retry': {
    'strategy': 'none',
    'initial_delay': '5s',
    'fixed_delay': '30s',
    'sequence': <String>[],
    'multiplier': 2,
    'max_delay': '10m',
    'jitter': '0%',
    'max_attempts': 0,
  },
  'conflicts': {'strategy': 'preserve', 'delete_vs_update': 'conflict'},
  'state': {'base_payload': 'always', 'tombstone_retention': '30d'},
  'profiles': {'sync_on_activate': false, 'existing_data': 'attach_to_default'},
};
