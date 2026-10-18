import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import '../../services/visual_theme_service.dart';
import '../note_cover/note_cover_artwork.dart';

class RedNoteGrid extends StatelessWidget {
  const RedNoteGrid({
    required this.bubbles,
    required this.onBubbleTap,
    this.documentStore,
    super.key,
  });
  final List<Bubble> bubbles;
  final ValueChanged<Bubble> onBubbleTap;
  final BubbleDocumentStore? documentStore;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const maxFeedWidth = 1320.0;
      final available = constraints.maxWidth.clamp(0.0, maxFeedWidth);
      final columnCount = (available / 250).floor().clamp(2, 5);
      final columns = List.generate(columnCount, (_) => <Widget>[]);
      for (var index = 0; index < bubbles.length; index++) {
        final note = bubbles[index];
        columns[index % columnCount].add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              container: true,
              label: note.title,
              button: true,
              child: Material(
                color: RedNoteColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                    color: RedNoteColors.border,
                    width: .7,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onBubbleTap(note),
                  child: AspectRatio(
                    aspectRatio: index.isEven ? .92 : 1.05,
                    child: ExcludeSemantics(
                      child: NoteCoverArtwork(
                        note: note,
                        documentStore: documentStore,
                        circular: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxFeedWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 6, 2, 20),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.feedTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: RedNoteColors.text,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        Localizations.localeOf(context).languageCode == 'zh'
                            ? '${bubbles.length} 条笔记'
                            : '${bubbles.length} notes',
                        style: const TextStyle(
                          fontSize: 12,
                          color: RedNoteColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < columnCount; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: columns[i],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
