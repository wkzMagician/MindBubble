import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final deviceIdentityProvider = Provider<DeviceIdentity>(
  (_) => throw UnimplementedError(),
);

class DeviceIdentity {
  const DeviceIdentity(this.id);

  final String id;

  static Future<DeviceIdentity> load() async {
    final support = await getApplicationSupportDirectory();
    final file = File(path.join(support.path, 'MindBubble', 'device-id'));
    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) return DeviceIdentity(existing);
    }
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await file.parent.create(recursive: true);
    await file.writeAsString(id, flush: true);
    return DeviceIdentity(id);
  }
}
