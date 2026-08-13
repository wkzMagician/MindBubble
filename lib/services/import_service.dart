import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

class ImportRow {
  const ImportRow(this.values);
  final Map<String, String> values;
}

class ImportService {
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
    throw UnsupportedError('Only CSV and XLSX are table imports.');
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
