import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/database.dart';
import '../models/bubble.dart';
import '../models/daily_selection.dart';
import '../services/sync_service.dart';

final bubbleRevisionProvider = StateProvider<int>((_) => 0);
final databaseDataVersionProvider = StreamProvider<int>((ref) async* {
  final database = ref.watch(databaseProvider).connection;
  var last = -1;
  while (true) {
    final value =
        (await database.rawQuery('PRAGMA data_version')).single.values.first
            as int;
    if (value != last) {
      last = value;
      yield value;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
});
final bubbleRepositoryProvider = Provider<BubbleRepository>(
  (ref) => BubbleRepository(ref.watch(databaseProvider).connection, () {
    ref.read(bubbleRevisionProvider.notifier).state++;
    final service = ref.read(syncServiceProvider);
    unawaited(
      service
          .loadConfig()
          .then((_) => service.scheduleSync())
          .catchError((Object _) {}),
    );
  }),
);

class BubbleRepository {
  BubbleRepository(this._database, this._changed);
  final Database _database;
  final void Function() _changed;

  Future<List<Bubble>> getAll({
    String query = '',
    bool includeDeleted = false,
  }) async {
    final normalized = query.trim();
    final clauses = <String>[
      if (!includeDeleted) 'deleted_at IS NULL',
      if (normalized.isNotEmpty) '(title LIKE ? OR description LIKE ?)',
    ];
    final rows = await _database.query(
      'bubbles',
      where: clauses.join(' AND '),
      whereArgs: normalized.isEmpty ? null : List.filled(2, '%$normalized%'),
      orderBy: 'updated_at DESC',
    );
    return rows.map(Bubble.fromMap).toList();
  }

  Future<void> save(Bubble bubble) async {
    await _database.insert(
      'bubbles',
      bubble.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changed();
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.update(
      'bubbles',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<Bubble?> getById(String id, {bool includeDeleted = false}) async {
    final rows = await _database.query(
      'bubbles',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Bubble.fromMap(rows.single);
  }

  Future<void> updateFrequency(String id, int frequency) async {
    if (frequency < 1 || frequency > 5) {
      throw ArgumentError.value(frequency, 'frequency');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.update(
      'bubbles',
      {'appearance_frequency': frequency, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changed();
  }

  Future<DailySelection?> getDailySelection(String date) async {
    final rows = await _database.query(
      'daily_selections',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return DailySelection(
      date: row['date']! as String,
      bubbleIds: (row['bubble_ids']! as String)
          .split(',')
          .where((id) => id.isNotEmpty)
          .toList(),
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['generated_at']! as int,
      ),
    );
  }

  Future<void> saveDailySelection(DailySelection selection) =>
      _database.insert('daily_selections', {
        'date': selection.date,
        'bubble_ids': selection.bubbleIds.join(','),
        'generated_at': selection.generatedAt.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> recordShown(List<String> ids, DateTime shownAt) async {
    final batch = _database.batch();
    for (final id in ids) {
      batch.rawUpdate(
        'UPDATE bubbles SET last_shown_at = ?, shown_count = shown_count + 1, updated_at = ? WHERE id = ?',
        [shownAt.millisecondsSinceEpoch, shownAt.millisecondsSinceEpoch, id],
      );
    }
    await batch.commit(noResult: true);
    _changed();
  }
}
