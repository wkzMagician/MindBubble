import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final databaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError(),
);

class AppDatabase {
  AppDatabase._(this._database);
  final Database _database;

  static Future<AppDatabase> open() async {
    sqfliteFfiInit();
    final directory = await getApplicationDocumentsDirectory();
    final database = await databaseFactoryFfi.openDatabase(
      path.join(directory.path, 'mind_bubble.db'),
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await _createBubbles(db);
          await _createDailySelections(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _createDailySelections(db);
          if (oldVersion < 4) await _migrateToV4(db);
          if (oldVersion < 5) {
            await db.update('bubbles', {'appearance_frequency': 3});
          }
        },
      ),
    );
    return AppDatabase._(database);
  }

  Database get connection => _database;

  static Future<void> _createBubbles(Database db) => db.execute('''
    CREATE TABLE bubbles (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      last_shown_at INTEGER, shown_count INTEGER NOT NULL DEFAULT 0,
      appearance_frequency INTEGER NOT NULL DEFAULT 3,
      deleted_at INTEGER, field_versions TEXT NOT NULL DEFAULT ''
    )
  ''');

  static Future<void> _createDailySelections(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS daily_selections (
      date TEXT PRIMARY KEY, bubble_ids TEXT NOT NULL, generated_at INTEGER NOT NULL
    )
  ''');

  static Future<void> _migrateToV4(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.execute('ALTER TABLE bubbles RENAME TO bubbles_legacy');
    await _createBubbles(db);
    await db.execute(
      '''
      INSERT INTO bubbles (id,title,description,created_at,updated_at,last_shown_at,shown_count,appearance_frequency,field_versions)
      SELECT id,title,description,created_at,?,last_shown_at,shown_count,
        CASE familiarity WHEN 0 THEN 5 WHEN 2 THEN 1 ELSE 3 END, ''
      FROM bubbles_legacy
    ''',
      [now],
    );
    await db.execute('DROP TABLE bubbles_legacy');
  }
}
