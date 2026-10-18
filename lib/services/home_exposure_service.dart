import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/recommendations/note_profile.dart';
import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';
import 'reminder_runtime.dart';

typedef HomeExposureRecorder = Future<void> Function(List<Bubble> notes);

final homeExposureRecorderProvider = Provider<HomeExposureRecorder>(
  (ref) => (notes) async {
    await ref
        .read(bubbleRepositoryProvider)
        .recordShown(
          notes.map((n) => n.id).toList(),
          DateTime.now(),
          channel: RecommendationChannel.home,
        );
    if (Platform.isAndroid || Platform.isIOS) {
      await ref.read(reminderRuntimeProvider).refreshMobileSchedule();
    }
  },
);
