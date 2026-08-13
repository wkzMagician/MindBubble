import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class MindBubblePaths {
  const MindBubblePaths({
    required this.businessRoot,
    required this.metadataRoot,
    required this.supportRoot,
  });

  final Directory businessRoot;
  final Directory metadataRoot;
  final Directory supportRoot;

  static Future<MindBubblePaths> resolve() async {
    final documents = (await getApplicationDocumentsDirectory()).absolute;
    final support = (await getApplicationSupportDirectory()).absolute;
    return fromRoots(documents: documents, support: support);
  }

  static MindBubblePaths fromRoots({
    required Directory documents,
    required Directory support,
  }) {
    documents = documents.absolute;
    support = support.absolute;
    final appSupport = Directory(p.join(support.path, 'MindBubble')).absolute;
    return MindBubblePaths(
      businessRoot: Directory(
        p.join(documents.path, 'MindBubble', 'bubbles'),
      ).absolute,
      metadataRoot: Directory(
        p.join(appSupport.path, 'dartloom', 'replica'),
      ).absolute,
      supportRoot: appSupport,
    );
  }
}
