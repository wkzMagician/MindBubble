import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:path/path.dart' as p;

import 'shared_mcp_journal.dart';

final class MindBubbleReplicaStore implements ReplicaStore {
  MindBubbleReplicaStore({required this.files, required this.journal}) {
    _fileChanges = files.changes.listen(_forwardFileChange);
    _journalPoller = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_pollJournalIntents()),
    );
    unawaited(_pollJournalIntents());
  }

  final FileDirectoryStore files;
  final SharedMcpJournal journal;
  final StreamController<StoreChange> _changes =
      StreamController<StoreChange>.broadcast();
  final Set<String> _announcedIntentIds = {};
  final Set<Future<void>> _backgroundTasks = {};
  late final StreamSubscription<StoreChange> _fileChanges;
  late final Timer _journalPoller;
  bool _closed = false;
  bool _pollingJournal = false;
  bool _journalPollingDisabled = false;
  Completer<void>? _pollCompleted;

  @override
  String get identity => files.identity;

  @override
  Stream<StoreChange> get changes => _changes.stream;

  @override
  bool acceptsKey(String key) =>
      key.toLowerCase().endsWith('.md') && files.acceptsKey(key);

  @override
  Future<List<ReplicaObjectMetadata>> scan() => files.scan();

  @override
  Future<Uint8List?> readBytes(String key) => files.readBytes(key);

  @override
  Future<void> writeBytes(
    String key,
    Uint8List data, {
    StoreMutationOrigin origin = StoreMutationOrigin.application,
  }) async {
    if (!acceptsKey(key)) throw ArgumentError.value(key, 'key');
    if (!origin.isAuthorizedIntent || origin == StoreMutationOrigin.migration) {
      await files.writeBytes(key, data, origin: origin);
      return;
    }
    final existing = await files.readBytes(key);
    final operationId = _operationId(key, origin);
    await journal.mutate(
      operationId: operationId,
      objectId: p.basenameWithoutExtension(key),
      kind: existing == null
          ? SharedJournalIntentKind.create
          : SharedJournalIntentKind.update,
      expectedContentHash: existing == null ? null : _sha256(existing),
      documentBytes: data,
      request: {'source': 'flutter', 'origin': origin.name, 'key': key},
      result: {'key': key},
    );
    _announcedIntentIds.add(operationId);
    _emit(StoreChange(key, origin));
  }

  @override
  Future<void> delete(
    String key, {
    StoreMutationOrigin origin = StoreMutationOrigin.application,
  }) async {
    if (!acceptsKey(key)) throw ArgumentError.value(key, 'key');
    if (!origin.isAuthorizedIntent || origin == StoreMutationOrigin.migration) {
      await files.delete(key, origin: origin);
      return;
    }
    final existing = await files.readBytes(key);
    if (existing == null) return;
    final operationId = _operationId(key, origin);
    await journal.mutate(
      operationId: operationId,
      objectId: p.basenameWithoutExtension(key),
      kind: SharedJournalIntentKind.delete,
      expectedContentHash: _sha256(existing),
      documentBytes: null,
      request: {'source': 'flutter', 'origin': origin.name, 'key': key},
      result: {'key': key},
    );
    _announcedIntentIds.add(operationId);
    _emit(StoreChange(key, origin, deleted: true));
  }

  @override
  Future<List<StoreIntent>> explicitIntents() async {
    final native = await files.explicitIntents();
    final shared = await journal.pendingIntents();
    return [
      ...native,
      for (final intent in shared)
        StoreIntent(
          operationId: intent.operationId,
          key: intent.key,
          kind: StoreIntentKind.values.byName(intent.kind.name),
          origin: StoreMutationOrigin.application,
          createdAt: intent.createdAt,
          contentHash: intent.contentHash,
        ),
    ];
  }

  @override
  Future<void> forgetExplicitIntent(String operationId) async {
    final shared = await journal.pendingIntents();
    if (shared.any((intent) => intent.operationId == operationId)) {
      await journal.acknowledge(operationId);
    } else {
      await files.forgetExplicitIntent(operationId);
    }
  }

  @override
  Future<Set<String>> explicitDeletedKeys() async => {
    ...await files.explicitDeletedKeys(),
    for (final intent in await journal.pendingIntents())
      if (intent.kind == SharedJournalIntentKind.delete) intent.key,
  };

  @override
  Future<void> forgetExplicitDelete(String key) async {
    for (final intent in await journal.pendingIntents()) {
      if (intent.key == key && intent.kind == SharedJournalIntentKind.delete) {
        await journal.acknowledge(intent.operationId);
      }
    }
    await files.forgetExplicitDelete(key);
  }

  @override
  Future<void> close() async {
    _closed = true;
    _journalPoller.cancel();
    await _pollCompleted?.future;
    await _fileChanges.cancel();
    if (_backgroundTasks.isNotEmpty) {
      await Future.wait(_backgroundTasks.toList());
    }
    await files.close();
    await _changes.close();
  }

  void _forwardFileChange(StoreChange change) {
    final task = _classifyAndEmitFileChange(change);
    _backgroundTasks.add(task);
    unawaited(task.whenComplete(() => _backgroundTasks.remove(task)));
  }

  Future<void> _pollJournalIntents() async {
    if (_closed || _pollingJournal || _journalPollingDisabled) return;
    _pollingJournal = true;
    final completed = Completer<void>();
    _pollCompleted = completed;
    try {
      for (final intent in await journal.pendingIntents()) {
        if (!_announcedIntentIds.add(intent.operationId)) continue;
        _emit(
          StoreChange(
            intent.key,
            StoreMutationOrigin.application,
            deleted: intent.kind == SharedJournalIntentKind.delete,
          ),
        );
      }
    } on Object {
      // explicitIntents() remains the fail-fast corruption boundary used by
      // sync. Disable background polling to avoid an unhandled timer error.
      _journalPollingDisabled = true;
    } finally {
      _pollingJournal = false;
      if (_pollCompleted == completed) _pollCompleted = null;
      completed.complete();
    }
  }

  Future<void> _classifyAndEmitFileChange(StoreChange change) async {
    if (_closed) return;
    if (change.origin != StoreMutationOrigin.external || change.key.isEmpty) {
      _emit(change);
      return;
    }

    List<SharedJournalIntent> pending;
    try {
      pending = await journal.pendingIntents();
    } on Object {
      _emit(change);
      return;
    }
    for (final intent in pending) {
      if (intent.key != change.key) continue;
      if (change.deleted && intent.kind == SharedJournalIntentKind.delete) {
        _emit(
          StoreChange(
            change.key,
            StoreMutationOrigin.application,
            deleted: true,
          ),
        );
        return;
      }
      if (!change.deleted && intent.contentHash != null) {
        final bytes = await files.readBytes(change.key);
        if (bytes != null && _sha256(bytes) == intent.contentHash) {
          _emit(StoreChange(change.key, StoreMutationOrigin.application));
          return;
        }
      }
    }
    _emit(change);
  }

  void _emit(StoreChange change) {
    if (!_closed) _changes.add(change);
  }

  String _operationId(String key, StoreMutationOrigin origin) =>
      'flutter/${DateTime.now().microsecondsSinceEpoch}/$pid/${origin.name}/${p.basenameWithoutExtension(key)}';
}

String _sha256(List<int> bytes) {
  // SharedMcpJournal validates this value against the document bytes. Keeping
  // hashing in that implementation avoids a second journal format.
  return SharedMcpJournal.contentHash(bytes);
}
