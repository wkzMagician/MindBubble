import 'dart:convert';

import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_settings_shared_preferences/dartloom_settings_shared_preferences.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';

import '../app/app_paths.dart';

/// Keep model metadata out of the legacy preferences file, whose cached
/// whole-file writes can otherwise overwrite a newly saved model connection.
class ModelPreferencesStore implements SettingsStore {
  ModelPreferencesStore(this.objects, this.legacy);
  final ObjectStore objects;
  final SettingsStore legacy;

  static Future<ModelPreferencesStore> open() async {
    final paths = await MindBubblePaths.resolve();
    return ModelPreferencesStore(
      await FileObjectStore.open(root: paths.metadataRoot),
      SharedPreferencesSettingsStore(),
    );
  }

  String _key(String key) => 'model-settings/${Uri.encodeComponent(key)}.json';

  @override
  Future<Object?> read(String key) async {
    final stored = await objects.read(_key(key));
    if (stored != null) return jsonDecode(utf8.decode(stored));
    final previous = await legacy.read(key);
    // A concurrent migration/save wins over the legacy snapshot.
    final current = await objects.read(_key(key));
    if (current != null) return jsonDecode(utf8.decode(current));
    if (previous != null) await write(key, previous);
    return previous;
  }

  @override
  Future<void> write(String key, Object value) =>
      objects.write(_key(key), utf8.encode(jsonEncode(value)));

  @override
  Future<void> remove(String key) =>
      objects.write(_key(key), utf8.encode('null'));
}
