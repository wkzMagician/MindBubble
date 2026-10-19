import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mind_bubble/services/notion_import_adapter.dart';

void main() {
  test('fetches pages and converts rich text and checklist blocks', () async {
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/v1/search') {
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(
          jsonEncode({
            'has_more': false,
            'results': [
              {
                'id': 'page-1',
                'object': 'page',
                'last_edited_time': '2026-10-01T10:00:00Z',
                'properties': {
                  'Name': {
                    'type': 'title',
                    'title': [
                      {'plain_text': 'My Notion Page'},
                    ],
                  },
                },
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/v1/blocks/page-1/children') {
        return http.Response(
          jsonEncode({
            'has_more': false,
            'results': [
              {
                'type': 'heading_2',
                'heading_2': {
                  'rich_text': [
                    {'plain_text': 'Section'},
                  ],
                },
              },
              {
                'type': 'to_do',
                'to_do': {
                  'checked': true,
                  'rich_text': [
                    {'plain_text': 'Done'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final adapter = NotionImportAdapter(client: client);
    final notes = await adapter.load('token');
    expect(notes.single.externalId, 'page-1');
    expect(notes.single.title, 'My Notion Page');
    expect(notes.single.markdown, contains('## Section'));
    expect(notes.single.markdown, contains('- [x] Done'));
    adapter.close();
  });
}
