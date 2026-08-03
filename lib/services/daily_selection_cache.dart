import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/daily_selection.dart';

final dailySelectionCacheProvider = Provider<DailySelectionCache>(
  (_) => throw UnimplementedError(),
);

class DailySelectionCache {
  DailySelectionCache._(this.file);

  final File file;

  factory DailySelectionCache.forTesting(File file) =>
      DailySelectionCache._(file);

  static Future<DailySelectionCache> open() async {
    final support = await getApplicationSupportDirectory();
    return DailySelectionCache._(
      File(
        path.join(support.path, 'MindBubble', 'cache', 'daily-selection.json'),
      ),
    );
  }

  Future<DailySelection?> read(String date) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?> || decoded['date'] != date) {
        return null;
      }
      final ids = decoded['bubbleIds'];
      final generatedAt = decoded['generatedAt'];
      if (ids is! List || generatedAt is! num) return null;
      return DailySelection(
        date: date,
        bubbleIds: ids.whereType<String>().toList(),
        generatedAt: DateTime.fromMillisecondsSinceEpoch(generatedAt.toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(DailySelection selection) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'date': selection.date,
        'bubbleIds': selection.bubbleIds,
        'generatedAt': selection.generatedAt.millisecondsSinceEpoch,
      }),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}
