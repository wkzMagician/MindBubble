import 'package:dartloom_model/dartloom_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../repositories/bubble_repository.dart';
import '../model_settings/model_settings.dart';
import 'note_analyzer.dart';

bool noteNeedsAnalysis(Bubble note) =>
    !note.isDeleted &&
    !const {
      'ready',
      'embedding_pending',
    }.contains(note.effectiveProfile.analysisStatus);

enum PendingAnalysisIssue {
  unconfigured,
  invalidConfiguration,
  modelFailed,
  storageFailed,
}

class PendingNoteAnalysisState {
  const PendingNoteAnalysisState({
    this.isRunning = false,
    this.total = 0,
    this.processed = 0,
    this.analyzed = 0,
    this.failed = 0,
    this.skipped = 0,
    this.issue,
  });

  final bool isRunning;
  final int total;
  final int processed;
  final int analyzed;
  final int failed;
  final int skipped;
  final PendingAnalysisIssue? issue;
}

final pendingNoteAnalysisProvider =
    StateNotifierProvider<
      PendingNoteAnalysisController,
      PendingNoteAnalysisState
    >(
      (ref) => PendingNoteAnalysisController(
        ref.watch(bubbleRepositoryProvider),
        ref.watch(modelSettingsRepositoryProvider),
      ),
    );

class PendingNoteAnalysisController
    extends StateNotifier<PendingNoteAnalysisState> {
  PendingNoteAnalysisController(this._repository, this._models)
    : super(const PendingNoteAnalysisState());

  final BubbleRepository _repository;
  final ModelSettingsRepository _models;

  Future<PendingAnalysisIssue?> _checkModel() async {
    try {
      final settings = await _models.load();
      if (!settings.configured) return PendingAnalysisIssue.unconfigured;
      if (settings.generation.access != ModelAccess.subscription) {
        final endpoint = Uri.tryParse(settings.generation.endpoint);
        if (endpoint == null ||
            !const {'http', 'https'}.contains(endpoint.scheme) ||
            !endpoint.hasAuthority ||
            endpoint.host.isEmpty) {
          return PendingAnalysisIssue.invalidConfiguration;
        }
      }
      return null;
    } on Object {
      return PendingAnalysisIssue.invalidConfiguration;
    }
  }

  /// Reads the entire library, independently of the list's search query.
  /// Keep this provider alive so changing pages cannot start a second run.
  Future<PendingNoteAnalysisState> analyzePending() async {
    if (state.isRunning) return state;
    state = const PendingNoteAnalysisState(isRunning: true);
    var total = 0, processed = 0, analyzed = 0, failed = 0, skipped = 0;

    PendingNoteAnalysisState publish({
      bool running = true,
      PendingAnalysisIssue? issue,
    }) {
      final next = PendingNoteAnalysisState(
        isRunning: running,
        total: total,
        processed: processed,
        analyzed: analyzed,
        failed: failed,
        skipped: skipped,
        issue: issue,
      );
      if (mounted) state = next;
      return next;
    }

    try {
      final notes = (await _repository.getAll())
          .where(noteNeedsAnalysis)
          .toList();
      total = notes.length;
      if (notes.isEmpty) return publish(running: false);
      final issue = await _checkModel();
      if (issue != null) return publish(running: false, issue: issue);
      publish();

      for (var offset = 0; offset < total; offset += NoteAnalyzer.batchSize) {
        if (!mounted) return publish(running: false);
        final originals = notes
            .skip(offset)
            .take(NoteAnalyzer.batchSize)
            .toList();
        final batch = <Bubble>[];
        for (final original in originals) {
          final current = await _repository.getById(original.id);
          if (current != null && noteNeedsAnalysis(current)) {
            batch.add(current);
          } else {
            skipped++;
          }
        }

        await _repository.analyzeNotes(batch);
        for (final original in batch) {
          final current = await _repository.getById(original.id);
          if (current == null ||
              current.title != original.title ||
              current.description != original.description) {
            skipped++;
          } else if (noteNeedsAnalysis(current)) {
            failed++;
          } else {
            analyzed++;
          }
        }
        processed += originals.length;
        publish();
        if (failed > 0) {
          return publish(
            running: false,
            issue: PendingAnalysisIssue.modelFailed,
          );
        }
      }
      return publish(running: false);
    } on Object {
      return publish(running: false, issue: PendingAnalysisIssue.storageFailed);
    }
  }
}
