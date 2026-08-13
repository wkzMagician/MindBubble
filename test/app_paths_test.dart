import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/app/app_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolves redirected Documents paths containing spaces and Unicode', () {
    final root = Directory(p.join(Directory.systemTemp.path, '用户 Data'));
    final paths = MindBubblePaths.fromRoots(
      documents: Directory(p.join(root.path, 'My Documents')),
      support: Directory(p.join(root.path, 'App Support')),
    );

    expect(
      paths.businessRoot.path,
      p.normalize(p.join(root.path, 'My Documents', 'MindBubble', 'bubbles')),
    );
    expect(
      paths.metadataRoot.path,
      p.normalize(
        p.join(root.path, 'App Support', 'MindBubble', 'dartloom', 'replica'),
      ),
    );
    expect(
      p.isWithin(paths.businessRoot.path, paths.metadataRoot.path),
      isFalse,
    );
  });
}
