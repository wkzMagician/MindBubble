import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bulk_import_service.dart';
import 'html_note_converter.dart';

/// One-shot Microsoft Graph reader. The delegated access token remains in
/// memory and is never persisted by MindBubble.
class OneNoteGraphAdapter {
  OneNoteGraphAdapter({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://graph.microsoft.com/v1.0/me/onenote/';
  final _converter = const HtmlNoteConverter();

  void close() => _client.close();

  Future<List<ImportCandidate>> load(String token, {int maxPages = 200}) async {
    if (token.trim().isEmpty) {
      throw const FormatException('需要 Microsoft Graph Access Token');
    }
    final headers = {
      'Authorization': 'Bearer ${token.trim()}',
      'Accept': 'application/json',
    };
    Uri? next = Uri.parse('${_base}pages?%24top=100');
    final pages = <ImportCandidate>[];
    final seen = <String>{};

    while (next != null && pages.length < maxPages) {
      _validateGraphUrl(next);
      final response = await _client
          .get(next, headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw FormatException(
          'Microsoft Graph HTTP ${response.statusCode}: ${response.body}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['value'] is! List) {
        throw const FormatException('Invalid OneNote pages response');
      }
      for (final item in decoded['value'] as List) {
        if (pages.length >= maxPages) break;
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty || !seen.add(id)) continue;
        final title = item['title']?.toString() ?? 'Untitled OneNote page';
        final endpoint = Uri.parse(
          '${_base}pages/${Uri.encodeComponent(id)}/content',
        );
        final content = await _client
            .get(
              endpoint,
              headers: {
                'Authorization': 'Bearer ${token.trim()}',
                'Accept': 'text/html',
              },
            )
            .timeout(const Duration(seconds: 30));
        if (content.statusCode != 200) {
          throw FormatException('OneNote page HTTP ${content.statusCode}');
        }
        final markdown = _converter.toMarkdown(
          utf8.decode(content.bodyBytes, allowMalformed: true),
        );
        if (markdown.isEmpty) continue;
        pages.add(
          ImportCandidate(
            externalId: id,
            title: title,
            markdown: markdown,
            updatedAt: DateTime.tryParse(
              item['lastModifiedDateTime']?.toString() ?? '',
            ),
          ),
        );
      }
      final link = decoded['@odata.nextLink'];
      next = link is String && link.isNotEmpty && pages.length < maxPages
          ? Uri.tryParse(link)
          : null;
    }
    return pages;
  }

  void _validateGraphUrl(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'graph.microsoft.com' ||
        !uri.path.startsWith('/v1.0/me/onenote/pages')) {
      throw const FormatException('Unsafe Microsoft Graph pagination URL');
    }
  }
}
