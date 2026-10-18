import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../l10n/l10n.dart';
import '../../repositories/bubble_repository.dart';
import '../../services/bubble_document_store.dart';
import '../../services/home_exposure_service.dart';
import '../../viewmodels/bubble_view_models.dart';
import '../recommendations/note_detail.dart';
import '../recommendations/note_profile.dart';
import '../bubble_list/bubble_list_page.dart';
import 'bubble_field.dart';
import 'ocean_background.dart';
import 'red_note_grid.dart';
import '../../services/visual_theme_service.dart';

class OceanPage extends ConsumerStatefulWidget {
  const OceanPage({super.key});

  @override
  ConsumerState<OceanPage> createState() => _OceanPageState();
}

class _OceanPageState extends ConsumerState<OceanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  List<Bubble>? _displayedBatch;
  final Set<String> _exposedIds = {};

  Widget _presentBubbles(List<Bubble> bubbles, bool redNote) {
    if (!identical(_displayedBatch, bubbles)) {
      _displayedBatch = bubbles;
      _exposedIds.clear();
    }
    void recordVisible(List<Bubble> visible) {
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final fresh = visible
          .where((note) => !_exposedIds.contains(note.id))
          .toList();
      if (fresh.isEmpty) return;
      _exposedIds.addAll(fresh.map((note) => note.id));
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted ||
            !(ModalRoute.of(context)?.isCurrent ?? true) ||
            !identical(ref.read(displayBubblesProvider).valueOrNull, bubbles)) {
          if (identical(_displayedBatch, bubbles)) {
            _exposedIds.removeAll(fresh.map((note) => note.id));
          }
          return;
        }
        await ref.read(homeExposureRecorderProvider)(fresh);
        if (mounted && ref.exists(bubbleRepositoryProvider)) {
          final repository = ref.read(bubbleRepositoryProvider);
          for (final note in fresh) {
            unawaited(
              repository.ensureCover(note).catchError((Object error) {
                debugPrint('Could not cache note cover: $error');
              }),
            );
          }
        }
      });
    }

    if (bubbles.isEmpty) return Center(child: Text(context.l10n.noBubblesYet));
    if (redNote) {
      recordVisible(bubbles);
      return RedNoteGrid(
        bubbles: bubbles,
        onBubbleTap: _showBubble,
        documentStore: ref.read(bubbleDocumentStoreProvider),
      );
    }
    final needsAttachments = bubbles.any(
      (note) =>
          note.cover?.posterUri != null ||
          note.cover?.imageUri?.startsWith('assets/') == true ||
          note.description.contains('](assets/'),
    );
    return BubbleField(
      key: ValueKey(ref.watch(homeRefreshVersionProvider)),
      bubbles: bubbles,
      onBubbleTap: _showBubble,
      documentStore: needsAttachments || ref.exists(bubbleDocumentStoreProvider)
          ? ref.read(bubbleDocumentStoreProvider)
          : null,
      onVisibleChanged: recordVisible,
    );
  }

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _refreshBubbles() =>
      ref.read(homeRefreshVersionProvider.notifier).state++;

  @override
  Widget build(BuildContext context) {
    final redNote = ref.watch(visualThemeProvider) == VisualTheme.redNote;
    final page = Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: redNote
                ? ColoredBox(color: context.appBackground)
                : AnimatedBuilder(
                    animation: _animation,
                    builder: (_, __) =>
                        OceanBackground(progress: _animation.value),
                  ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.appTitle,
                              style: const TextStyle(fontSize: 25),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _refreshBubbles,
                        icon: const Icon(Icons.refresh_rounded, size: 19),
                        label: Text(context.l10n.refreshBubbles),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: redNote ? '切换海洋主题' : '切换小红书主题',
                        icon: Icon(
                          redNote ? Icons.water_outlined : Icons.style_outlined,
                        ),
                        onPressed: () =>
                            ref.read(visualThemeProvider.notifier).toggle(),
                      ),
                      IconButton(
                        tooltip: context.l10n.manageBubbles,
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BubbleListPage(),
                            ),
                          );
                          if (mounted) _refreshBubbles();
                        },
                        icon: const Icon(Icons.format_list_bulleted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ref
                      .watch(displayBubblesProvider)
                      .when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                          child: Text(context.l10n.scheduleError('$error')),
                        ),
                        data: (bubbles) => _presentBubbles(bubbles, redNote),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.f5): _refreshBubbles},
      child: Focus(autofocus: true, child: page),
    );
  }

  Future<void> _showBubble(Bubble bubble) => showNoteDetail(
    context: context,
    ref: ref,
    channel: RecommendationChannel.home,
    bubble: bubble,
    onEdit: () => _editBubble(bubble),
    onDelete: () => ref.read(bubbleRepositoryProvider).delete(bubble.id),
  );

  Future<void> _editBubble(Bubble bubble) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BubbleEditorDialog(bubble: bubble),
    );
    if (saved == true) {
      ref.read(bubbleRevisionProvider.notifier).state++;
    }
  }
}
