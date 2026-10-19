import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;

class ImportRow {
  const ImportRow(this.values);

  final Map<String, String> values;
}

/// One item in the versioned `mind-bubble-import` interchange format.
class MindBubbleImportItem {
  const MindBubbleImportItem({
    required this.id,
    required this.title,
    required this.description,
    this.appearanceFrequency = 3,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String description;
  final int appearanceFrequency;
  final DateTime? updatedAt;

  factory MindBubbleImportItem.fromJson(Object? value, {required int index}) {
    if (value is! Map) {
      throw FormatException('items[$index] must be an object.');
    }
    final item = Map<String, Object?>.from(value);
    final id = _requiredString(item['id'], 'items[$index].id');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id)) {
      throw FormatException(
        'items[$index].id must be a safe MindBubble document id.',
      );
    }
    final title = _requiredString(item['title'], 'items[$index].title');
    final description = _requiredString(
      item['description'],
      'items[$index].description',
    );
    final frequency = switch (item['appearanceFrequency']) {
      null => 3,
      int value => value,
      num value => value.toInt(),
      _ => throw FormatException(
        'items[$index].appearanceFrequency must be an integer.',
      ),
    };
    if (frequency < 1 || frequency > 5) {
      throw FormatException(
        'items[$index].appearanceFrequency must be between 1 and 5.',
      );
    }
    return MindBubbleImportItem(
      id: id,
      title: title,
      description: description,
      appearanceFrequency: frequency,
      updatedAt: _optionalDate(item['updatedAt'], 'items[$index].updatedAt'),
    );
  }
}

/// A complete, replayable import batch produced by an Agent or connector.
class MindBubbleImportBatch {
  const MindBubbleImportBatch({
    required this.schemaVersion,
    required this.items,
    this.sourceId,
    this.cursor,
    this.nextCursor,
  });

  static const format = 'mind-bubble-import';
  static const supportedSchemaVersion = 1;

  final int schemaVersion;
  final List<MindBubbleImportItem> items;
  final String? sourceId;
  final String? cursor;
  final String? nextCursor;
}

class ImportCheckpointStore {
  const ImportCheckpointStore._();

  static const _fileName = 'import-checkpoints.json';

  static Future<String?> read(Directory supportRoot, String sourceId) async {
    final file = File(path.join(supportRoot.path, _fileName));
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Import checkpoint file is invalid.');
    }
    final value = decoded[sourceId];
    return value is String ? value : null;
  }

  static Future<void> write(
    Directory supportRoot,
    String sourceId,
    String nextCursor,
  ) async {
    await supportRoot.create(recursive: true);
    final file = File(path.join(supportRoot.path, _fileName));
    final values = <String, Object?>{};
    if (await file.exists()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Import checkpoint file is invalid.');
      }
      for (final entry in decoded.entries) {
        if (entry.key is String && entry.value is String) {
          values[entry.key as String] = entry.value;
        }
      }
    }
    values[sourceId] = nextCursor;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(values), flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }
}

class ImportService {
  Future<MindBubbleImportBatch> readImport(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('MindBubble import must be a JSON object.');
    }
    final json = Map<String, Object?>.from(decoded);
    if (json['format'] != MindBubbleImportBatch.format) {
      throw const FormatException(
        'Unsupported import format. Expected mind-bubble-import.',
      );
    }
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != MindBubbleImportBatch.supportedSchemaVersion) {
      throw FormatException(
        'Unsupported import schema version: $schemaVersion',
      );
    }
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Import items must be an array.');
    }
    final source = json['source'];
    String? sourceId;
    String? cursor;
    String? nextCursor;
    if (source != null) {
      if (source is! Map) {
        throw const FormatException('Import source must be an object.');
      }
      final sourceJson = Map<String, Object?>.from(source);
      sourceId = _optionalString(sourceJson['id'], 'source.id');
      cursor = _optionalString(sourceJson['cursor'], 'source.cursor');
      nextCursor = _optionalString(
        sourceJson['nextCursor'],
        'source.nextCursor',
      );
      if (sourceId == null && (cursor != null || nextCursor != null)) {
        throw const FormatException(
          'source.id is required when using an incremental cursor.',
        );
      }
    }
    return MindBubbleImportBatch(
      schemaVersion: schemaVersion as int,
      items: [
        for (var index = 0; index < rawItems.length; index++)
          MindBubbleImportItem.fromJson(rawItems[index], index: index),
      ],
      sourceId: sourceId,
      cursor: cursor,
      nextCursor: nextCursor,
    );
  }

  /// Reads the legacy CSV/XLSX table format kept for existing users.
  Future<List<ImportRow>> readTable(File file) async {
    final extension = file.path.split('.').last.toLowerCase();
    if (extension == 'csv') {
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(await file.readAsString());
      return _fromRows(
        rows.map((row) => row.map((cell) => '$cell').toList()).toList(),
      );
    }
    if (extension == 'xlsx') {
      final workbook = Excel.decodeBytes(await file.readAsBytes());
      final sheet = workbook.tables.values.firstOrNull;
      if (sheet == null) return [];
      return _fromRows(
        sheet.rows
            .map(
              (row) =>
                  row.map((cell) => cell?.value?.toString() ?? '').toList(),
            )
            .toList(),
      );
    }
    throw UnsupportedError('Only JSON, CSV and XLSX imports are supported.');
  }

  List<ImportRow> _fromRows(List<List<String>> rows) {
    if (rows.isEmpty) return [];
    final headers = rows.first;
    return rows
        .skip(1)
        .where((row) => row.any((value) => value.trim().isNotEmpty))
        .map(
          (row) => ImportRow({
            for (var i = 0; i < headers.length; i++)
              headers[i]: i < row.length ? row[i] : '',
          }),
        )
        .toList();
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$field must be an ISO-8601 string.');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    throw FormatException('$field must be an ISO-8601 string.');
  }
}
