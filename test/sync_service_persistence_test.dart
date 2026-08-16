import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/services/sync_service.dart';

void main() {
  test(
    'saved WebDAV account and key are available to a new service instance',
    () async {
      final persistence = MemorySyncPersistence();
      final first = SyncService(persistence: persistence);

      await first.configureWebDav(
        serverUrl: ' https://dav.example.test/dav/ ',
        username: ' account@example.test ',
        appPassword: 'app-key',
      );

      final second = SyncService(persistence: persistence);
      final config = await second.loadConfig();

      expect(config?.serverUrl, 'https://dav.example.test/dav/');
      expect(config?.username, 'account@example.test');
      expect(second.isConfigured, isTrue);
      await first.dispose();
      await second.dispose();
    },
  );

  test('saving without a new key keeps the existing key', () async {
    final persistence = MemorySyncPersistence();
    final service = SyncService(persistence: persistence);

    await service.configureWebDav(
      serverUrl: 'https://dav.example.test/dav/',
      username: 'old@example.test',
      appPassword: 'keep-me',
    );
    await service.configureWebDav(
      serverUrl: 'https://dav.example.test/dav/',
      username: 'new@example.test',
      appPassword: '',
    );

    final reloaded = SyncService(persistence: persistence);
    expect((await reloaded.loadConfig())?.username, 'new@example.test');
    expect(reloaded.isConfigured, isTrue);
    await service.dispose();
    await reloaded.dispose();
  });
}
