import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mind_bubble/services/html_note_converter.dart';
import 'package:mind_bubble/services/onenote_graph_adapter.dart';
import 'package:mind_bubble/services/siyuan_import_adapter.dart';

void main() {
  test('HTML converter removes scripts, retains headings and links', () {
    const converter = HtmlNoteConverter();
    final markdown = converter.toMarkdown(
      '<html><head><script>secret()</script></head><body>'
      '<h2>Heading</h2><p>Alpha &amp; beta</p>'
      '<p><a href="https://example.com">Visit</a></p></body></html>',
    );
    expect(markdown, contains('## Heading'));
    expect(markdown, contains('Alpha & beta'));
    expect(markdown, contains('[Visit](https://example.com)'));
    expect(markdown, isNot(contains('secret()')));
  });

  test('OneNote Graph loads paginated page bodies by stable IDs', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer access');
      final url = request.url.toString();
      if (url.contains('/pages?') && !url.contains('skiptoken')) {
        return http.Response(
          jsonEncode({
            'value': [
              {
                'id': 'page-a',
                'title': 'Alpha',
                'lastModifiedDateTime': '2026-10-15T12:00:00Z',
              },
            ],
            '@odata.nextLink':
                'https://graph.microsoft.com/v1.0/me/onenote/pages?skiptoken=next',
          }),
          200,
        );
      }
      if (url.contains('skiptoken')) {
        return http.Response(
          jsonEncode({
            'value': [
              {'id': 'page-b', 'title': 'Beta'},
            ],
          }),
          200,
        );
      }
      if (url.endsWith('/page-a/content')) {
        return http.Response(
          '<html><body><p>First page</p></body></html>',
          200,
        );
      }
      if (url.endsWith('/page-b/content')) {
        return http.Response('<html><body><h2>Second</h2></body></html>', 200);
      }
      throw StateError('Unexpected Graph URL: $url');
    });
    final adapter = OneNoteGraphAdapter(client: client);
    addTearDown(adapter.close);
    final notes = await adapter.load('access');
    expect(notes.map((note) => note.externalId), ['page-a', 'page-b']);
    expect(notes.first.markdown, contains('First page'));
    expect(notes.last.markdown, contains('## Second'));
  });

  test('Graph pagination refuses URLs outside Microsoft Graph', () async {
    final adapter = OneNoteGraphAdapter(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'value': [],
            '@odata.nextLink': 'https://evil.example/token',
          }),
          200,
        );
      }),
    );
    addTearDown(adapter.close);
    await expectLater(adapter.load('access'), throwsFormatException);
  });

  test('SiYuan local API queries documents and exports Markdown', () async {
    final client = MockClient((request) async {
      expect(request.url.host, '127.0.0.1');
      expect(request.url.port, 6806);
      expect(request.headers['authorization'], 'Token local-token');
      if (request.url.path.endsWith('/api/query/sql')) {
        final query = jsonDecode(request.body)['stmt'] as String;
        expect(query, contains("type = 'd'"));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'data': [
                {'id': '20261015-abcd', 'content': '思源示例'},
              ],
            }),
          ),
          200,
        );
      }
      if (request.url.path.endsWith('/api/export/exportMdContent')) {
        expect(jsonDecode(request.body)['id'], '20261015-abcd');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'data': {'hPath': '/我的笔记/思源示例', 'content': '# 思源示例\n\n示例正文'},
            }),
          ),
          200,
        );
      }
      throw StateError('Unexpected SiYuan endpoint');
    });
    final adapter = SiYuanImportAdapter(client: client);
    addTearDown(adapter.close);
    final notes = await adapter.load('local-token');
    expect(notes, hasLength(1));
    expect(notes.single.externalId, '20261015-abcd');
    expect(notes.single.title, '思源示例');
    expect(notes.single.markdown, contains('示例正文'));
  });
}
