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
    required this.subtitle,
    required this.icon,
    required this.description,
    required this.methods,
    required this.extensions,
    required this.instructions,
  });
  final ImportSourceApp app;
  final ImportSourceGroup group;
  final String title;
  final String subtitle;
  final IconData icon;
  final String description;
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
    subtitle: 'Vault · Markdown',
    icon: Icons.auto_awesome_outlined,
    description: '导入 Vault 中的 Markdown 笔记与本地图片。',
    methods: [ImportEntryMethod.folder, ImportEntryMethod.files],
    extensions: ['zip', 'md', 'markdown'],
    instructions: '推荐选择 Vault 根目录；也可选择包含笔记和附件的 ZIP，或若干 Markdown 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.notion,
    group: ImportSourceGroup.international,
    title: 'Notion',
    subtitle: 'ZIP 导出 / Integration API',
    icon: Icons.view_quilt_outlined,
    description: '导入 Notion 的 Markdown & CSV 导出包，或通过 Integration API 读取授权页面。',
    methods: [ImportEntryMethod.files, ImportEntryMethod.notionApi],
    extensions: ['zip'],
    instructions: '在 Notion 导出为 Markdown & CSV，选择得到的 ZIP 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.evernote,
    group: ImportSourceGroup.international,
    title: 'Evernote',
    subtitle: 'ENEX 导出',
    icon: Icons.note_alt_outlined,
    description: '读取 Evernote ENEX 笔记及内嵌图片。',
    methods: [ImportEntryMethod.files],
    extensions: ['enex', 'zip'],
    instructions: '在 Evernote 导出 .enex 文件，支持选择多个文件或包含 ENEX 的 ZIP。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.googleKeep,
    group: ImportSourceGroup.international,
    title: 'Google Keep',
    subtitle: 'Google Takeout',
    icon: Icons.lightbulb_outline,
    description: '导入 Google Keep 的便签、清单和标签。',
    methods: [ImportEntryMethod.files],
    extensions: ['zip', 'json'],
    instructions: '通过 Google Takeout 导出 Keep，选择 Takeout ZIP 或其中的 JSON 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.oneNote,
    group: ImportSourceGroup.international,
    title: 'Microsoft OneNote',
    subtitle: 'Microsoft Graph / HTML',
    icon: Icons.menu_book_outlined,
    description: '使用 Microsoft Graph 读取 OneNote 页面，也可导入已经转换成 HTML 的笔记。',
    methods: [ImportEntryMethod.oneNoteGraph, ImportEntryMethod.files],
    extensions: ['html', 'htm', 'zip'],
    instructions: '选择转换得到的 HTML 或 ZIP。OneNote 原生 .one 格式需要先转换。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.siyuan,
    group: ImportSourceGroup.china,
    title: '思源笔记',
    subtitle: '本地 API / Markdown',
    icon: Icons.hub_outlined,
    description: '通过运行中的思源内核读取文档，或导入 Markdown 导出。',
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
    subtitle: 'Markdown 导出',
    icon: Icons.library_books_outlined,
    description: '导入语雀知识库的 Markdown 或 HTML 笔记。',
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: ['md', 'markdown', 'html', 'htm', 'zip'],
    instructions: '选择 Markdown / HTML 导出文件或文件夹。API 接入需要相应授权，当前使用文件导入。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.flowUs,
    group: ImportSourceGroup.china,
    title: 'FlowUs 息流',
    subtitle: '页面导出',
    icon: Icons.dashboard_outlined,
    description: '导入 FlowUs 导出的 Markdown、HTML 和 CSV 页面。',
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: ['md', 'markdown', 'html', 'htm', 'csv', 'zip'],
    instructions:
        '从 FlowUs 导出页面，选择 Markdown / HTML / CSV 文件或 ZIP。API 接入尚需单独授权配置。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.feishu,
    group: ImportSourceGroup.china,
    title: '飞书文档',
    subtitle: '转换导入',
    icon: Icons.business_center_outlined,
    description: '读取飞书文档转换出的 Markdown、HTML 或 CSV 文件。',
    methods: [ImportEntryMethod.files, ImportEntryMethod.folder],
    extensions: ['md', 'markdown', 'html', 'htm', 'csv', 'zip'],
    instructions:
        '选择转换为 Markdown、HTML 或 CSV 的文件。原生飞书 Docx、Word、PDF 和开放平台连接尚未实现。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.flomo,
    group: ImportSourceGroup.china,
    title: 'flomo 浮墨笔记',
    subtitle: 'HTML 导出包',
    icon: Icons.sticky_note_2_outlined,
    description: '识别 flomo HTML 导出中的每条 memo，并导入文本和图片。',
    methods: [ImportEntryMethod.files],
    extensions: ['zip', 'html', 'htm'],
    instructions: '从 flomo 导出 HTML/ZIP，建议选择 ZIP，以同时提取 file/ 目录中的图片附件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.generic,
    group: ImportSourceGroup.generic,
    title: '通用导入',
    subtitle: '文件夹 · 多种格式',
    icon: Icons.file_upload_outlined,
    description: '适用于 Logseq 和其他软件已有的独立笔记文件。',
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

String importMethodDescription(ImportEntryMethod method) => switch (method) {
  ImportEntryMethod.folder => '扫描已导出笔记目录中的文件与图片',
  ImportEntryMethod.files => '读取从源软件导出的文件',
  ImportEntryMethod.notionApi => '用 Integration Token 读取已授权页面',
  ImportEntryMethod.oneNoteGraph => '用已授权的 Graph Access Token 读取页面',
  ImportEntryMethod.siyuanApi => '读取当前设备 127.0.0.1:6806 上的思源内核',
};
