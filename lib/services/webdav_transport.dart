import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavResource {
  const WebDavResource({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.etag,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final String? etag;
}

class WebDavReadResult {
  const WebDavReadResult(this.bytes, this.etag);

  final Uint8List bytes;
  final String? etag;
}

class WebDavTransportException implements Exception {
  const WebDavTransportException(
    this.operation, {
    this.statusCode,
    this.detail,
  });

  final String operation;
  final int? statusCode;
  final String? detail;

  @override
  String toString() {
    final status = statusCode == null ? '' : '（HTTP $statusCode）';
    final suffix = detail == null || detail!.isEmpty ? '' : '：$detail';
    return '$operation失败$status$suffix';
  }
}

abstract class WebDavTransport {
  Future<void> ensureDirectory(String remotePath);
  Future<List<WebDavResource>> list(String remotePath);
  Future<WebDavReadResult> read(String remotePath);
  Future<String?> write(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool createOnly = false,
    String contentType = 'application/octet-stream',
  });
  Future<void> delete(String remotePath, {String? ifMatch});
  void close();
}

/// The deliberately small WebDAV surface MindBubble needs.
///
/// TODO(opendal): Re-evaluate Apache OpenDAL when its Dart binding is stable,
/// or when MindBubble needs multiple cloud-storage backends. Until then, keep
/// this adapter limited to MKCOL, PROPFIND, GET, conditional PUT, and DELETE.
class HttpWebDavTransport implements WebDavTransport {
  HttpWebDavTransport({
    required String serverUrl,
    required String username,
    required String password,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = Uri.parse(
         serverUrl.endsWith('/') ? serverUrl : '$serverUrl/',
       ),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _authorization =
           'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;
  final String _authorization;
  final Duration timeout;

  @override
  Future<void> ensureDirectory(String remotePath) async {
    final segments = _segments(remotePath);
    var current = '';
    for (final segment in segments) {
      current = '$current/$segment';
      final response = await _send('MKCOL', current);
      if ({200, 201, 204, 405}.contains(response.statusCode)) continue;
      throw _responseError('创建 WebDAV 目录', response);
    }
  }

  @override
  Future<List<WebDavResource>> list(String remotePath) async {
    final normalized = _normalizePath(remotePath);
    final response = await _send(
      'PROPFIND',
      normalized,
      headers: const {
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode('''
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
    <d:getetag/>
  </d:prop>
</d:propfind>
'''),
    );
    if (response.statusCode != 207) {
      throw _responseError('列出 WebDAV 目录', response);
    }

    try {
      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      final resources = <WebDavResource>[];
      for (final element in document.findAllElements(
        'response',
        namespace: '*',
      )) {
        final hrefs = element.findAllElements('href', namespace: '*');
        if (hrefs.isEmpty) continue;
        final href =
            Uri.tryParse(hrefs.first.innerText)?.path ?? hrefs.first.innerText;
        final segments = href
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .toList();
        if (segments.isEmpty) continue;
        final name = Uri.decodeComponent(segments.last);
        final isDirectory = element
            .findAllElements('collection', namespace: '*')
            .isNotEmpty;
        final etags = element.findAllElements('getetag', namespace: '*');
        resources.add(
          WebDavResource(
            path: '$normalized/$name${isDirectory ? '/' : ''}',
            name: name,
            isDirectory: isDirectory,
            etag: etags.isEmpty ? null : etags.first.innerText.trim(),
          ),
        );
      }
      return resources;
    } on XmlParserException catch (error) {
      throw WebDavTransportException('解析 WebDAV 目录响应', detail: error.message);
    }
  }

  @override
  Future<WebDavReadResult> read(String remotePath) async {
    final response = await _send('GET', remotePath);
    if (response.statusCode != 200) {
      throw _responseError('下载 WebDAV 文件', response);
    }
    return WebDavReadResult(response.bodyBytes, response.headers['etag']);
  }

  @override
  Future<String?> write(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool createOnly = false,
    String contentType = 'application/octet-stream',
  }) async {
    final response = await _send(
      'PUT',
      remotePath,
      headers: {
        'Content-Type': contentType,
        if (ifMatch != null) 'If-Match': ifMatch,
        if (createOnly) 'If-None-Match': '*',
      },
      body: bytes,
    );
    if (!{200, 201, 204}.contains(response.statusCode)) {
      throw _responseError('上传 WebDAV 文件', response);
    }
    return response.headers['etag'];
  }

  @override
  Future<void> delete(String remotePath, {String? ifMatch}) async {
    final response = await _send(
      'DELETE',
      remotePath,
      headers: {if (ifMatch != null) 'If-Match': ifMatch},
    );
    if (!{200, 202, 204, 404}.contains(response.statusCode)) {
      throw _responseError('删除 WebDAV 文件', response);
    }
  }

  Future<http.Response> _send(
    String method,
    String remotePath, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, _resolve(remotePath))
      ..headers.addAll({
        'Authorization': _authorization,
        'User-Agent': 'MindBubble/1',
        ...headers,
      });
    if (body != null) request.bodyBytes = body;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on WebDavTransportException {
      rethrow;
    } catch (error) {
      throw WebDavTransportException(method, detail: error.toString());
    }
  }

  WebDavTransportException _responseError(
    String operation,
    http.Response response,
  ) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    return WebDavTransportException(
      operation,
      statusCode: response.statusCode,
      detail: body.isEmpty
          ? response.reasonPhrase
          : body.substring(0, body.length.clamp(0, 300)),
    );
  }

  Uri _resolve(String remotePath) =>
      _baseUri.resolve(_normalizePath(remotePath).substring(1));

  static String _normalizePath(String value) {
    final segments = _segments(value);
    return '/${segments.join('/')}';
  }

  static List<String> _segments(String value) => value
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
