import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class LocalDataBackupService {
  static Future<Directory?> createInitialBackup() async {
    final documents = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final marker = File(
      path.join(support.path, 'MindBubble', 'dartloom-backup-created'),
    );
    if (await marker.exists()) return null;

    final backup = await createBackup(
      destinationParent: Directory(
        path.join(support.parent.path, 'DartloomBackups', 'MindBubble'),
      ),
      sources: {
        'documents-mindbubble': Directory(
          path.join(documents.path, 'MindBubble'),
        ),
        'app-support': Directory(path.join(support.path, 'MindBubble')),
        'legacy-database': File(path.join(documents.path, 'mind_bubble.db')),
      },
      applicationVersion: '0.4.0+5',
    );
    await marker.parent.create(recursive: true);
    await marker.writeAsString(backup.path, flush: true);
    return backup;
  }

  static Future<Directory> createBackup({
    required Directory destinationParent,
    required Map<String, FileSystemEntity> sources,
    required String applicationVersion,
    DateTime? createdAt,
  }) async {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final stem = timestamp.toIso8601String().replaceAll(':', '-');
    var suffix = 0;
    Directory backup;
    do {
      backup = Directory(
        path.join(destinationParent.path, suffix == 0 ? stem : '$stem-$suffix'),
      );
      suffix++;
    } while (await backup.exists());
    await backup.create(recursive: true);

    final sourceRecords = <Map<String, Object?>>[];
    final fileRecords = <Map<String, Object?>>[];
    try {
      for (final entry in sources.entries) {
        final source = entry.value;
        final type = await FileSystemEntity.type(
          source.path,
          followLinks: false,
        );
        final present = type != FileSystemEntityType.notFound;
        sourceRecords.add({
          'id': entry.key,
          'absoluteSourcePath': source.absolute.path,
          'present': present,
        });
        if (!present) continue;
        if (type == FileSystemEntityType.link) {
          throw FileSystemException(
            'Backup sources cannot be links',
            source.path,
          );
        }
        if (source is File) {
          await _copyFile(
            entry.key,
            source,
            source.parent,
            backup,
            fileRecords,
          );
        } else if (source is Directory) {
          await for (final child in source.list(
            recursive: true,
            followLinks: false,
          )) {
            final childType = await FileSystemEntity.type(
              child.path,
              followLinks: false,
            );
            if (childType == FileSystemEntityType.link) {
              throw FileSystemException(
                'Backup sources cannot contain links',
                child.path,
              );
            }
            if (child is File) {
              await _copyFile(entry.key, child, source, backup, fileRecords);
            }
          }
        }
      }
      final manifest = {
        'schemaVersion': 1,
        'createdAtUtc': timestamp.toIso8601String(),
        'application': 'MindBubble',
        'applicationVersion': applicationVersion,
        'backupAbsolutePath': backup.absolute.path,
        'sources': sourceRecords,
        'files': fileRecords,
      };
      await File(path.join(backup.path, 'manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );
      await verifyBackup(backup);
      return backup;
    } catch (_) {
      // A failed backup is deliberately left in place for diagnosis. It never
      // receives a successful manifest and can never satisfy verification.
      rethrow;
    }
  }

  static Future<void> verifyBackup(Directory backup) async {
    final manifestFile = File(path.join(backup.path, 'manifest.json'));
    if (!await manifestFile.exists()) {
      throw const FormatException('Backup manifest is missing.');
    }
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported backup manifest.');
    }
    final files = decoded['files'];
    if (files is! List) throw const FormatException('Invalid backup manifest.');
    for (final raw in files) {
      if (raw is! Map) throw const FormatException('Invalid backup entry.');
      final relative = raw['backupRelativePath'];
      final size = raw['size'];
      final expectedHash = raw['sha256'];
      if (relative is! String || size is! int || expectedHash is! String) {
        throw const FormatException('Invalid backup entry.');
      }
      final file = File(path.join(backup.path, relative));
      if (!await file.exists() || await file.length() != size) {
        throw FileSystemException('Backup size verification failed', file.path);
      }
      if (await _hash(file) != expectedHash) {
        throw FileSystemException('Backup hash verification failed', file.path);
      }
    }
  }

  static Future<void> _copyFile(
    String sourceId,
    File source,
    Directory sourceRoot,
    Directory backup,
    List<Map<String, Object?>> records,
  ) async {
    final relative = path.relative(source.path, from: sourceRoot.path);
    if (path.isAbsolute(relative) || relative.startsWith('..')) {
      throw FileSystemException(
        'Backup file escaped its source root',
        source.path,
      );
    }
    final destination = File(
      path.join(backup.path, 'data', sourceId, relative),
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    final stat = await source.stat();
    final sourceHash = await _hash(source);
    if (await destination.length() != stat.size ||
        await _hash(destination) != sourceHash) {
      throw FileSystemException('Backup copy verification failed', source.path);
    }
    records.add({
      'sourceId': sourceId,
      'sourceAbsolutePath': source.absolute.path,
      'relativePath': relative,
      'backupRelativePath': path.relative(destination.path, from: backup.path),
      'size': stat.size,
      'mtimeUtc': stat.modified.toUtc().toIso8601String(),
      'sha256': sourceHash,
    });
  }

  static Future<String> _hash(File file) async =>
      sha256.bind(file.openRead()).first.then((digest) => digest.toString());
}
