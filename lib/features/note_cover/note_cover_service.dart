import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import 'note_cover.dart';
import 'note_cover_generator.dart';

typedef CoverRasterizer =
    Future<Uint8List> Function(NoteCover cover, String title);

final noteCoverServiceProvider = Provider<NoteCoverService>(
  (ref) => NoteCoverService(ref.watch(bubbleDocumentStoreProvider)),
);

class NoteCoverService {
  NoteCoverService(this.store, {CoverRasterizer? rasterize})
    : rasterize = rasterize ?? NoteCoverGenerator.render;

  final BubbleDocumentStore store;
  final CoverRasterizer rasterize;

  Future<Bubble> prepare(Bubble note) async {
    var cover = note.cover ?? NoteCover.forNote(note.id, note.description);
    if (cover.source == NoteCoverSource.image && cover.imageUri != null) {
      return note.copyWith(cover: cover);
    }
    if (cover.hasPosterFor(note.title) &&
        await store.readAttachment(cover.posterUri!) != null) {
      return note.copyWith(cover: cover);
    }
    final bytes = await rasterize(cover, note.title);
    final uri = await store.storeAttachment(bytes, 'cover.png');
    cover = cover.copyWith(
      posterUri: uri,
      posterSignature: cover.signature(note.title),
    );
    return note.copyWith(cover: cover);
  }
}
