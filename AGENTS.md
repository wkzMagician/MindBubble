# Agent Instructions

This project uses Dartloom as ordinary Dart/Flutter packages. The selected
platforms and packages are recorded in `.dartloom/project.yaml`; Web is not a
supported target.

Business code belongs in `lib/features`; shared application glue belongs in
`lib/app` and `lib/services`. Import Dartloom contracts and adapters through
their package libraries. Do not recreate a runtime registry or generated
capability/bootstrap layer in this application.

The application owns its document paths. Dartloom storage is opened with the
absolute MindBubble document directory, and singleton ownership is acquired
through `dartloom_singleton_socket` during startup.

Before finishing, run `dart format .`, `flutter analyze`, and `flutter test`.

<!-- dartloom:begin -->
## Dartloom packages

Selected platforms: Android, Ios, Windows, Macos, Linux

### Dartloom SDK

Package: `dartloom`

- Platforms: Android, Ios, Windows, Macos, Linux, Web
- Purpose: Stable Dartloom contract facade.
- Main API: Dartloom SDK
- Import:

  ```dart
  import 'package:dartloom/dartloom.dart';
  ```

### Singleton

Package: `dartloom_singleton`

- Platforms: Android, Ios, Windows, Macos, Linux, Web
- Purpose: Singleton package for Dart and Flutter applications.
- Main API: Singleton
- Import:

  ```dart
  import 'package:dartloom_singleton/dartloom_singleton.dart';
  ```

### Singleton Socket

Package: `dartloom_singleton_socket`

- Platforms: Android, Ios, Windows, Macos, Linux, Web
- Purpose: Singleton Socket package for Dart and Flutter applications.
- Main API: SingletonSocket
- Import:

  ```dart
  import 'package:dartloom_singleton_socket/dartloom_singleton_socket.dart';
  ```

### Synchronization Contracts

Package: `dartloom_sync`

- Platforms: Android, Ios, Windows, Macos, Linux, Web
- Purpose: Stable synchronization contracts.
- Main API: SyncService
- Import:

  ```dart
  import 'package:dartloom_sync/dartloom_sync.dart';
  ```

### Storage Contracts

Package: `dartloom_storage`

- Platforms: Android, Ios, Windows, Macos, Linux, Web
- Purpose: Stable binary object-storage contracts.
- Main API: ObjectStore
- Import:

  ```dart
  import 'package:dartloom_storage/dartloom_storage.dart';
  ```

### File Object Storage

Package: `dartloom_storage_file`

- Platforms: Android, Ios, Windows, Macos, Linux
- Purpose: Directory-backed binary object storage.
- Main API: FileObjectStore
- Import:

  ```dart
  import 'package:dartloom_storage_file/dartloom_storage_file.dart';
  ```

<!-- dartloom:end -->
