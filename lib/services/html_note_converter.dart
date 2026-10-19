import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'bulk_import_service.dart';

class HtmlNoteConverter {
  const HtmlNoteConverter();
  String decodeEntities(String input) => input.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);'),
    (match) {
      final key = match.group(1)!;
      if (key.startsWith('#')) {
        final hex = key.length > 2 && key[1].toLowerCase() == 'x';
        final n = int.tryParse(
          key.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        if (n != null &&
            n > 0 &&
            n <= 0x10ffff &&
            !(n >= 0xd800 && n <= 0xdfff)) {
          return String.fromCharCode(n);
        }
      }
      return const {
            'amp': '&',
            'lt': '<',
            'gt': '>',
            'quot': '"',
            'apos': "'",
            'nbsp': ' ',
            'hellip': '…',
          }[key.toLowerCase()] ??
          match.group(0)!;
    },
  );

  String toMarkdown(String html) {
    final cleaned = html
        .replaceAll(
          RegExp(r'<head\b[^>]*>[\s\S]*?</head\s*>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'<(script|style)\b[^>]*>[\s\S]*?</\1\s*>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAllMapped(
          RegExp(
            r'<a\b[^>]*\bhref\s*=\s*["\x27]([^"\x27]+)["\x27][^>]*>([\s\S]*?)</a>',
            caseSensitive: false,
          ),
          (m) {
            final url = decodeEntities(m.group(1)!);
            final label = decodeEntities(
              m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ''),
            ).trim();
            return url.startsWith('http://') || url.startsWith('https://')
                ? '[$label]($url)'
                : label;
          },
        )
        .replaceAllMapped(
          RegExp(
            r'<img\b[^>]*\bsrc\s*=\s*["\x27]([^"\x27]+)["\x27][^>]*>',
            caseSensitive: false,
          ),
          (m) => '\n\n![image](${decodeEntities(m.group(1)!)})\n\n',
        )
        .replaceAllMapped(
          RegExp(r'<h([1-6])\b[^>]*>', caseSensitive: false),
          (m) => '\n\n${List.filled(int.parse(m.group(1)!), '#').join()} ',
        )
        .replaceAll(RegExp(r'</h[1-6]\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n- ')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</?(?:p|div|section|article|blockquote|ul|ol|tr|table)\b[^>]*>',
            caseSensitive: false,
          ),
          '\n\n',
        )
        .replaceAll(RegExp(r'<[^>]*>'), '');
    return decodeEntities(cleaned)
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  ImportCandidate singlePage(
    String name,
    String html, [
    Map<String, Uint8List> files = const {},
  ]) {
    final tag = RegExp(
      r'<title\b[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
    final title = tag == null
        ? path.posix.basenameWithoutExtension(name)
        : decodeEntities(tag.replaceAll(RegExp(r'<[^>]+>'), '')).trim();
    final body =
        RegExp(
          r'<body\b[^>]*>([\s\S]*?)</body>',
          caseSensitive: false,
        ).firstMatch(html)?.group(1) ??
        html;
    final assets = <String, Uint8List>{};
    for (final match in RegExp(
      r'<img\b[^>]*\bsrc\s*=\s*["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    ).allMatches(body)) {
      final src = decodeEntities(match.group(1)!);
      if (src.startsWith('https://') ||
          src.startsWith('http://') ||
          src.startsWith('data:')) {
        continue;
      }
      final relative = path.posix.normalize(
        path.posix.join(path.posix.dirname(name), Uri.decodeFull(src)),
      );
      final bytes = files[relative];
      if (bytes != null) assets[src] = bytes;
    }
    return ImportCandidate(
      externalId: name,
      title: title,
      markdown: toMarkdown(body),
      assets: assets,
    );
  }

  List<ImportCandidate> readFlomo(
    String name,
    String html,
    Map<String, Uint8List> files,
  ) {
    final memos = _divs(html, 'memo');
    if (memos.isEmpty) return [singlePage(name, html)];
    final notes = <ImportCandidate>[];
    final repeated = <String, int>{};
    for (final memo in memos) {
      final dates = _divs(memo, 'time');
      final date = dates.isEmpty
          ? ''
          : decodeEntities(
              dates.first.replaceAll(RegExp(r'<[^>]+>'), ''),
            ).trim();
      final content = _divs(memo, 'content');
      final body = toMarkdown(content.isEmpty ? memo : content.first);
      if (body.isEmpty) continue;
      final assets = <String, Uint8List>{};
      final media = <String>[];
      final filesHtml = _divs(memo, 'files');
      if (filesHtml.isNotEmpty) {
        for (final match in RegExp(
          r'<img\b[^>]*\bsrc\s*=\s*["\x27]([^"\x27]+)["\x27]',
          caseSensitive: false,
        ).allMatches(filesHtml.first)) {
          final link = decodeEntities(match.group(1)!);
          if (!link.startsWith('https://') && !link.startsWith('http://')) {
            final filePath = path.posix.normalize(
              path.posix.join(path.posix.dirname(name), Uri.decodeFull(link)),
            );
            final bytes = files[filePath];
            if (bytes != null) assets[link] = bytes;
          }
          media.add('![image]($link)');
        }
      }
      final title = body
          .split('\n')
          .first
          .replaceAll(RegExp(r'^#+\s*'), '')
          .trim();
      final key = date.isEmpty ? '$name:${notes.length}' : date;
      final occurrence = repeated.update(key, (n) => n + 1, ifAbsent: () => 1);
      notes.add(
        ImportCandidate(
          externalId: 'flomo:$key:$occurrence',
          title: title.isEmpty
              ? 'flomo memo'
              : (title.length > 90 ? title.substring(0, 90) : title),
          markdown: [
            body,
            if (date.isNotEmpty) '创建于：$date',
            ...media,
          ].join('\n\n'),
          assets: assets,
          updatedAt: DateTime.tryParse(date),
        ),
      );
    }
    return notes;
  }

  List<String> _divs(String html, String cls) {
    final matcher = RegExp(r'</?div\b[^>]*>', caseSensitive: false);
    final named = RegExp(
      r'\bclass\s*=\s*["\x27][^"\x27]*\b' +
          RegExp.escape(cls) +
          r'\b[^"\x27]*["\x27]',
      caseSensitive: false,
    );
    final tags = matcher.allMatches(html).toList();
    final output = <String>[];
    for (var i = 0; i < tags.length; i++) {
      if (tags[i].group(0)!.startsWith('</') ||
          !named.hasMatch(tags[i].group(0)!)) {
        continue;
      }
      var depth = 1;
      for (var j = i + 1; j < tags.length; j++) {
        depth += tags[j].group(0)!.startsWith('</') ? -1 : 1;
        if (depth == 0) {
          output.add(html.substring(tags[i].end, tags[j].start));
          break;
        }
      }
    }
    return output;
  }
}
