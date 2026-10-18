import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bulk_import_service.dart';

/// Reads pages shared with a Notion integration. The supplied token is
/// session-only and never written into MindBubble settings or exports.
class NotionImportAdapter {
  NotionImportAdapter({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Notion-Version': '2022-06-28',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _json(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'Notion API 请求失败：HTTP ${response.statusCode} ${response.body}',
      );
    }
    final parsed = jsonDecode(response.body);
    if (parsed is! Map) {
      throw const FormatException('Unexpected Notion response');
    }
    return Map<String, dynamic>.from(parsed);
  }

  Future<List<Map<String, dynamic>>> _children(
    String token,
    String blockId,
  ) async {
    final all = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final uri = Uri.https('api.notion.com', '/v1/blocks/$blockId/children', {
        'page_size': '100',
        if (cursor != null) 'start_cursor': cursor,
      });
      final body = await _json(
        await _client.get(uri, headers: _headers(token)),
      );
      for (final result in (body['results'] as List? ?? [])) {
        if (result is Map) all.add(Map<String, dynamic>.from(result));
      }
      cursor = body['has_more'] == true ? body['next_cursor'] as String? : null;
    } while (cursor != null && all.length < 2000);
    return all;
  }

  String _richText(dynamic entries) {
    if (entries is! List) return '';
    final result = StringBuffer();
    for (final item in entries) {
      if (item is! Map) continue;
      final text =
          item['plain_text']?.toString() ??
          (item['text'] is Map
              ? (item['text']['content']?.toString() ?? '')
              : '');
      final href = item['href']?.toString();
      result.write(href == null || href.isEmpty ? text : '[$text]($href)');
    }
    return result.toString();
  }

  String _title(Map<String, dynamic> page) {
    final props = page['properties'];
    if (props is Map) {
      for (final prop in props.values) {
        if (prop is Map && prop['type'] == 'title') {
          final title = _richText(prop['title']);
          if (title.isNotEmpty) return title;
        }
      }
    }
    final explicit = _richText(page['title']);
    return explicit.isEmpty ? 'Untitled Notion Page' : explicit;
  }

  Future<String> _renderBlocks(
    String token,
    String pageId,
    Map<String, Uint8List> assets, {
    int depth = 0,
  }) async {
    if (depth > 4) return '';
    final lines = <String>[];
    for (final block in await _children(token, pageId)) {
      final type = block['type']?.toString() ?? '';
      final data = block[type];
      if (data is! Map) continue;
      final text = _richText(data['rich_text']);
      switch (type) {
        case 'heading_1':
          lines.add('# $text');
          break;
        case 'heading_2':
          lines.add('## $text');
          break;
        case 'heading_3':
          lines.add('### $text');
          break;
        case 'paragraph':
          lines.add(text);
          break;
        case 'bulleted_list_item':
          lines.add('- $text');
          break;
        case 'numbered_list_item':
          lines.add('1. $text');
          break;
        case 'to_do':
          lines.add((data['checked'] == true ? '- [x] ' : '- [ ] ') + text);
          break;
        case 'quote':
          lines.add('> $text');
          break;
        case 'code':
          // Convert fences with stable boundaries for Markdown source editing.
          final lang = data['language']?.toString() ?? '';
          lines.add('~~~$lang\n$text\n~~~');
          break;
        case 'divider':
          lines.add('---');
          break;
        case 'bookmark':
          final url = data['url']?.toString();
          if (url != null) lines.add('[$url]($url)');
          break;
        case 'image':
          final payload = data['file'] ?? data['external'];
          if (payload is Map) {
            final url = payload['url']?.toString();
            if (url != null) {
              final ext = Uri.tryParse(url)?.path.toLowerCase() ?? '';
              final suffix =
                  RegExp(
                    r'\.(png|jpg|jpeg|gif|webp|bmp)$',
                  ).firstMatch(ext)?.group(0) ??
                  '.png';
              final filename =
                  'notion-${block['id']?.toString() ?? 'image'}$suffix';
              try {
                final response = await _client.get(Uri.parse(url));
                if (response.statusCode == 200 &&
                    response.bodyBytes.length < 20 * 1024 * 1024) {
                  assets[filename] = response.bodyBytes;
                  lines.add('![image]($filename)');
                } else {
                  lines.add('![image]($url)');
                }
              } catch (_) {
                lines.add('![image]($url)');
              }
            }
          }
          break;
        default:
          if (text.isNotEmpty) lines.add(text);
      }
      if (block['has_children'] == true && block['id'] is String) {
        final children = await _renderBlocks(
          token,
          block['id'] as String,
          assets,
          depth: depth + 1,
        );
        if (children.isNotEmpty) lines.add(children);
      }
    }
    return lines.join('\n\n');
  }

  Future<List<ImportCandidate>> load(String token, {int maxPages = 200}) async {
    if (token.trim().isEmpty) throw const FormatException('Notion Token 不能为空');
    final notes = <ImportCandidate>[];
    String? cursor;
    do {
      final payload = <String, dynamic>{
        'page_size': 100,
        'sort': {'direction': 'descending', 'timestamp': 'last_edited_time'},
        'filter': {'value': 'page', 'property': 'object'},
        if (cursor != null) 'start_cursor': cursor,
      };
      final body = await _json(
        await _client.post(
          Uri.https('api.notion.com', '/v1/search'),
          headers: _headers(token),
          body: jsonEncode(payload),
        ),
      );
      for (final candidate in (body['results'] as List? ?? [])) {
        if (candidate is! Map || candidate['id'] is! String) continue;
        final page = Map<String, dynamic>.from(candidate);
        final assets = <String, Uint8List>{};
        final markdown = await _renderBlocks(
          token,
          page['id'] as String,
          assets,
        );
        if (markdown.trim().isEmpty) continue;
        notes.add(
          ImportCandidate(
            externalId: page['id'] as String,
            title: _title(page),
            markdown: markdown,
            updatedAt: DateTime.tryParse(
              page['last_edited_time']?.toString() ?? '',
            ),
            assets: assets,
          ),
        );
        if (notes.length >= maxPages) return notes;
      }
      cursor = body['has_more'] == true ? body['next_cursor'] as String? : null;
    } while (cursor != null);
    return notes;
  }

  void close() => _client.close();
}
