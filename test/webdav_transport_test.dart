import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mind_bubble/services/webdav_transport.dart';

void main() {
  test(
    'ensureDirectory creates each WebDAV collection below the base path',
    () async {
      final requests = <http.Request>[];
      final transport = HttpWebDavTransport(
        serverUrl: 'https://example.test/dav/',
        username: 'user',
        password: 'app-password',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('', 201);
        }),
      );

      await transport.ensureDirectory('/MindBubble/devices');

      expect(requests.map((request) => request.method), ['MKCOL', 'MKCOL']);
      expect(requests.map((request) => request.url.path), [
        '/dav/MindBubble',
        '/dav/MindBubble/devices',
      ]);
      expect(
        requests.first.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('user:app-password'))}',
      );
    },
  );

  test('list parses PROPFIND resources into stable remote paths', () async {
    late http.Request captured;
    final transport = HttpWebDavTransport(
      serverUrl: 'https://example.test/dav/',
      username: 'user',
      password: 'password',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/MindBubble/devices/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/MindBubble/devices/device-a.json</d:href>
    <d:propstat><d:prop><d:resourcetype/><d:getetag>"etag-a"</d:getetag></d:prop></d:propstat>
  </d:response>
</d:multistatus>''',
          207,
          headers: {'content-type': 'application/xml'},
        );
      }),
    );

    final resources = await transport.list('/MindBubble/devices');

    expect(captured.method, 'PROPFIND');
    expect(captured.headers['Depth'], '1');
    expect(captured.body, contains('<d:propfind'));
    expect(
      resources.where((resource) => !resource.isDirectory).single.path,
      '/MindBubble/devices/device-a.json',
    );
    expect(
      resources.where((resource) => !resource.isDirectory).single.etag,
      '"etag-a"',
    );
  });

  test('read and write transfer bytes with GET and PUT', () async {
    final requests = <http.Request>[];
    final transport = HttpWebDavTransport(
      serverUrl: 'https://example.test/dav/',
      username: 'user',
      password: 'password',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response.bytes(
            utf8.encode('{"ok":true}'),
            200,
            headers: {'etag': '"v1"'},
          );
        }
        return http.Response('', 204, headers: {'etag': '"v2"'});
      }),
    );

    final downloaded = await transport.read('/MindBubble/devices/a.json');
    final uploadedEtag = await transport.write(
      '/MindBubble/devices/a.json',
      utf8.encode('{"updated":true}'),
      ifMatch: '"v1"',
      contentType: 'application/json; charset=utf-8',
    );

    expect(utf8.decode(downloaded.bytes), '{"ok":true}');
    expect(downloaded.etag, '"v1"');
    expect(uploadedEtag, '"v2"');
    expect(requests.map((request) => request.method), ['GET', 'PUT']);
    expect(requests.last.body, '{"updated":true}');
    expect(requests.last.headers['If-Match'], '"v1"');
    expect(
      requests.last.headers['Content-Type'],
      'application/json; charset=utf-8',
    );
  });

  test(
    'non-success status preserves the HTTP status for user-facing errors',
    () async {
      final transport = HttpWebDavTransport(
        serverUrl: 'https://example.test/dav/',
        username: 'user',
        password: 'wrong',
        client: MockClient((_) async => http.Response('Unauthorized', 401)),
      );

      await expectLater(
        transport.read('/MindBubble/devices/a.json'),
        throwsA(
          isA<WebDavTransportException>().having(
            (error) => error.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    },
  );

  test('delete carries the remote ETag and treats 404 as success', () async {
    late http.Request captured;
    final transport = HttpWebDavTransport(
      serverUrl: 'https://example.test/dav/',
      username: 'user',
      password: 'password',
      client: MockClient((request) async {
        captured = request;
        return http.Response('', 404);
      }),
    );

    await transport.delete('/MindBubble/v2/bubbles/a.md', ifMatch: '"v3"');

    expect(captured.method, 'DELETE');
    expect(captured.headers['If-Match'], '"v3"');
  });
}
