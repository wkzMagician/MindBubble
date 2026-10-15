import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/bubble_document_store.dart';

/// One renderer for edit previews and reading, including synced local images.
class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    required this.data,
    this.store,
    this.styleSheet,
    this.selectable = false,
    super.key,
  });

  final String data;
  final BubbleDocumentStore? store;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    selectable: selectable,
    styleSheet: styleSheet,
    onTapLink: (_, href, __) async {
      final url = Uri.tryParse(href ?? '');
      if (url == null ||
          !const ['http', 'https', 'mailto'].contains(url.scheme)) {
        return;
      }
      await launchUrl(url, mode: LaunchMode.externalApplication);
    },
    imageBuilder: (uri, title, alt) {
      if (uri.scheme == 'https' || uri.scheme == 'http') {
        return Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _brokenImage(context, alt),
        );
      }
      if (store == null) return _brokenImage(context, alt);
      final key = uri.toString();
      return FutureBuilder<Uint8List?>(
        future: store!.readAttachment(key),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final bytes = snapshot.data;
          return bytes == null
              ? _brokenImage(context, alt)
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _brokenImage(context, alt),
                );
        },
      );
    },
  );

  Widget _brokenImage(BuildContext context, String? alt) => Padding(
    padding: const EdgeInsets.all(10),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 6),
        Text(alt ?? '图片不可用'),
      ],
    ),
  );
}
