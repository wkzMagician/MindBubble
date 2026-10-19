import 'dart:convert';
import 'dart:io';

import 'note_profile.dart';

/// Append-only per-device history, outside synchronized Markdown documents.
class RecommendationEventStore {
  RecommendationEventStore(this.file);
  RecommendationEventStore.memory() : file = null;
  final File? file;
  final Map<String, RecommendationEvent> _memory = {};
  int _knownLength = -1;
  Future<void> _tail = Future.value();

  Future<List<RecommendationEvent>> read() async {
    await _tail;
    return _read();
  }

  Future<List<RecommendationEvent>> _read() async {
    final file = this.file;
    if (file == null) return _memory.values.toList();
    if (!await file.exists()) {
      _memory.clear();
      _knownLength = 0;
      return [];
    }
    final length = await file.length();
    if (length == _knownLength) return _memory.values.toList();
    final events = <String, RecommendationEvent>{};
    for (final line in await file.readAsLines()) {
      try {
        final event = RecommendationEvent.fromJson(
          (jsonDecode(line) as Map).cast<String, Object?>(),
        );
        events[event.id] = event;
      } on Object {
        // A truncated final line must not discard the remaining history.
      }
    }
    _memory
      ..clear()
      ..addAll(events);
    _knownLength = length;
    return _memory.values.toList();
  }

  Future<bool> append(RecommendationEvent event) {
    final result = _tail.then((_) async {
      if ((await _read()).any((e) => e.id == event.id)) return false;
      final file = this.file;
      if (file == null) {
        _memory[event.id] = event;
        return true;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '\n${jsonEncode(event.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
      _memory[event.id] = event;
      _knownLength = await file.length();
      return true;
    });
    _tail = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }
}
