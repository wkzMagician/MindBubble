import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:path/path.dart' as p;

import '../models/bubble.dart';
import 'bubble_document_store.dart';

Future<Uint8List?> mindBubbleMergePolicy(SyncConflict conflict) async {
  if (conflict.base == null ||
      conflict.local == null ||
      conflict.remote == null ||
      !conflict.key.toLowerCase().endsWith('.md')) {
    return null;
  }
  final id = p.basenameWithoutExtension(conflict.key);
  final merged = mergeMindBubbleDocuments(
    id: id,
    baseRaw: utf8.decode(conflict.base!),
    localRaw: utf8.decode(conflict.local!),
    remoteRaw: utf8.decode(conflict.remote!),
  );
  return merged == null ? null : Uint8List.fromList(utf8.encode(merged));
}

String? mergeMindBubbleDocuments({
  required String id,
  required String baseRaw,
  required String localRaw,
  required String remoteRaw,
  DateTime? mergedAt,
}) {
  final base = BubbleDocumentCodec.decode(baseRaw, expectedId: id).bubble;
  final local = BubbleDocumentCodec.decode(localRaw, expectedId: id).bubble;
  final remote = BubbleDocumentCodec.decode(remoteRaw, expectedId: id).bubble;

  T? mergeValue<T>(T baseValue, T localValue, T remoteValue) {
    if (localValue == remoteValue) return localValue;
    if (localValue == baseValue) return remoteValue;
    if (remoteValue == baseValue) return localValue;
    return null;
  }

  final title = mergeValue(base.title, local.title, remote.title);
  final description = mergeValue(
    base.description,
    local.description,
    remote.description,
  );
  final frequency = mergeValue(
    base.appearanceFrequency,
    local.appearanceFrequency,
    remote.appearanceFrequency,
  );
  if (title == null || description == null || frequency == null) return null;

  final stats = <String, BubbleShowStats>{};
  for (final device in {
    ...base.shownByDevice.keys,
    ...local.shownByDevice.keys,
    ...remote.shownByDevice.keys,
  }) {
    final localStats = local.shownByDevice[device];
    final remoteStats = remote.shownByDevice[device];
    if (localStats == null) {
      if (remoteStats != null) stats[device] = remoteStats;
    } else if (remoteStats == null) {
      stats[device] = localStats;
    } else {
      final localTime = localStats.lastShownAt;
      final remoteTime = remoteStats.lastShownAt;
      stats[device] = BubbleShowStats(
        count: localStats.count > remoteStats.count
            ? localStats.count
            : remoteStats.count,
        lastShownAt: localTime == null
            ? remoteTime
            : remoteTime == null || localTime.isAfter(remoteTime)
            ? localTime
            : remoteTime,
      );
    }
  }
  final merged = Bubble(
    id: id,
    title: title,
    description: description,
    createdAt: local.createdAt.isBefore(remote.createdAt)
        ? local.createdAt
        : remote.createdAt,
    updatedAt: (mergedAt ?? DateTime.now()).toUtc(),
    appearanceFrequency: frequency,
    shownByDevice: stats,
  );
  return BubbleDocumentCodec.encode(merged, updatedBy: 'dartloom-merge');
}
