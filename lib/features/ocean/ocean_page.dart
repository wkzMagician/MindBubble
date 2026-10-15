import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../l10n/l10n.dart';
import '../../repositories/bubble_repository.dart';
import '../../services/bubble_document_store.dart';
import '../../viewmodels/bubble_view_models.dart';
import '../../widgets/bubble_detail_dialog.dart';
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

  @override
  Widget build(BuildContext context) {
    final redNote = ref.watch(visualThemeProvider) == VisualTheme.redNote;
    return Scaffold(
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
                            const SizedBox(height: 4),
                            Text(context.l10n.todaySubtitle),
                          ],
                        ),
                      ),
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
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BubbleListPage(),
                          ),
                        ),
                        icon: const Icon(Icons.format_list_bulleted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ref
                      .watch(todayBubblesProvider)
                      .when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                          child: Text(context.l10n.scheduleError('$error')),
                        ),
                        data: (bubbles) => bubbles.isEmpty
                            ? Center(child: Text(context.l10n.noBubblesYet))
                            : redNote
                            ? RedNoteGrid(
                                bubbles: bubbles,
                                onBubbleTap: _showBubble,
                                documentStore: ref.read(
                                  bubbleDocumentStoreProvider,
                                ),
                              )
                            : BubbleField(
                                bubbles: bubbles,
                                onBubbleTap: _showBubble,
                              ),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBubble(Bubble bubble) => showDialog<void>(
    context: context,
    builder: (context) => BubbleDetailDialog(
      bubble: bubble,
      documentStore: ref.read(bubbleDocumentStoreProvider),
      onFrequencyChanged: (frequency) => ref
          .read(bubbleRepositoryProvider)
          .updateFrequency(bubble.id, frequency),
      onEdit: () => _editBubble(bubble),
      onDelete: () => ref.read(bubbleRepositoryProvider).delete(bubble.id),
    ),
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
