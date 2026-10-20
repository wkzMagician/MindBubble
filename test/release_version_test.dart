import 'package:flutter_test/flutter_test.dart';

import '../tool/release_version.dart';

void main() {
  test('all platforms receive the explicit version and build number', () {
    final version = ReleaseVersion.fromPubspec('version: 0.4.9+8\n');
    expect(version.buildName, '0.4.9');
    expect(version.buildNumber, 8);
  });

  test('new builds cannot silently fall back to versionCode 1', () {
    expect(
      () => ReleaseVersion.fromPubspec('version: 0.4.9'),
      throwsFormatException,
    );
  });

  test('version must fit Windows executable version fields', () {
    for (final value in ['0.4.9+65536', '65536.0.0+8', '0.4.9+0']) {
      expect(
        () => ReleaseVersion.fromPubspec('version: $value'),
        throwsFormatException,
      );
    }
  });

  final previous = {'v0.4.1': 'version: 0.4.1+6', 'v0.4.8': 'version: 0.4.8'};

  test('tag releases require both version and build number to advance', () {
    validateReleaseVersion(
      ReleaseVersion.fromPubspec('version: 0.4.9+7'),
      'refs/tags/v0.4.9',
      previous,
    );
    for (final value in ['0.4.9+6', '0.4.9+1']) {
      expect(
        () => validateReleaseVersion(
          ReleaseVersion.fromPubspec('version: $value'),
          'refs/tags/v0.4.9',
          previous,
        ),
        throwsFormatException,
      );
    }
  });

  test('tag and source version must match', () {
    expect(
      () => validateReleaseVersion(
        ReleaseVersion.fromPubspec('version: 0.4.8+7'),
        'refs/tags/v0.4.9',
        previous,
      ),
      throwsFormatException,
    );
  });

  test('numeric version comparison rejects older releases', () {
    expect(
      () => validateReleaseVersion(
        ReleaseVersion.fromPubspec('version: 0.4.9+9'),
        'refs/tags/v0.4.9',
        {'v0.4.10': 'version: 0.4.10+8'},
      ),
      throwsFormatException,
    );
  });

  test('same tag may be rebuilt without comparing against itself', () {
    validateReleaseVersion(
      ReleaseVersion.fromPubspec('version: 0.4.9+8'),
      'refs/tags/v0.4.9',
      {...previous, 'v0.4.9': 'version: 0.4.9+8'},
    );
  });

  test('branch builds do not require a new release tag', () {
    validateReleaseVersion(
      ReleaseVersion.fromPubspec('version: 0.4.8+7'),
      'refs/heads/main',
      previous,
    );
  });

  test('unsupported tag formats fail before building', () {
    for (final tag in ['v0.4.9-rc.1', 'v0.4', 'v01.4.9']) {
      expect(
        () => validateReleaseVersion(
          ReleaseVersion.fromPubspec('version: 0.4.9+8'),
          'refs/tags/$tag',
          previous,
        ),
        throwsFormatException,
      );
    }
  });
}
