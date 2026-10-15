import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// Each application advertises only the import entry points it supports.
enum ImportSourceApp {
  obsidian,
  logseq,
  notion,
  evernote,
  googleKeep,
  markdown,
  spreadsheet,
  mindBubble,
}

enum ImportEntryMethod { folder, files, notionApi }

class ImportSourceSpec {
  const ImportSourceSpec({
    required this.app,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.description,
    required this.methods,
    required this.extensions,
    required this.instructions,
  });

  final ImportSourceApp app;
  final String title;
  final String subtitle;
  final IconData icon;
  final String description;
  final List<ImportEntryMethod> methods;
  final List<String> extensions;
  final String instructions;

  String get id => app.name;
  ImportEntryMethod get recommended => methods.first;

  /// A stable import identity is needed so reimport detects changed notes.
  /// Vault-based tools default to the chosen vault name, whereas exports
  /// usually change filenames on every download.
  String suggestedIdentity(String? selectedPath) {
    if ((app == ImportSourceApp.obsidian ||
            app == ImportSourceApp.logseq ||
            app == ImportSourceApp.markdown) &&
        selectedPath != null) {
      final base = path.basename(path.normalize(selectedPath));
      final name = path.basenameWithoutExtension(base).trim();
      if (name.isNotEmpty) return '$id:$name';
    }
    return id;
  }

  bool allows(ImportEntryMethod method) => methods.contains(method);
}

const importSourceSpecs = <ImportSourceSpec>[
  ImportSourceSpec(
    app: ImportSourceApp.obsidian,
    title: 'Obsidian',
    subtitle: 'Vault · Markdown',
    icon: Icons.auto_awesome_outlined,
    description: '导入 Obsidian Vault 中的 Markdown 笔记与本地图片。',
    methods: [ImportEntryMethod.folder, ImportEntryMethod.files],
    extensions: ['zip', 'md', 'markdown'],
    instructions: '推荐直接选择 Vault 根目录，应用会读取子目录中的 .md 文件和图片。也可选择 Vault ZIP 导出包。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.logseq,
    title: 'Logseq',
    subtitle: 'Graph · Markdown',
    icon: Icons.account_tree_outlined,
    description: '导入 Logseq Graph 的页面、日志与相关图片。',
    methods: [ImportEntryMethod.folder, ImportEntryMethod.files],
    extensions: ['zip', 'md', 'markdown'],
    instructions: '选择 Graph 根目录（通常包含 pages、journals、assets），或选择其 ZIP 归档。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.notion,
    title: 'Notion',
    subtitle: '导出包 / API',
    icon: Icons.view_quilt_outlined,
    description: '支持 Notion 官方导出的 Markdown + CSV，也可通过 Integration API 读取授权页面。',
    methods: [ImportEntryMethod.files, ImportEntryMethod.notionApi],
    extensions: ['zip'],
    instructions: '在 Notion 中执行导出，选择 Markdown & CSV 格式，并上传 ZIP 文件。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.evernote,
    title: 'Evernote',
    subtitle: 'ENEX 导出',
    icon: Icons.note_alt_outlined,
    description: '读取 Evernote ENEX 笔记及其中的图片资源。',
    methods: [ImportEntryMethod.files],
    extensions: ['enex', 'zip'],
    instructions:
        '从 Evernote 导出笔记本为 .enex 文件；可以一次选择多个 ENEX 文件，或选择包含 ENEX 的 ZIP。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.googleKeep,
    title: 'Google Keep',
    subtitle: 'Takeout · JSON',
    icon: Icons.lightbulb_outline,
    description: '导入 Google Keep 便签、清单和标签。',
    methods: [ImportEntryMethod.files],
    extensions: ['zip', 'json'],
    instructions: '在 Google Takeout 中导出 Keep 数据，选择导出的 ZIP 文件或其中的多个 JSON 笔记。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.markdown,
    title: 'Markdown',
    subtitle: '通用 Markdown',
    icon: Icons.description_outlined,
    description: '适用于其他 Markdown 笔记软件与普通 Markdown 文件。',
    methods: [ImportEntryMethod.folder, ImportEntryMethod.files],
    extensions: ['md', 'markdown', 'zip'],
    instructions: '选择 Markdown 目录、一个或多个 .md 文件，或者包含 Markdown 与图片的 ZIP 包。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.spreadsheet,
    title: 'CSV / Excel',
    subtitle: '结构化表格',
    icon: Icons.table_chart_outlined,
    description: '将表格中的每行转换为独立笔记。',
    methods: [ImportEntryMethod.files],
    extensions: ['csv', 'xlsx'],
    instructions: '选择 CSV 或 XLSX 文件。使用 title / description 列（也支持标题、描述等常见列名）。',
  ),
  ImportSourceSpec(
    app: ImportSourceApp.mindBubble,
    title: 'MindBubble',
    subtitle: '标准 JSON',
    icon: Icons.bubble_chart_outlined,
    description: '从 MindBubble 标准 JSON 数据包迁移笔记。',
    methods: [ImportEntryMethod.files],
    extensions: ['json'],
    instructions: '选择符合 mind-bubble-import 格式的 JSON 文件，笔记原始 ID 将用于追踪后续更新。',
  ),
];

String importMethodLabel(ImportEntryMethod method) => switch (method) {
  ImportEntryMethod.folder => '选择文件夹',
  ImportEntryMethod.files => '选择文件 / 导出包',
  ImportEntryMethod.notionApi => 'Notion API 连接',
};

String importMethodDescription(ImportEntryMethod method) => switch (method) {
  ImportEntryMethod.folder => '直接扫描笔记目录及图片',
  ImportEntryMethod.files => '从软件导出的文件中读取笔记',
  ImportEntryMethod.notionApi => '使用 Integration Token 读取已授权页面',
};
