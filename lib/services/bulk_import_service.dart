import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../models/bubble.dart';
import '../repositories/bubble_repository.dart';
import 'bubble_document_store.dart';
import 'import_service.dart';
import 'html_note_converter.dart';

/// Normalized note from a local directory, export archive or structured export.
class ImportCandidate {
  const ImportCandidate({
    required this.externalId,
    required this.title,
    required this.markdown,
    this.updatedAt,
    this.preferredBubbleId,
    this.assets = const {},
  });
  final String externalId;
  final String title;
  final String markdown;
  final DateTime? updatedAt;
  final String? preferredBubbleId;
  final Map<String, Uint8List> assets;
}

enum ImportAction { add, update, unchanged, conflict }

enum ImportConflictChoice { keepLocal, useSource, duplicate }

class ImportPlanItem {
  const ImportPlanItem({
    required this.note,
    required this.bubbleId,
    required this.action,
  });
  final ImportCandidate note;
  final String bubbleId;
  final ImportAction action;
}

class ImportPreview {
  const ImportPreview({required this.sourceId, required this.items});
  final String sourceId;
  final List<ImportPlanItem> items;
  int count(ImportAction action) =>
      items.where((e) => e.action == action).length;
}

/// Stores the last successfully imported source snapshot and local content state.
class ImportLedger {
  ImportLedger._(this.file, this.entries);
  final File file;
  final Map<String, dynamic> entries;

  static Future<ImportLedger> open(Directory supportRoot) async {
    final file = File(path.join(supportRoot.path, 'import-ledger.json'));
    if (!await file.exists()) return ImportLedger._(file, {});
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw const FormatException('Invalid import ledger');
    return ImportLedger._(file, Map<String, dynamic>.from(decoded));
  }

  Map<String, dynamic>? get(String key) {
    final value = entries[key];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final temp = File(path.join(file.parent.path, 'import-ledger.tmp'));
    await temp.writeAsString(jsonEncode(entries), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

class BulkImportService {
  BulkImportService(this.repository, this.documents);
  final BubbleRepository repository;
  final BubbleDocumentStore documents;

  String _hashContent(String title, String markdown) => sha256
      .convert(utf8.encode('${title.trim()}\n${markdown.trim()}'))
      .toString();

  String _idFor(String source, String external) => sha256
      .convert(utf8.encode('$source::$external'))
      .toString()
      .substring(0, 32);

  String _ledgerKey(String source, String external) =>
      sha256.convert(utf8.encode('$source::$external')).toString();

  Future<ImportPreview> preview(
    String sourceId,
    List<ImportCandidate> notes,
  ) async {
    if (sourceId.trim().isEmpty) {
      throw const FormatException('Source name required');
    }
    final ledger = await ImportLedger.open(documents.supportRoot);
    final existing = {for (final b in await repository.getAll()) b.id: b};
    final seen = <String>{};
    final planned = <ImportPlanItem>[];
    for (final note in notes) {
      if (!seen.add(note.externalId)) continue;
      if (note.title.trim().isEmpty || note.markdown.trim().isEmpty) continue;
      final record = ledger.get(_ledgerKey(sourceId, note.externalId));
      final id =
          record?['bubbleId'] as String? ??
          note.preferredBubbleId ??
          _idFor(sourceId, note.externalId);
      final local = existing[id];
      final incoming = _hashContent(note.title, note.markdown);
      ImportAction action;
      if (local == null) {
        action = ImportAction.add;
      } else if (record == null) {
        action = _hashContent(local.title, local.description) == incoming
            ? ImportAction.unchanged
            : ImportAction.conflict;
      } else if (record['sourceHash'] == incoming) {
        action = ImportAction.unchanged;
      } else if (record['localHash'] ==
          _hashContent(local.title, local.description)) {
        action = ImportAction.update;
      } else {
        action = ImportAction.conflict;
      }
      planned.add(ImportPlanItem(note: note, bubbleId: id, action: action));
    }
    return ImportPreview(sourceId: sourceId, items: planned);
  }

  /// Commit is safely repeatable: the ledger checkpoint advances only after
  /// all note and image writes finish. Unchanged imports never touch local edits.
  Future<int> commit(
    ImportPreview preview, {
    ImportConflictChoice conflictChoice = ImportConflictChoice.keepLocal,
  }) async {
    final ledger = await ImportLedger.open(documents.supportRoot);
    var saved = 0;
    for (final entry in preview.items) {
      if (entry.action == ImportAction.unchanged) {
        final local = await repository.getById(entry.bubbleId);
        final key = _ledgerKey(preview.sourceId, entry.note.externalId);
        if (local != null && ledger.get(key) == null) {
          ledger.entries[key] = {
            'bubbleId': local.id,
            'sourceHash': _hashContent(entry.note.title, entry.note.markdown),
            'localHash': _hashContent(local.title, local.description),
          };
        }
        continue;
      }
      if (entry.action == ImportAction.conflict &&
          conflictChoice == ImportConflictChoice.keepLocal) {
        continue;
      }

      final note = entry.note;
      final current = await repository.getById(entry.bubbleId);
      final shouldDuplicate =
          entry.action == ImportAction.conflict &&
          conflictChoice == ImportConflictChoice.duplicate;
      final id = shouldDuplicate
          ? _idFor(
              preview.sourceId,
              '${note.externalId}:copy:${DateTime.now().microsecondsSinceEpoch}',
            )
          : entry.bubbleId;
      var markdown = note.markdown;
      for (final asset in note.assets.entries) {
        try {
          final key = await documents.storeAttachment(asset.value, asset.key);
          // Path can be URL-encoded by the exporting program.
          markdown = markdown.replaceAll('](${asset.key})', ']($key)');
          markdown = markdown.replaceAll(
            '](${Uri.encodeFull(asset.key)})',
            ']($key)',
          );
          markdown = markdown.replaceAll('](<${asset.key}>)', ']($key)');
        } on FormatException {
          // Preserve a link to any non-image attachment.
        }
      }
      final now = DateTime.now();
      final bubble = Bubble(
        id: id,
        title: note.title.trim(),
        description: markdown.trim(),
        createdAt: current?.createdAt ?? note.updatedAt ?? now,
        updatedAt: now,
        appearanceFrequency: current?.appearanceFrequency ?? 3,
        shownByDevice: current?.shownByDevice ?? const {},
      );
      await repository.save(bubble);
      saved++;
      if (!shouldDuplicate) {
        ledger.entries[_ledgerKey(preview.sourceId, note.externalId)] = {
          'bubbleId': id,
          'sourceHash': _hashContent(note.title, note.markdown),
          'localHash': _hashContent(bubble.title, bubble.description),
          'importedAt': now.toUtc().toIso8601String(),
        };
      }
    }
    await ledger.save();
    return saved;
  }

  /// Scan regular folders (Obsidian/Logseq/Markdown), a ZIP, ENEX, Keep JSON,
  /// canonical MindBubble JSON, or legacy CSV/XLSX.
  Future<List<ImportCandidate>> readDirectory(Directory directory) async {
    final files = <String, Uint8List>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (entity.lengthSync() > 20 * 1024 * 1024) continue;
      final relative = path
          .relative(entity.path, from: directory.path)
          .replaceAll('\\', '/');
      if (_safePath(relative)) files[relative] = await entity.readAsBytes();
      if (files.length > 5000) {
        throw const FormatException('Too many files (max 5000)');
      }
    }
    return _readFileMap(files);
  }

  Future<List<ImportCandidate>> readFile(File file) async {
    final ext = path.extension(file.path).toLowerCase();
    if (ext == '.zip') {
      final bytes = await file.readAsBytes();
      if (bytes.length > 100 * 1024 * 1024) {
        throw const FormatException('Archive exceeds 100 MB limit');
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = <String, Uint8List>{};
      var uncompressed = 0;
      for (final item in archive) {
        if (!item.isFile || !_safePath(item.name)) continue;
        uncompressed += item.size;
        if (uncompressed > 250 * 1024 * 1024 || files.length > 5000) {
          throw const FormatException('Archive exceeds import limits');
        }
        if (item.size > 20 * 1024 * 1024) continue;
        final data = item.content;
        if (data is List<int>) {
          files[item.name.replaceAll('\\', '/')] = Uint8List.fromList(data);
        }
      }
      return _readFileMap(files);
    }
    if (ext == '.csv' || ext == '.xlsx') {
      return _tableCandidates(
        await ImportService().readTable(file),
        path.basename(file.path),
      );
    }
    return _readFileMap({path.basename(file.path): await file.readAsBytes()});
  }

  List<ImportCandidate> _tableCandidates(List<ImportRow> rows, String origin) {
    final seen = <String, int>{};
    final notes = <ImportCandidate>[];
    for (final row in rows) {
      final fields = row.values;
      final title =
          (fields['title'] ??
                  fields['标题'] ??
                  fields['Name'] ??
                  fields['name'] ??
                  '')
              .trim();
      if (title.isEmpty) continue;
      final stableKey =
          (fields['id'] ??
                  fields['ID'] ??
                  fields['URL'] ??
                  fields['url'] ??
                  title.toLowerCase())
              .trim();
      final occurrence = seen.update(
        stableKey,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      final body =
          (fields['description'] ??
                  fields['Description'] ??
                  fields['正文'] ??
                  fields['描述'] ??
                  fields['Content'] ??
                  fields['content'] ??
                  '')
              .trim();
      final fallback = fields.entries
          .where(
            (entry) =>
                entry.value.trim().isNotEmpty && entry.value.trim() != title,
          )
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      final content = body.isEmpty ? fallback : body;
      if (content.isEmpty) continue;
      notes.add(
        ImportCandidate(
          externalId: '$origin:$stableKey:$occurrence',
          title: title,
          markdown: content,
        ),
      );
    }
    return notes;
  }

  bool _safePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.contains('../') &&
        !normalized.startsWith('..') &&
        !RegExp(r'^[A-Za-z]:').hasMatch(normalized);
  }

  List<ImportCandidate> _readFileMap(Map<String, Uint8List> files) {
    final output = <ImportCandidate>[];
    for (final file in files.entries) {
      final name = file.key;
      final ext = path.extension(name).toLowerCase();
      if (ext == '.md' || ext == '.markdown') {
        final text = utf8.decode(file.value, allowMalformed: true).trim();
        if (text.isEmpty) continue;
        final base = path.basenameWithoutExtension(name);
        final notionMatch = RegExp(
          r'^(.*) ([0-9a-f]{32})$',
          caseSensitive: false,
        ).firstMatch(base);
        final title = notionMatch?.group(1) ?? base;
        final id = notionMatch?.group(2) ?? name;
        final folder = path.posix.dirname(name);
        final assets = <String, Uint8List>{};
        final links = RegExp(r'!\[[^\]]*\]\((<?[^)>]+>?)\)').allMatches(text);
        for (final match in links) {
          final link = match.group(1)!.replaceAll(RegExp(r'^<|>$'), '');
          final local = Uri.decodeFull(link);
          if (local.startsWith('http:') || local.startsWith('https:')) continue;
          final relative = path.posix.normalize(path.posix.join(folder, local));
          if (files.containsKey(relative)) assets[link] = files[relative]!;
        }
        output.add(
          ImportCandidate(
            externalId: id,
            title: title,
            markdown: text,
            assets: assets,
          ),
        );
      } else if (ext == '.html' || ext == '.htm') {
        final html = utf8.decode(file.value, allowMalformed: true);
        final converter = const HtmlNoteConverter();
        // flomo exports contain many memos in one HTML file.
        if (RegExp(
          r'<div\b[^>]*class=["\x27][^"\x27]*\bmemo\b',
          caseSensitive: false,
        ).hasMatch(html)) {
          output.addAll(converter.readFlomo(name, html, files));
        } else {
          output.add(converter.singlePage(name, html, files));
        }
      } else if (ext == '.enex') {
        output.addAll(_readEnex(utf8.decode(file.value, allowMalformed: true)));
      } else if (ext == '.csv') {
        final parsed = const CsvToListConverter(
          shouldParseNumbers: false,
          eol: '\n',
        ).convert(utf8.decode(file.value, allowMalformed: true));
        if (parsed.isNotEmpty) {
          final headers = parsed.first.map((value) => '$value').toList();
          final rows = [
            for (final line in parsed.skip(1))
              ImportRow({
                for (var i = 0; i < headers.length; i++)
                  headers[i]: i < line.length ? '${line[i]}' : '',
              }),
          ];
          output.addAll(_tableCandidates(rows, name));
        }
      } else if (ext == '.json') {
        final decoded = jsonDecode(
          utf8.decode(file.value, allowMalformed: true),
        );
        if (decoded is Map && decoded['format'] == 'mind-bubble-import') {
          for (final item in (decoded['items'] as List? ?? [])) {
            if (item is! Map) continue;
            final id = item['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            output.add(
              ImportCandidate(
                externalId: id,
                preferredBubbleId: id,
                title: item['title']?.toString() ?? '',
                markdown: item['description']?.toString() ?? '',
                updatedAt: DateTime.tryParse(
                  item['updatedAt']?.toString() ?? '',
                ),
              ),
            );
          }
        } else if (decoded is Map &&
            (decoded.containsKey('textContent') ||
                decoded.containsKey('listContent'))) {
          final title =
              decoded['title']?.toString() ??
              path.basenameWithoutExtension(name);
          final list = decoded['listContent'];
          final content =
              decoded['textContent']?.toString() ??
              (list is List
                  ? list
                        .map(
                          (x) => x is Map
                              ? ((x['isChecked'] == true
                                        ? '- [x] '
                                        : '- [ ] ') +
                                    (x['text']?.toString() ?? ''))
                              : '',
                        )
                        .join('\n')
                  : '');
          if (content.trim().isEmpty) continue;
          final labels = decoded['labels'];
          final suffix = labels is List
              ? '\n\n${labels.map((l) => '#${l is Map ? (l['name']?.toString() ?? '') : l.toString()}').join(' ')}'
              : '';
          output.add(
            ImportCandidate(
              externalId: decoded['id']?.toString() ?? name,
              title: title.isEmpty ? 'Untitled Keep note' : title,
              markdown: content + suffix,
            ),
          );
        }
      }
    }
    return output;
  }

  List<ImportCandidate> _readEnex(String xml) {
    final document = XmlDocument.parse(xml);
    final output = <ImportCandidate>[];
    var index = 0;
    for (final note in document.findAllElements('note')) {
      String value(String tag) => note.getElement(tag)?.innerText.trim() ?? '';
      final title = value('title');
      final enml = value('content');
      if (title.isEmpty || enml.isEmpty) continue;
      var markdown = enml
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</(div|p)>', caseSensitive: false), '\n\n')
          .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n- ')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&')
          .trim();
      if (markdown.isEmpty) markdown = title;
      final assets = <String, Uint8List>{};
      for (final resource in note.findElements('resource')) {
        final base64Text = resource.getElement('data')?.innerText.trim();
        final name = resource
            .getElement('resource-attributes')
            ?.getElement('file-name')
            ?.innerText
            .trim();
        if (base64Text == null || name == null || name.isEmpty) continue;
        try {
          final bytes = base64Decode(base64Text.replaceAll(RegExp(r'\s+'), ''));
          assets[name] = Uint8List.fromList(bytes);
          markdown += '\n\n![$name]($name)';
        } on FormatException {
          /* Resource unsupported. */
        }
      }
      output.add(
        ImportCandidate(
          externalId: value('guid').isEmpty ? 'enex-${index++}' : value('guid'),
          title: title,
          markdown: markdown,
          assets: assets,
        ),
      );
    }
    return output;
  }
}
