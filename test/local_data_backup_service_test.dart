import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/local_data_backup_service.dart';

void main() {
  test(
    'manifest verifies and detects one deliberately corrupted file',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'mindbubble-backup-',
      );
      addTearDown(() async {
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
      });
      final source = Directory(
        '${sandbox.path}${Platform.pathSeparator}source',
      );
      await source.create();
      await File(
        '${source.path}${Platform.pathSeparator}one.md',
      ).writeAsString('safe bytes', flush: true);

      final backup = await LocalDataBackupService.createBackup(
        destinationParent: Directory(
          '${sandbox.path}${Platform.pathSeparator}backups',
        ),
        sources: {'documents': source},
        applicationVersion: 'test',
        createdAt: DateTime.utc(2026, 8, 14),
      );
      await LocalDataBackupService.verifyBackup(backup);

      final manifest =
          jsonDecode(
                await File(
                  '${backup.path}${Platform.pathSeparator}manifest.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      final entry = (manifest['files'] as List).single as Map<String, Object?>;
      final copy = File(
        '${backup.path}${Platform.pathSeparator}${entry['backupRelativePath']}',
      );
      await copy.writeAsString('corrupted', flush: true);

      expect(
        () => LocalDataBackupService.verifyBackup(backup),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('same timestamp creates a unique non-overwriting backup', () async {
    final sandbox = await Directory.systemTemp.createTemp('mindbubble-backup-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final source = File('${sandbox.path}${Platform.pathSeparator}source.db');
    await source.writeAsBytes([1, 2, 3], flush: true);
    final parent = Directory('${sandbox.path}${Platform.pathSeparator}backups');
    final time = DateTime.utc(2026, 8, 14);

    final first = await LocalDataBackupService.createBackup(
      destinationParent: parent,
      sources: {'database': source},
      applicationVersion: 'test',
      createdAt: time,
    );
    final second = await LocalDataBackupService.createBackup(
      destinationParent: parent,
      sources: {'database': source},
      applicationVersion: 'test',
      createdAt: time,
    );

    expect(second.path, isNot(first.path));
    await LocalDataBackupService.verifyBackup(first);
    await LocalDataBackupService.verifyBackup(second);
  });
}
