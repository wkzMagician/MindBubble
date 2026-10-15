import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import '../../services/visual_theme_service.dart';

/// Responsive, content-first masonry feed used only by RedNote theme.
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

  static final _image = RegExp(
    r'!\[[^\]]*\]\((https?://[^\s)]+|assets/[0-9a-f]{64}\.[a-z]+)(?:\s+[^)]*)?\)',
  );
  static final _link = RegExp(r'\[([^\]]+)\]\([^)]+\)');
  static final _formatting = RegExp(
    r'^\s{0,3}(?:#{1,6}\s+|[-*+]\s+|>\s+)|[\x60*_~]',
    multiLine: true,
  );
  static const _paperColors = [
    Color(0xFFF2F0EB),
    Color(0xFFF0F0EE),
    Color(0xFFF2F1EF),
    Color(0xFFEFEEEB),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const maxFeedWidth = 1320.0;
      final available = constraints.maxWidth.clamp(0.0, maxFeedWidth);
      final columnCount = (available / 250).floor().clamp(2, 5);
      final columns = List.generate(columnCount, (_) => <Widget>[]);

      for (var index = 0; index < bubbles.length; index++) {
        columns[index % columnCount].add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _noteCard(bubbles[index], index),
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
                        '${bubbles.length} 条笔记',
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

  Widget _noteCard(Bubble note, int index) {
    final picture = _image.firstMatch(note.description)?.group(1);
    final preview = note.description
        .replaceAll(_image, '')
        .replaceAllMapped(_link, (match) => match.group(1) ?? '')
        .replaceAll(_formatting, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final coverText = preview.isEmpty ? note.title : preview;

    return Material(
      color: RedNoteColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: RedNoteColors.border, width: .7),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onBubbleTap(note),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (picture != null)
              AspectRatio(
                aspectRatio: index.isEven ? .92 : 1.12,
                child: _cover(picture),
              )
            else
              Container(
                height: 185.0 + (index % 3) * 26,
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
                color: _paperColors[index % _paperColors.length],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.format_quote_rounded,
                      size: 22,
                      color: Color(0xFFB9B6B0),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          coverText,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF4E4A46),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.62,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: RedNoteColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: RedNoteColors.field,
                        child: Icon(
                          Icons.bubble_chart_outlined,
                          size: 12,
                          color: RedNoteColors.secondary,
                        ),
                      ),
                      SizedBox(width: 7),
                      Text(
                        '浮念',
                        style: TextStyle(
                          fontSize: 11,
                          color: RedNoteColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(String uri) {
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }
    final store = documentStore;
    if (store == null) return _imagePlaceholder();
    return FutureBuilder<Uint8List?>(
      future: store.readAttachment(uri),
      builder: (context, snapshot) => snapshot.data == null
          ? _imagePlaceholder()
          : Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _imagePlaceholder(),
            ),
    );
  }

  Widget _imagePlaceholder() => const ColoredBox(
    color: RedNoteColors.field,
    child: Center(
      child: Icon(Icons.image_outlined, size: 28, color: RedNoteColors.muted),
    ),
  );
}
