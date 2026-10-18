import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:markdown/markdown.dart' as md;

enum NoteCoverSource { generated, image }

enum NoteCoverTextSource { original, hook, custom }

enum NoteCoverFit { contain, cover }

class NoteCover {
  static const rendererVersion = 5;
  const NoteCover({
    required this.seed,
    this.source = NoteCoverSource.generated,
    this.textSource = NoteCoverTextSource.original,
    this.text = '',
    this.phrases = const [],
    this.imageUri,
    this.fit = NoteCoverFit.contain,
    this.focalX = .5,
    this.focalY = .5,
    this.posterUri,
    this.posterSignature,
  });

  final int seed;
  final NoteCoverSource source;
  final NoteCoverTextSource textSource;
  final String text;
  final List<String> phrases;
  final String? imageUri;
  final NoteCoverFit fit;
  final double focalX;
  final double focalY;
  final String? posterUri;
  final String? posterSignature;

  factory NoteCover.forNote(String id, String markdown) {
    var seed = 0x811c9dc5;
    for (final byte in utf8.encode(id)) {
      seed = ((seed ^ byte) * 0x01000193) & 0x7fffffff;
    }
    final images = noteImageUris(markdown);
    return NoteCover(
      seed: seed,
      source: images.isEmpty
          ? NoteCoverSource.generated
          : NoteCoverSource.image,
      imageUri: images.isEmpty ? null : images.first,
    );
  }

  static int randomSeed() => Random.secure().nextInt(0x7fffffff);

  String headline(String title) =>
      textSource == NoteCoverTextSource.original || text.trim().isEmpty
      ? title.trim()
      : text.trim();

  String signature(String title) => sha256
      .convert(
        utf8.encode(
          jsonEncode([rendererVersion, seed, headline(title), phrases]),
        ),
      )
      .toString();

  bool hasPosterFor(String title) =>
      posterUri != null && posterSignature == signature(title);

  NoteCover copyWith({
    int? seed,
    NoteCoverSource? source,
    NoteCoverTextSource? textSource,
    String? text,
    List<String>? phrases,
    String? imageUri,
    NoteCoverFit? fit,
    double? focalX,
    double? focalY,
    String? posterUri,
    String? posterSignature,
  }) => NoteCover(
    seed: seed ?? this.seed,
    source: source ?? this.source,
    textSource: textSource ?? this.textSource,
    text: text ?? this.text,
    phrases: phrases ?? this.phrases,
    imageUri: imageUri ?? this.imageUri,
    fit: fit ?? this.fit,
    focalX: focalX ?? this.focalX,
    focalY: focalY ?? this.focalY,
    posterUri: posterUri ?? this.posterUri,
    posterSignature: posterSignature ?? this.posterSignature,
  );

  Map<String, Object?> toJson() => {
    'seed': seed,
    'source': source.name,
    'textSource': textSource.name,
    'text': text,
    'phrases': phrases,
    if (imageUri != null) 'imageUri': imageUri,
    'fit': fit.name,
    'focalX': focalX,
    'focalY': focalY,
    if (posterUri != null) 'posterUri': posterUri,
    if (posterSignature != null) 'posterSignature': posterSignature,
  };

  factory NoteCover.fromJson(Map<String, Object?> json) {
    double focal(String key) {
      final value = json[key];
      return value is num && value.isFinite ? value.toDouble().clamp(0, 1) : .5;
    }

    return NoteCover(
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      source: NoteCoverSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => NoteCoverSource.generated,
      ),
      textSource: NoteCoverTextSource.values.firstWhere(
        (value) => value.name == json['textSource'],
        orElse: () => NoteCoverTextSource.original,
      ),
      text: json['text'] as String? ?? '',
      phrases: json['phrases'] is List
          ? List.unmodifiable((json['phrases'] as List).whereType<String>())
          : const [],
      imageUri: json['imageUri'] as String?,
      fit: json['fit'] == 'cover' ? NoteCoverFit.cover : NoteCoverFit.contain,
      focalX: focal('focalX'),
      focalY: focal('focalY'),
      posterUri: json['posterUri'] as String?,
      posterSignature: json['posterSignature'] as String?,
    );
  }
}

/// Parse actual Markdown images, excluding examples inside fenced/inline code.
List<String> noteImageUris(String markdown) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parseLines(markdown.split('\n'));
  final visitor = _ImageVisitor();
  for (final node in nodes) {
    node.accept(visitor);
  }
  return List.unmodifiable(visitor.uris);
}

class _ImageVisitor implements md.NodeVisitor {
  final uris = <String>[];

  @override
  bool visitElementBefore(md.Element element) {
    if (element.tag == 'code' || element.tag == 'pre') return false;
    if (element.tag == 'img') {
      final source = element.attributes['src']?.trim();
      if (source != null && source.isNotEmpty && !uris.contains(source)) {
        final uri = Uri.tryParse(source);
        if (source.startsWith('assets/') ||
            uri?.scheme == 'http' ||
            uri?.scheme == 'https') {
          uris.add(source);
        }
      }
    }
    return true;
  }

  @override
  void visitElementAfter(md.Element element) {}

  @override
  void visitText(md.Text text) {}
}
