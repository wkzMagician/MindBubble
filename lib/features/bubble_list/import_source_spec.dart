import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

enum ImportSourceApp {
  obsidian,
  notion,
  evernote,
  googleKeep,
  oneNote,
  siyuan,
  yuque,
  flowUs,
  feishu,
  flomo,
  generic,
}

enum ImportSourceGroup { international, china, generic }

enum ImportEntryMethod { folder, files, notionApi, oneNoteGraph, siyuanApi }

class ImportSourceSpec {
  const ImportSourceSpec({
    required this.app,
    required this.group,
    required this.title,
    required this.icon,
    required this.methods,
    required this.extensions,
    required this.instructions,
  });
  final ImportSourceApp app;
  final ImportSourceGroup group;
  final String title;
  final IconData icon;
  final List<ImportEntryMethod> methods;
  final List<String> extensions;
  final String instructions;
  String get id => app.name;
  ImportEntryMethod get recommended => methods.first;
  String suggestedIdentity(String? selectedPath) {
    if ((app == ImportSourceApp.obsidian || app == ImportSourceApp.generic) &&
        selectedPath != null) {
      final name = path
          .basenameWithoutExtension(path.basename(path.normalize(selectedPath)))
          .trim();
      if (name.isNotEmpty) return '$id:$name';
    }
    return id;
  }

  bool allows(ImportEntryMethod method) => methods.contains(method);
}

const importSourceSpecs = <ImportSourceSpec>[
  ImportSourceSpec(
    app: ImportSourceApp.obsidian,
    group: ImportSourceGroup.international,
    title: 'Obsidian',
    icon: Icons.auto_awesome_outlined,
    methods: [ImportEntryMethod.folder, ImportEntryMethod.files],
    extensions: ['zip', 'md', 'markdown'],
    instructions: '推荐选择 Vault 根目录；也可选择包含笔记和附件的 ZIP，或若干 Markdown 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.notion,
    group: ImportSourceGroup.international,
    title: 'Notion',
    icon: Icons.view_quilt_outlined,
    methods: [ImportEntryMethod.files, ImportEntryMethod.notionApi],
    extensions: ['zip'],
    instructions: '在 Notion 导出为 Markdown & CSV，选择得到的 ZIP 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.evernote,
    group: ImportSourceGroup.international,
    title: 'Evernote',
    icon: Icons.note_alt_outlined,
    methods: [ImportEntryMethod.files],
    extensions: ['enex', 'zip'],
    instructions: '在 Evernote 导出 .enex 文件，支持选择多个文件或包含 ENEX 的 ZIP。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.googleKeep,
    group: ImportSourceGroup.international,
    title: 'Google Keep',
    icon: Icons.lightbulb_outline,
    methods: [ImportEntryMethod.files],
    extensions: ['zip', 'json'],
    instructions: '通过 Google Takeout 导出 Keep，选择 Takeout ZIP 或其中的 JSON 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.oneNote,
    group: ImportSourceGroup.international,
    title: 'Microsoft OneNote',
    icon: Icons.menu_book_outlined,
    methods: [ImportEntryMethod.oneNoteGraph, ImportEntryMethod.files],
    extensions: ['html', 'htm', 'zip'],
    instructions: '选择转换得到的 HTML 或 ZIP。OneNote 原生 .one 格式需要先转换。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.siyuan,
    group: ImportSourceGroup.china,
    title: '思源笔记',
    icon: Icons.hub_outlined,
    methods: [
      ImportEntryMethod.siyuanApi,
      ImportEntryMethod.folder,
      ImportEntryMethod.files,
    ],
    extensions: ['md', 'markdown', 'zip'],
    instructions: '选择思源导出的 Markdown 文件夹或 ZIP；移动端可导入导出包。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.yuque,
    group: ImportSourceGroup.china,
    title: '语雀',
    icon: Icons.library_books_outlined,
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: ['md', 'markdown', 'html', 'htm', 'zip'],
    instructions: '选择 Markdown / HTML 导出文件或文件夹。API 接入需要相应授权，当前使用文件导入。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.flowUs,
    group: ImportSourceGroup.china,
    title: 'FlowUs 息流',
    icon: Icons.dashboard_outlined,
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: ['md', 'markdown', 'html', 'htm', 'csv', 'zip'],
    instructions:
        '从 FlowUs 导出页面，选择 Markdown / HTML / CSV 文件或 ZIP。API 接入尚需单独授权配置。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.feishu,
    group: ImportSourceGroup.china,
    title: '飞书文档',
    icon: Icons.business_center_outlined,
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: ['md', 'markdown', 'html', 'htm', 'csv', 'zip'],
    instructions:
        '选择转换为 Markdown、HTML 或 CSV 的文件。原生飞书 Docx、Word、PDF 和开放平台连接尚未实现。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.flomo,
    group: ImportSourceGroup.china,
    title: 'flomo 浮墨笔记',
    icon: Icons.sticky_note_2_outlined,
    methods: [ImportEntryMethod.files],
    extensions: ['zip', 'html', 'htm'],
    instructions: '从 flomo 导出 HTML/ZIP，建议选择 ZIP，以同时提取 file/ 目录中的图片附件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.generic,
    group: ImportSourceGroup.generic,
    title: '通用导入',
    icon: Icons.file_upload_outlined,
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: [
      'md',
      'markdown',
      'html',
      'htm',
      'zip',
      'json',
      'csv',
      'xlsx',
      'enex',
    ],
    instructions:
        '支持 Markdown、HTML、JSON、CSV、XLSX、ENEX、ZIP、文件夹。Logseq Graph 可选择 Markdown 目录。',
  ),
];

String importMethodLabel(ImportEntryMethod method) => switch (method) {
  ImportEntryMethod.folder => '选择文件夹',
  ImportEntryMethod.files => '选择文件 / 导出包',
  ImportEntryMethod.notionApi => 'Notion API 连接',
  ImportEntryMethod.oneNoteGraph => 'Microsoft Graph 连接',
  ImportEntryMethod.siyuanApi => '思源本地 API 连接',
};
