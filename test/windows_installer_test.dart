import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows installer preserves application and uninstall icons', () {
    final installer = File('installer/windows.iss');

    expect(installer.existsSync(), isTrue);
    final source = installer.readAsStringSync();
    expect(
      source,
      contains('AppIconFile "..\\windows\\runner\\resources\\app_icon.ico"'),
    );
    expect(source, contains('SetupIconFile={#AppIconFile}'));
    expect(source, contains(r'UninstallDisplayIcon={app}\{#MyAppExeName}'));
  });
}
