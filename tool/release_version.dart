import 'dart:io';

final _versionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+([1-9]\d*))?$',
);
final _tagPattern = RegExp(r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');

class ReleaseVersion {
  ReleaseVersion(this.major, this.minor, this.patch, this.buildNumber);

  final int major;
  final int minor;
  final int patch;
  final int buildNumber;

  String get buildName => '$major.$minor.$patch';

  factory ReleaseVersion.fromPubspec(String source, {bool legacy = false}) {
    final value = RegExp(
      r'^version:\s*([^\r\n#]+)',
      multiLine: true,
    ).firstMatch(source)?.group(1)?.trim();
    final match = value == null ? null : _versionPattern.firstMatch(value);
    if (match == null || (!legacy && match.group(4) == null)) {
      throw FormatException('pubspec.yaml must declare version: X.Y.Z+BUILD');
    }
    final parts = [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
    final build = int.parse(match.group(4) ?? '1');
    // The Windows executable stores four unsigned 16-bit version components.
    if ([...parts, build].any((value) => value > 65535)) {
      throw FormatException('Version components must not exceed 65535');
    }
    return ReleaseVersion(parts[0], parts[1], parts[2], build);
  }

  int compareName(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }
}

void validateReleaseVersion(
  ReleaseVersion current,
  String ref,
  Map<String, String> previousPubspecs,
) {
  if (!ref.startsWith('refs/tags/')) return;
  final tag = ref.substring('refs/tags/'.length);
  if (!_tagPattern.hasMatch(tag)) {
    throw FormatException('Release tags must use vX.Y.Z: $tag');
  }
  if (tag != 'v${current.buildName}') {
    throw FormatException(
      'Tag $tag does not match pubspec.yaml version ${current.buildName}',
    );
  }
  for (final entry in previousPubspecs.entries) {
    if (entry.key == tag || !_tagPattern.hasMatch(entry.key)) continue;
    final taggedVersion = ReleaseVersion.fromPubspec(
      'version: ${entry.key.substring(1)}+1',
    );
    if (current.compareName(taggedVersion) <= 0) {
      throw FormatException('Version must be newer than tag ${entry.key}');
    }
    final previous = ReleaseVersion.fromPubspec(entry.value, legacy: true);
    if (current.buildNumber <= previous.buildNumber) {
      throw FormatException(
        'Build number ${current.buildNumber} must exceed '
        '${previous.buildNumber} from ${entry.key}',
      );
    }
  }
}

Future<String> _git(List<String> arguments) async {
  final result = await Process.run('git', arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      arguments,
      '${result.stderr}',
      result.exitCode,
    );
  }
  return '${result.stdout}'.trim();
}

Future<void> main() async {
  try {
    final current = ReleaseVersion.fromPubspec(
      File('pubspec.yaml').readAsStringSync(),
    );
    final requestedRef =
        Platform.environment['RELEASE_REF'] ??
        Platform.environment['GITHUB_REF'] ??
        '';
    final ref = requestedRef.startsWith('v')
        ? 'refs/tags/$requestedRef'
        : requestedRef;
    final previous = <String, String>{};
    if (ref.startsWith('refs/tags/')) {
      final tags = await _git(['tag', '--list', 'v*']);
      for (final tag in tags.split('\n')) {
        if (!_tagPattern.hasMatch(tag) || ref == 'refs/tags/$tag') continue;
        previous[tag] = await _git(['show', '$tag:pubspec.yaml']);
      }
    }
    validateReleaseVersion(current, ref, previous);
    final output =
        'build_name=${current.buildName}\n'
        'build_number=${current.buildNumber}\n';
    final outputPath = Platform.environment['GITHUB_OUTPUT'];
    if (outputPath != null) {
      File(outputPath).writeAsStringSync(output, mode: FileMode.append);
    }
    stdout.write(output);
  } on Object catch (error) {
    stderr.writeln('Release version validation failed: $error');
    exitCode = 1;
  }
}
