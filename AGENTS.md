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
