import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const sharedMcpJournalProtocolVersion = 1;

enum SharedJournalIntentKind { create, update, delete }

final class SharedJournalConflict implements Exception {
  const SharedJournalConflict(this.message);

  final String message;

  @override
  String toString() => 'SharedJournalConflict: $message';
}

final class SharedJournalCorruption implements Exception {
  const SharedJournalCorruption(this.message);

  final String message;

  @override
  String toString() => 'SharedJournalCorruption: $message';
}

final class SharedJournalIntent {
  const SharedJournalIntent({
    required this.operationId,
    required this.key,
    required this.kind,
    required this.origin,
    required this.createdAt,
    required this.contentHash,
  });

  final String operationId;
  final String key;
  final SharedJournalIntentKind kind;
  final String origin;
  final DateTime createdAt;
  final String? contentHash;
}

final class SharedJournalMutationResult {
  const SharedJournalMutationResult({
    required this.operationId,
    required this.replayed,
    required this.result,
  });

  final String operationId;
  final bool replayed;
  final Object? result;
}

/// Cross-process write-ahead journal used by MindBubble and its Python MCP.
///
/// Both [documentRoot] and [journalRoot] must be absolute paths resolved by the
/// application. The journal root must not be inside the visible document root.
/// Every event is an immutable, checksummed JSON file; byte range 0..1 of
/// `journal.lock` serializes Dart and Python writers.
final class SharedMcpJournal {
  SharedMcpJournal({
    required Directory documentRoot,
    required Directory journalRoot,
  }) : documentRoot = Directory(p.normalize(documentRoot.absolute.path)),
       journalRoot = Directory(p.normalize(journalRoot.absolute.path)) {
    if (!p.isAbsolute(documentRoot.path) || !p.isAbsolute(journalRoot.path)) {
      throw ArgumentError('documentRoot and journalRoot must be absolute');
    }
    if (p.equals(this.documentRoot.path, this.journalRoot.path) ||
        p.isWithin(this.documentRoot.path, this.journalRoot.path)) {
      throw ArgumentError('journalRoot must be outside documentRoot');
    }
  }

  final Directory documentRoot;
  final Directory journalRoot;

  static String contentHash(List<int> bytes) => _sha256(bytes);

  Directory get _entriesRoot => Directory(p.join(journalRoot.path, 'entries'));
  File get _lockFile => File(p.join(journalRoot.path, 'journal.lock'));

  Future<SharedJournalMutationResult> mutate({
    required String operationId,
    required String objectId,
    required SharedJournalIntentKind kind,
    required String? expectedContentHash,
    required List<int>? documentBytes,
    required Object? request,
    required Object? result,
  }) async {
    _validateOperationId(operationId);
    _validateObjectId(objectId);
    if (kind == SharedJournalIntentKind.create && expectedContentHash != null) {
      throw ArgumentError('create must not have an expectedContentHash');
    }
    if (kind != SharedJournalIntentKind.create &&
        (expectedContentHash == null || expectedContentHash.isEmpty)) {
      throw ArgumentError('${kind.name} requires expectedContentHash');
    }
    if (kind == SharedJournalIntentKind.delete && documentBytes != null) {
      throw ArgumentError('delete must not contain document bytes');
    }
    if (kind != SharedJournalIntentKind.delete && documentBytes == null) {
      throw ArgumentError('${kind.name} requires document bytes');
    }

    final contentHash = documentBytes == null ? null : _sha256(documentBytes);
    final payloadBase64 = documentBytes == null
        ? null
        : base64Encode(documentBytes);
    final requestChecksum = _sha256(
      utf8.encode(
        _canonicalJson({
          'version': sharedMcpJournalProtocolVersion,
          'operationId': operationId,
          'objectId': objectId,
          'kind': kind.name,
          'expectedContentHash': expectedContentHash,
          'request': request,
        }),
      ),
    );

    return _withLock(() async {
      final state = await _loadState();
      await _recoverLocked(state);
      final existing = state.entries[operationId];
      if (existing != null) {
        final prepared = existing.prepared;
        if (prepared['requestChecksum'] != requestChecksum) {
          throw const SharedJournalConflict(
            'operationId was already used for a different request',
          );
        }
        return SharedJournalMutationResult(
          operationId: operationId,
          replayed: true,
          result: prepared['result'],
        );
      }

      final target = File(p.join(documentRoot.path, '$objectId.md'));
      final currentHash = await target.exists()
          ? _sha256(await target.readAsBytes())
          : null;
      if (currentHash != expectedContentHash) {
        throw SharedJournalConflict(
          '$operationId: expected $expectedContentHash, found $currentHash',
        );
      }

      final prepared = <String, Object?>{
        'version': sharedMcpJournalProtocolVersion,
        'sequence': state.nextSequence,
        'phase': 'prepared',
        'operationId': operationId,
        'requestChecksum': requestChecksum,
        'expectedContentHash': expectedContentHash,
        'payloadBase64': payloadBase64,
        'result': result,
        'intent': <String, Object?>{
          'operationId': operationId,
          'key': '$objectId.md',
          'kind': kind.name,
          'origin': 'application',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'contentHash': contentHash,
        },
      };
      await _appendEvent(prepared);
      state.addPrepared(prepared);
      await _recoverOperationLocked(state, operationId);
      return SharedJournalMutationResult(
        operationId: operationId,
        replayed: false,
        result: result,
      );
    });
  }

  Future<void> recover() => _withLock(() async {
    await _recoverLocked(await _loadState());
  });

  /// Imports a delete already completed by the archived sync implementation.
  /// Callers must independently verify the legacy marker against its durable
  /// state before invoking this method.
  Future<void> importAppliedDeleteIntent({
    required String operationId,
    required String objectId,
    required DateTime createdAt,
  }) async {
    _validateOperationId(operationId);
    _validateObjectId(objectId);
    await _withLock(() async {
      final state = await _loadState();
      await _recoverLocked(state);
      if (state.entries.containsKey(operationId)) return;
      final target = File(p.join(documentRoot.path, '$objectId.md'));
      if (await target.exists()) {
        throw SharedJournalConflict(
          '$operationId: verified legacy delete target still exists',
        );
      }
      final prepared = <String, Object?>{
        'version': sharedMcpJournalProtocolVersion,
        'sequence': state.nextSequence,
        'phase': 'prepared',
        'operationId': operationId,
        'requestChecksum': _sha256(
          utf8.encode('legacy-delete\n$operationId\n$objectId'),
        ),
        'expectedContentHash': null,
        'payloadBase64': null,
        'result': {'id': objectId, 'imported': true},
        'intent': <String, Object?>{
          'operationId': operationId,
          'key': '$objectId.md',
          'kind': SharedJournalIntentKind.delete.name,
          'origin': 'application',
          'createdAt': createdAt.toUtc().toIso8601String(),
          'contentHash': null,
        },
      };
      await _appendEvent(prepared);
      state.addPrepared(prepared);
      final applied = <String, Object?>{
        'version': sharedMcpJournalProtocolVersion,
        'sequence': state.nextSequence,
        'phase': 'applied',
        'operationId': operationId,
        'resultContentHash': null,
      };
      await _appendEvent(applied);
      state.addApplied(applied);
    });
  }

  Future<List<SharedJournalIntent>> pendingIntents() => _withLock(() async {
    final state = await _loadState();
    await _recoverLocked(state);
    final pending = <SharedJournalIntent>[];
    for (final entry in state.entries.values) {
      if (entry.applied == null || entry.acknowledged != null) continue;
      final raw = (entry.prepared['intent']! as Map).cast<String, Object?>();
      pending.add(
        SharedJournalIntent(
          operationId: raw['operationId']! as String,
          key: raw['key']! as String,
          kind: SharedJournalIntentKind.values.byName(raw['kind']! as String),
          origin: raw['origin']! as String,
          createdAt: DateTime.parse(raw['createdAt']! as String).toUtc(),
          contentHash: raw['contentHash'] as String?,
        ),
      );
    }
    return pending;
  });

  Future<void> acknowledge(String operationId) async {
    _validateOperationId(operationId);
    await _withLock(() async {
      final state = await _loadState();
      await _recoverLocked(state);
      final entry = state.entries[operationId];
      if (entry == null || entry.applied == null) {
        throw const SharedJournalConflict(
          'cannot acknowledge an unapplied operation',
        );
      }
      if (entry.acknowledged != null) return;
      final event = <String, Object?>{
        'version': sharedMcpJournalProtocolVersion,
        'sequence': state.nextSequence,
        'phase': 'acknowledged',
        'operationId': operationId,
      };
      await _appendEvent(event);
      state.addAcknowledged(event);
    });
  }

  /// Writes only a prepare event so tests can model termination before apply.
  Future<void> prepareForTesting({
    required String operationId,
    required String objectId,
    required SharedJournalIntentKind kind,
    required String? expectedContentHash,
    required List<int>? documentBytes,
    required Object? request,
    required Object? result,
  }) async {
    _validateOperationId(operationId);
    _validateObjectId(objectId);
    final requestChecksum = _sha256(
      utf8.encode(
        _canonicalJson({
          'version': sharedMcpJournalProtocolVersion,
          'operationId': operationId,
          'objectId': objectId,
          'kind': kind.name,
          'expectedContentHash': expectedContentHash,
          'request': request,
        }),
      ),
    );
    await _withLock(() async {
      final state = await _loadState();
      final event = <String, Object?>{
        'version': sharedMcpJournalProtocolVersion,
        'sequence': state.nextSequence,
        'phase': 'prepared',
        'operationId': operationId,
        'requestChecksum': requestChecksum,
        'expectedContentHash': expectedContentHash,
        'payloadBase64': documentBytes == null
            ? null
            : base64Encode(documentBytes),
        'result': result,
        'intent': <String, Object?>{
          'operationId': operationId,
          'key': '$objectId.md',
          'kind': kind.name,
          'origin': 'application',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'contentHash': documentBytes == null ? null : _sha256(documentBytes),
        },
      };
      await _appendEvent(event);
    });
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    await journalRoot.create(recursive: true);
    final lock = await _lockFile.open(mode: FileMode.append);
    try {
      if (await lock.length() == 0) {
        await lock.writeByte(0);
        await lock.flush();
      }
      await lock.setPosition(0);
      await lock.lock(FileLock.blockingExclusive, 0, 1);
      return await action();
    } finally {
      try {
        await lock.unlock(0, 1);
      } on FileSystemException {
        // A failed action can close or invalidate a platform lock; close still
        // releases it. Preserve the original exception.
      }
      await lock.close();
    }
  }

  Future<_JournalState> _loadState() async {
    final state = _JournalState();
    if (!await _entriesRoot.exists()) return state;
    final files = await _entriesRoot
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      Object? decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } on Object catch (error) {
        throw SharedJournalCorruption(
          'invalid journal event ${p.basename(file.path)}: $error',
        );
      }
      if (decoded is! Map ||
          decoded['version'] != sharedMcpJournalProtocolVersion) {
        throw SharedJournalCorruption(
          'unsupported journal event ${p.basename(file.path)}',
        );
      }
      final event = decoded.cast<String, Object?>();
      if (event['checksum'] != _checksumEvent(event)) {
        throw SharedJournalCorruption(
          'checksum mismatch in ${p.basename(file.path)}',
        );
      }
      state.add(event);
    }
    return state;
  }

  Future<void> _recoverLocked(_JournalState state) async {
    final pending =
        state.entries.entries
            .where((entry) => entry.value.applied == null)
            .toList()
          ..sort(
            (left, right) => (left.value.prepared['sequence']! as int)
                .compareTo(right.value.prepared['sequence']! as int),
          );
    for (final entry in pending) {
      await _recoverOperationLocked(state, entry.key);
    }
  }

  Future<void> _recoverOperationLocked(
    _JournalState state,
    String operationId,
  ) async {
    final prepared = state.entries[operationId]!.prepared;
    final intent = (prepared['intent']! as Map).cast<String, Object?>();
    final target = File(p.join(documentRoot.path, intent['key']! as String));
    final currentHash = await target.exists()
        ? _sha256(await target.readAsBytes())
        : null;
    final expectedHash = prepared['expectedContentHash'] as String?;
    final resultHash = intent['contentHash'] as String?;
    final kind = SharedJournalIntentKind.values.byName(
      intent['kind']! as String,
    );
    final alreadyApplied = kind == SharedJournalIntentKind.delete
        ? currentHash == null
        : currentHash == resultHash;
    if (!alreadyApplied) {
      if (currentHash != expectedHash) {
        throw SharedJournalConflict(
          '$operationId: expected $expectedHash, found $currentHash',
        );
      }
      if (kind == SharedJournalIntentKind.delete) {
        await target.delete();
      } else {
        final payload = base64Decode(prepared['payloadBase64']! as String);
        if (_sha256(payload) != resultHash) {
          throw SharedJournalCorruption(
            '$operationId: payload checksum does not match intent',
          );
        }
        await _atomicWrite(target, payload);
      }
    }
    final event = <String, Object?>{
      'version': sharedMcpJournalProtocolVersion,
      'sequence': state.nextSequence,
      'phase': 'applied',
      'operationId': operationId,
      'resultContentHash': resultHash,
    };
    await _appendEvent(event);
    state.addApplied(event);
  }

  Future<void> _appendEvent(Map<String, Object?> event) async {
    await _entriesRoot.create(recursive: true);
    final signed = <String, Object?>{
      ...event,
      'checksum': _checksumEvent(event),
    };
    final operationHash = _sha256(
      utf8.encode(event['operationId']! as String),
    ).substring(0, 16);
    final sequence = (event['sequence']! as int).toString().padLeft(20, '0');
    final target = File(
      p.join(
        _entriesRoot.path,
        '$sequence-$operationHash-${event['phase']}.json',
      ),
    );
    if (await target.exists()) {
      throw SharedJournalCorruption(
        'journal event already exists: ${p.basename(target.path)}',
      );
    }
    await _atomicWrite(target, utf8.encode('${_canonicalJson(signed)}\n'));
  }

  Future<void> _atomicWrite(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final nonce = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final temporary = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.$nonce.mbj-tmp',
    );
    final previous = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.$nonce.mbj-old',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await _renameWithRetry(target, previous.path);
      try {
        await _renameWithRetry(temporary, target.path);
        if (await previous.exists()) await _deleteWithRetry(previous);
      } on Object {
        if (!await target.exists() && await previous.exists()) {
          await _renameWithRetry(previous, target.path);
        }
        rethrow;
      }
    } finally {
      if (await temporary.exists()) await _deleteWithRetry(temporary);
    }
  }

  Future<void> _renameWithRetry(File source, String target) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      try {
        await source.rename(target);
        return;
      } on FileSystemException {
        if (attempt == 39) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
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
}

final class _JournalEntry {
  _JournalEntry(this.prepared);

  final Map<String, Object?> prepared;
  Map<String, Object?>? applied;
  Map<String, Object?>? acknowledged;
}

final class _JournalState {
  final Map<String, _JournalEntry> entries = {};
  final Set<int> _sequences = {};
  int _maximumSequence = 0;

  int get nextSequence => _maximumSequence + 1;

  void add(Map<String, Object?> event) {
    final sequence = event['sequence'];
    if (sequence is! int || sequence <= 0 || !_sequences.add(sequence)) {
      throw const SharedJournalCorruption('invalid or duplicate sequence');
    }
    _maximumSequence = max(_maximumSequence, sequence);
    final operationId = event['operationId'];
    if (operationId is! String) {
      throw const SharedJournalCorruption('event has no operationId');
    }
    _validateOperationId(operationId);
    switch (event['phase']) {
      case 'prepared':
        return addPrepared(event, sequenceAlreadyAdded: true);
      case 'applied':
        return addApplied(event, sequenceAlreadyAdded: true);
      case 'acknowledged':
        return addAcknowledged(event, sequenceAlreadyAdded: true);
      default:
        throw const SharedJournalCorruption('unknown journal phase');
    }
  }

  void addPrepared(
    Map<String, Object?> event, {
    bool sequenceAlreadyAdded = false,
  }) {
    if (!sequenceAlreadyAdded) _recordNewSequence(event);
    final operationId = event['operationId']! as String;
    if (entries.containsKey(operationId)) {
      throw SharedJournalCorruption('duplicate prepare for $operationId');
    }
    final intent = event['intent'];
    if (intent is! Map ||
        intent['operationId'] != operationId ||
        intent['origin'] != 'application' ||
        intent['key'] is! String ||
        !(intent['key']! as String).endsWith('.md') ||
        event['requestChecksum'] is! String) {
      throw SharedJournalCorruption('invalid intent for $operationId');
    }
    _validateObjectId(
      (intent['key']! as String).substring(
        0,
        (intent['key']! as String).length - 3,
      ),
    );
    SharedJournalIntentKind.values.byName(intent['kind']! as String);
    entries[operationId] = _JournalEntry(event);
  }

  void addApplied(
    Map<String, Object?> event, {
    bool sequenceAlreadyAdded = false,
  }) {
    if (!sequenceAlreadyAdded) _recordNewSequence(event);
    final operationId = event['operationId']! as String;
    final entry = entries[operationId];
    if (entry == null || entry.applied != null) {
      throw SharedJournalCorruption('invalid applied event for $operationId');
    }
    entry.applied = event;
  }

  void addAcknowledged(
    Map<String, Object?> event, {
    bool sequenceAlreadyAdded = false,
  }) {
    if (!sequenceAlreadyAdded) _recordNewSequence(event);
    final operationId = event['operationId']! as String;
    final entry = entries[operationId];
    if (entry?.applied == null || entry!.acknowledged != null) {
      throw SharedJournalCorruption(
        'invalid acknowledged event for $operationId',
      );
    }
    entry.acknowledged = event;
  }

  void _recordNewSequence(Map<String, Object?> event) {
    final sequence = event['sequence']! as int;
    if (!_sequences.add(sequence)) {
      throw const SharedJournalCorruption('duplicate sequence');
    }
    _maximumSequence = max(_maximumSequence, sequence);
  }
}

final _objectIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$');
final _operationIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$');

void _validateObjectId(String value) {
  if (!_objectIdPattern.hasMatch(value)) {
    throw ArgumentError("invalid object ID '$value'");
  }
}

void _validateOperationId(String value) {
  if (!_operationIdPattern.hasMatch(value)) {
    throw ArgumentError("invalid operation ID '$value'");
  }
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

String _checksumEvent(Map<String, Object?> event) {
  final unsigned = <String, Object?>{
    for (final entry in event.entries)
      if (entry.key != 'checksum') entry.key: entry.value,
  };
  return _sha256(utf8.encode(_canonicalJson(unsigned)));
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}
