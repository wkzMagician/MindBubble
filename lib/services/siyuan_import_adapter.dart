import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bulk_import_service.dart';

/// Reads the user's current local SiYuan kernel via its documented public API.
/// Only a loopback endpoint is used, never an arbitrary host.
class SiYuanImportAdapter {
  SiYuanImportAdapter({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const _base = 'http://127.0.0.1:6806';
  void close() => _client.close();

  Future<dynamic> _post(
    String endpoint,
    String token,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(
          Uri.parse(_base + endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Token $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw FormatException('思源内核 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['code'] != 0) {
      throw FormatException(
        '思源内核请求失败：${decoded is Map ? decoded['msg'].toString() : response.body}',
      );
    }
    return decoded['data'];
  }

  Future<List<ImportCandidate>> load(
    String token, {
    int maxDocuments = 200,
  }) async {
    if (token.trim().isEmpty) throw const FormatException('请输入思源 API Token');
    final t = token.trim();
    final notes = <ImportCandidate>[];
    for (var offset = 0; offset < maxDocuments; offset += 100) {
      final sql =
          "SELECT id, content, hpath, updated FROM blocks WHERE type = 'd' ORDER BY id LIMIT 100 OFFSET $offset";
      final data = await _post('/api/query/sql', t, {'stmt': sql});
      if (data is! List) {
        throw const FormatException('Invalid SiYuan SQL result');
      }
      if (data.isEmpty) break;
      for (final row in data) {
        if (notes.length >= maxDocuments) break;
        if (row is! Map) continue;
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final exported = await _post('/api/export/exportMdContent', t, {
          'id': id,
        });
        if (exported is! Map) continue;
        final markdown = exported['content']?.toString().trim() ?? '';
        if (markdown.isEmpty) continue;
        final humanPath = exported['hPath']?.toString() ?? '';
        final name = row['content']?.toString().trim() ?? '';
        final title = name.isNotEmpty ? name : (humanPath.split('/').last);
        notes.add(
          ImportCandidate(
            externalId: id,
            title: title.isEmpty ? id : title,
            markdown: markdown,
          ),
        );
      }
      if (data.length < 100) break;
    }
    return notes;
  }
}
