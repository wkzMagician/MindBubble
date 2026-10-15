import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../services/bubble_document_store.dart';

import '../../models/bubble.dart';
import '../../services/visual_theme_service.dart';

/// Image-first compact note cards for the RedNote visual theme.
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

  static final _picture = RegExp(
    r'!\[[^\]]*\]\((https?://[^)\s]+|assets/[0-9a-f]{64}\.[a-z]+)',
  );
  static final _markup = RegExp(
    r'!?\[([^\]]+)\]\([^)]+\)|[*_#>~]|^\s*[-+]\s+',
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 580
          ? 2
          : constraints.maxWidth < 900
          ? 3
          : 4;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: constraints.maxWidth < 580 ? .72 : .85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: bubbles.length,
        itemBuilder: (context, index) {
          final note = bubbles[index];
          final picture = _picture.firstMatch(note.description)?.group(1);
          final abstractText = note.description
              .replaceAllMapped(_markup, (m) => m.group(1) ?? '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final palette = [
            const Color(0xFFFFE7E4),
            const Color(0xFFFFF0D9),
            const Color(0xFFE5F1FF),
            const Color(0xFFECE9FF),
          ];
          return Material(
            color: context.appPanel,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onBubbleTap(note),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: palette[index % palette.length],
                      child: picture != null
                          ? _cover(picture)
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  abstractText.isEmpty
                                      ? note.title
                                      : abstractText,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFF664F55),
                                    fontSize: 16,
                                    height: 1.55,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.bubble_chart_outlined,
                              size: 14,
                              color: Color(0xFFB77C87),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '浮念',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
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
        },
      );
    },
  );
  Widget _cover(String uri) {
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    final store = documentStore;
    if (store == null) return const Center(child: Icon(Icons.image_outlined));
    return FutureBuilder<Uint8List?>(
      future: store.readAttachment(uri),
      builder: (context, snapshot) => snapshot.data == null
          ? const Center(child: Icon(Icons.image_outlined))
          : Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
    );
  }
}
