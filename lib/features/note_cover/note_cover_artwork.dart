import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import 'note_cover.dart';
import 'note_cover_generator.dart';

class NoteCoverArtwork extends StatefulWidget {
  const NoteCoverArtwork({
    required this.note,
    this.documentStore,
    this.preview = false,
    this.showImageTitle = true,
    this.circular = true,
    super.key,
  });
  final Bubble note;
  final BubbleDocumentStore? documentStore;
  final bool preview;
  final bool showImageTitle;
  final bool circular;
  @override
  State<NoteCoverArtwork> createState() => _NoteCoverArtworkState();
}

class _NoteCoverArtworkState extends State<NoteCoverArtwork> {
  late NoteCover _cover;
  Future<Uint8List?>? _bytes;
  bool _imageFailed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NoteCoverArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.title != widget.note.title ||
        oldWidget.note.description != widget.note.description ||
        oldWidget.note.cover != widget.note.cover ||
        oldWidget.documentStore != widget.documentStore ||
        oldWidget.preview != widget.preview) {
      _load();
    }
  }

  void _load() {
    _imageFailed = false;
    final note = widget.note;
    _cover = note.cover ?? NoteCover.forNote(note.id, note.description);
    if (_cover.source == NoteCoverSource.image && _cover.imageUri != null) {
      _bytes = _cover.imageUri!.startsWith('assets/')
          ? widget.documentStore?.readAttachment(_cover.imageUri!)
          : null;
    } else if (widget.preview && !_cover.hasPosterFor(note.title)) {
      _bytes = null;
    } else {
      final cover = _cover;
      final store = widget.documentStore;
      _bytes = () async {
        if (store != null && cover.hasPosterFor(note.title)) {
          final saved = await store.readAttachment(cover.posterUri!);
          if (saved != null) return saved;
        }
        return NoteCoverGenerator.render(cover, note.title);
      }();
    }
  }

  Widget _poster() => CustomPaint(
    painter: NoteCoverPainter(cover: _cover, title: widget.note.title),
    size: Size.infinite,
  );
  Widget _imageError(BuildContext context, Object error, StackTrace? stack) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_imageFailed) setState(() => _imageFailed = true);
    });
    return _poster();
  }

  Widget _image(ImageProvider provider) => Image(
    image: ResizeImage(
      provider,
      width: 1024,
      height: 1024,
      policy: ResizeImagePolicy.fit,
    ),
    fit: _cover.fit == NoteCoverFit.cover ? BoxFit.cover : BoxFit.contain,
    alignment: _cover.fit == NoteCoverFit.contain
        ? Alignment.center
        : Alignment(_cover.focalX * 2 - 1, _cover.focalY * 2 - 1),
    excludeFromSemantics: true,
    gaplessPlayback: true,
    errorBuilder: _imageError,
  );
  @override
  Widget build(BuildContext context) {
    if (_imageFailed) return _poster();
    if (_cover.source != NoteCoverSource.image || _cover.imageUri == null) {
      if (_bytes == null) return _poster();
      return FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) => snapshot.data == null
            ? _poster()
            : Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                    wasSynchronouslyLoaded || frame != null ? child : _poster(),
                errorBuilder: (_, _, _) => _poster(),
              ),
      );
    }
    final uri = _cover.imageUri!;
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return _photo(_image(NetworkImage(uri)));
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) => snapshot.data == null
          ? _poster()
          : _photo(_image(MemoryImage(snapshot.data!))),
    );
  }

  Widget _photo(Widget image) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final complete = _cover.fit == NoteCoverFit.contain;
      final side = widget.circular ? .16 : .08;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFECEEE7)),
          if (complete)
            Positioned(
              left: width * (widget.circular ? .18 : .04),
              right: width * (widget.circular ? .18 : .04),
              top: height * (widget.circular ? .15 : .04),
              bottom:
                  height *
                  (widget.showImageTitle
                      ? (widget.circular ? .36 : .23)
                      : (widget.circular ? .15 : .04)),
              child: image,
            )
          else
            image,
          if (widget.showImageTitle)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  width * side,
                  complete ? 0 : width * .19,
                  width * side,
                  widget.circular ? width * .15 : height * .06,
                ),
                decoration: BoxDecoration(
                  gradient: complete
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00031D27), Color(0xED031D27)],
                        ),
                ),
                child: Text(
                  widget.note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: (width * .075).clamp(11, 20),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: complete
                        ? const Color(0xFF253D3A)
                        : const Color(0xFFF6F8EE),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
