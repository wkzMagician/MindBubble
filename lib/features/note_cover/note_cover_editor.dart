import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../models/bubble.dart';
import '../../services/bubble_document_store.dart';
import 'cover_headline_service.dart';
import 'note_cover.dart';
import 'note_cover_artwork.dart';

class NoteCoverEditor extends ConsumerStatefulWidget {
  const NoteCoverEditor({
    required this.noteId,
    required this.title,
    required this.body,
    required this.initialCover,
    required this.onChanged,
    this.enabled = true,
    this.autoSelectFirstImage = false,
    super.key,
  });
  final String noteId;
  final TextEditingController title;
  final TextEditingController body;
  final NoteCover initialCover;
  final ValueChanged<NoteCover> onChanged;
  final bool enabled;
  final bool autoSelectFirstImage;

  @override
  ConsumerState<NoteCoverEditor> createState() => _NoteCoverEditorState();
}

class _NoteCoverEditorState extends ConsumerState<NoteCoverEditor> {
  late NoteCover _cover;
  late final TextEditingController _text;
  late List<String> _images;
  late String _body;
  final _previous = <String>[];
  bool _generating = false;
  String? _error;
  int _request = 0;
  bool _sourceChosen = false;

  @override
  void initState() {
    super.initState();
    _cover = widget.initialCover;
    _body = widget.body.text;
    _images = noteImageUris(_body);
    _text = TextEditingController(text: _cover.headline(widget.title.text));
    widget.title.addListener(_inputsChanged);
    widget.body.addListener(_inputsChanged);
  }

  @override
  void dispose() {
    _request++;
    widget.title.removeListener(_inputsChanged);
    widget.body.removeListener(_inputsChanged);
    _text.dispose();
    super.dispose();
  }

  void _inputsChanged() {
    if (_body != widget.body.text) {
      _body = widget.body.text;
      _images = noteImageUris(_body);
      if (widget.autoSelectFirstImage &&
          !_sourceChosen &&
          _cover.imageUri == null &&
          _images.isNotEmpty) {
        _cover = _cover.copyWith(
          source: NoteCoverSource.image,
          imageUri: _images.first,
        );
        widget.onChanged(_cover);
      }
    }
    if (_cover.textSource == NoteCoverTextSource.original) {
      _text.text = widget.title.text;
    }
    setState(() {});
  }

  void _change(NoteCover cover, {bool updateText = false}) {
    _sourceChosen = true;
    setState(() {
      _cover = cover;
      _error = null;
    });
    if (updateText) _text.text = cover.headline(widget.title.text);
    widget.onChanged(cover);
  }

  Future<void> _refine() async {
    final request = ++_request;
    final title = widget.title.text;
    final body = widget.body.text;
    final previous = {..._previous, _cover.headline(title)}.toList();
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final headline = await ref
          .read(coverHeadlineServiceProvider)
          .generate(title: title, body: body, previous: previous);
      if (!mounted || request != _request) return;
      if (title != widget.title.text || body != widget.body.text) {
        setState(() => _error = context.l10n.coverBodyChanged);
        return;
      }
      _previous.add(headline.text);
      _change(
        _cover.copyWith(
          textSource: NoteCoverTextSource.hook,
          text: headline.text,
          phrases: headline.phrases,
        ),
        updateText: true,
      );
    } on CoverHeadlineUnavailable {
      if (mounted && request == _request) {
        setState(() => _error = context.l10n.coverModelRequired);
      }
    } on Object {
      if (mounted && request == _request) {
        setState(() => _error = context.l10n.coverHeadlineFailed);
      }
    } finally {
      if (mounted && request == _request) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_generating;
    final image = _cover.source == NoteCoverSource.image;
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final note = Bubble(
      id: widget.noteId,
      title: widget.title.text,
      description: widget.body.text,
      createdAt: now,
      updatedAt: now,
      cover: _cover,
    );
    final images = {
      ..._images,
      if (image && _cover.imageUri != null) _cover.imageUri!,
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.noteCover,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 14),
        if (images.isNotEmpty) ...[
          SegmentedButton<NoteCoverSource>(
            segments: [
              ButtonSegment(
                value: NoteCoverSource.generated,
                label: Text(context.l10n.coverGenerated),
              ),
              ButtonSegment(
                value: NoteCoverSource.image,
                label: Text(context.l10n.coverImages),
              ),
            ],
            selected: {_cover.source},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (values) => _change(
                    _cover.copyWith(
                      source: values.first,
                      imageUri: _cover.imageUri ?? images.first,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 14),
        ],
        Center(
          child: SizedBox(
            width: 210,
            height: 210,
            child: GestureDetector(
              onPanUpdate: enabled && image && _cover.fit == NoteCoverFit.cover
                  ? (details) => _change(
                      _cover.copyWith(
                        focalX: (_cover.focalX - details.delta.dx / 210).clamp(
                          0,
                          1,
                        ),
                        focalY: (_cover.focalY - details.delta.dy / 210).clamp(
                          0,
                          1,
                        ),
                      ),
                    )
                  : null,
              child: ClipOval(
                child: NoteCoverArtwork(
                  note: note,
                  documentStore: ref.read(bubbleDocumentStoreProvider),
                  preview: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!image) ...[
          Center(
            child: TextButton.icon(
              onPressed: enabled
                  ? () => _change(_cover.copyWith(seed: NoteCover.randomSeed()))
                  : null,
              icon: const Icon(Icons.shuffle, size: 16),
              label: Text(context.l10n.coverNewImage),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<NoteCoverTextSource>(
            segments: [
              ButtonSegment(
                value: NoteCoverTextSource.original,
                label: Text(context.l10n.coverOriginal),
              ),
              ButtonSegment(
                value: NoteCoverTextSource.hook,
                label: Text(context.l10n.coverRefine),
              ),
            ],
            selected: _cover.textSource == NoteCoverTextSource.custom
                ? {}
                : {_cover.textSource},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (values) {
                    if (values.isEmpty) return;
                    if (values.first == NoteCoverTextSource.original) {
                      _change(
                        _cover.copyWith(
                          textSource: NoteCoverTextSource.original,
                          phrases: const [],
                        ),
                        updateText: true,
                      );
                    } else {
                      _refine();
                    }
                  }
                : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text(context.l10n.coverText)),
              if (_cover.textSource == NoteCoverTextSource.hook)
                TextButton(
                  onPressed: enabled ? _refine : null,
                  child: Text(context.l10n.coverNewHeadline),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _text,
            enabled: enabled,
            minLines: 2,
            maxLines: 4,
            maxLength: 40,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (value) => _change(
              _cover.copyWith(
                textSource: NoteCoverTextSource.custom,
                text: value,
                phrases: const [],
              ),
            ),
          ),
        ] else ...[
          if (images.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final uri in images)
                  SizedBox(
                    width: 62,
                    height: 62,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(3),
                        side: BorderSide(
                          color: uri == _cover.imageUri
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                          width: uri == _cover.imageUri ? 2 : 1,
                        ),
                      ),
                      onPressed: enabled
                          ? () => _change(_cover.copyWith(imageUri: uri))
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: NoteCoverArtwork(
                          note: note.copyWith(
                            cover: _cover.copyWith(imageUri: uri),
                          ),
                          documentStore: ref.read(bubbleDocumentStoreProvider),
                          preview: true,
                          showImageTitle: false,
                          circular: false,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          SegmentedButton<NoteCoverFit>(
            segments: [
              ButtonSegment(
                value: NoteCoverFit.contain,
                label: Text(context.l10n.coverFullImage),
              ),
              ButtonSegment(
                value: NoteCoverFit.cover,
                label: Text(context.l10n.coverFillImage),
              ),
            ],
            selected: {_cover.fit},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (values) => _change(_cover.copyWith(fit: values.first))
                : null,
          ),
          if (_cover.fit == NoteCoverFit.cover) ...[
            const SizedBox(height: 14),
            Text(context.l10n.coverHorizontalPosition),
            Slider(
              value: _cover.focalX,
              onChanged: enabled
                  ? (value) => _change(_cover.copyWith(focalX: value))
                  : null,
            ),
            Text(context.l10n.coverVerticalPosition),
            Slider(
              value: _cover.focalY,
              onChanged: enabled
                  ? (value) => _change(_cover.copyWith(focalY: value))
                  : null,
            ),
          ],
        ],
        if (_generating)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
