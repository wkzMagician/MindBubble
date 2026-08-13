import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/services/mindbubble_merge_policy.dart';

void main() {
  test('non-overlapping Markdown fields merge without losing either edit', () {
    final base = _raw(title: 'base', body: 'base body', frequency: 3);
    final local = _raw(title: 'local title', body: 'base body', frequency: 3);
    final remote = _raw(title: 'base', body: 'remote body', frequency: 3);

    final merged = mergeMindBubbleDocuments(
      id: 'bubble-1',
      baseRaw: base,
      localRaw: local,
      remoteRaw: remote,
      mergedAt: DateTime.utc(2026, 8, 14),
    );

    final bubble = BubbleDocumentCodec.decode(
      merged!,
      expectedId: 'bubble-1',
    ).bubble;
    expect(bubble.title, 'local title');
    expect(bubble.description, 'remote body');
  });

  test('same-field concurrent edits remain an explicit conflict', () {
    final result = mergeMindBubbleDocuments(
      id: 'bubble-1',
      baseRaw: _raw(title: 'base', body: 'body', frequency: 3),
      localRaw: _raw(title: 'local', body: 'body', frequency: 3),
      remoteRaw: _raw(title: 'remote', body: 'body', frequency: 3),
    );
    expect(result, isNull);
  });
}

String _raw({
  required String title,
  required String body,
  required int frequency,
}) => BubbleDocumentCodec.encode(
  Bubble(
    id: 'bubble-1',
    title: title,
    description: body,
    createdAt: DateTime.utc(2026, 8, 1),
    updatedAt: DateTime.utc(2026, 8, 14),
    appearanceFrequency: frequency,
  ),
  updatedBy: 'test',
);
