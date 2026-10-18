import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../repositories/bubble_repository.dart';
import '../../services/bubble_document_store.dart';
import '../../widgets/bubble_detail_dialog.dart';
import 'note_profile.dart';
import 'note_profile_dialog.dart';
import 'recommendation_service.dart';

Future<void> showNoteDetail({
  required BuildContext context,
  required WidgetRef ref,
  required Bubble bubble,
  required RecommendationChannel channel,
  VoidCallback? onEdit,
  Future<void> Function()? onDelete,
}) async {
  final repository = ref.read(bubbleRepositoryProvider);
  final recommendations = ref.read(recommendationServiceProvider);
  await repository.recordBehavior(
    bubble.id,
    RecommendationEventType.opened,
    channel: channel,
  );
  if (channel == RecommendationChannel.search) {
    await repository.recordBehavior(
      bubble.id,
      RecommendationEventType.searched,
      channel: channel,
    );
  }
  if (!context.mounted) return;
  final reading = Completer<double>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => BubbleDetailDialog(
      bubble: bubble,
      onReadingComplete: (seconds) {
        if (!reading.isCompleted) reading.complete(seconds);
      },
      documentStore: ref.read(bubbleDocumentStoreProvider),
      onFrequencyChanged: (frequency) =>
          repository.updateFrequency(bubble.id, frequency),
      onFeedback: (value) async {
        await recommendations.feedback(bubble.id, value, channel);
        return repository.getById(bubble.id);
      },
      onProfile: (current) async {
        final edited = await showDialog<Bubble>(
          context: dialogContext,
          builder: (_) => NoteProfileDialog(bubble: current),
        );
        if (edited != null) await repository.save(edited, analyze: false);
        return edited;
      },
      onReanalyze: () async {
        final current = await repository.getById(bubble.id);
        if (current == null) return null;
        await repository.analyzeNotes([current]);
        return repository.getById(bubble.id);
      },
      onEdit: onEdit,
      onDelete: onDelete,
    ),
  );
  await repository.recordBehavior(
    bubble.id,
    RecommendationEventType.read,
    channel: channel,
    durationSeconds: await reading.future,
  );
}
