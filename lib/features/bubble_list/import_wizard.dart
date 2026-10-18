import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../repositories/bubble_repository.dart';
import '../../services/bubble_document_store.dart';
import '../../services/bulk_import_service.dart';
import '../../services/notion_import_adapter.dart';
import '../../services/onenote_graph_adapter.dart';
import '../../services/siyuan_import_adapter.dart';
import '../../services/visual_theme_service.dart';
import 'import_source_spec.dart';

/// Choose an application first; each application exposes only compatible
/// import methods, with a shared incremental preview and conflict workflow.
class ImportWizard extends ConsumerStatefulWidget {
  const ImportWizard({super.key});

  @override
  ConsumerState<ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends ConsumerState<ImportWizard> {
  final _identity = TextEditingController(text: importSourceSpecs.first.id);
  final _notionToken = TextEditingController();
  final _oneNoteToken = TextEditingController();
  final _siyuanToken = TextEditingController();
  ImportSourceSpec _selected = importSourceSpecs.first;
  ImportEntryMethod _method = importSourceSpecs.first.recommended;
  ImportPreview? _preview;
  ImportConflictChoice _conflictChoice = ImportConflictChoice.keepLocal;
  String? _pickedLabel;
  String? _error;
  bool _identityEdited = false;
  bool _busy = false;

  BulkImportService get _service => BulkImportService(
    ref.read(bubbleRepositoryProvider),
    ref.read(bubbleDocumentStoreProvider),
  );

  @override
  void dispose() {
    _identity.dispose();
    _notionToken.dispose();
    _oneNoteToken.dispose();
    _siyuanToken.dispose();
    super.dispose();
  }

  void _chooseSource(ImportSourceSpec source) {
    if (_busy) return;
    setState(() {
      _selected = source;
      _method = source.recommended;
      _identity.text = source.id;
      _identityEdited = false;
      _notionToken.clear();
      _oneNoteToken.clear();
      _siyuanToken.clear();
      _preview = null;
      _pickedLabel = null;
      _error = null;
      _conflictChoice = ImportConflictChoice.keepLocal;
    });
  }

  void _chooseMethod(ImportEntryMethod method) {
    if (_busy || !_selected.allows(method)) return;
    setState(() {
      _method = method;
      _preview = null;
      _pickedLabel = null;
      _error = null;
    });
  }

  Future<void> _selectInput() async {
    final currentSource = _selected;
    final currentMethod = _method;
    if (currentMethod == ImportEntryMethod.notionApi) {
      await _scanNotion();
      return;
    }
    if (currentMethod == ImportEntryMethod.oneNoteGraph) {
      await _scanOneNote();
      return;
    }
    if (currentMethod == ImportEntryMethod.siyuanApi) {
      await _scanSiYuan();
      return;
    }
    try {
      if (currentMethod == ImportEntryMethod.folder) {
        final directory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择 ${currentSource.title} 笔记目录',
        );
        if (directory == null || !mounted) return;
        await _scan(
          directory,
          () => _service.readDirectory(Directory(directory)),
        );
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: currentSource.extensions,
          allowMultiple: true,
          dialogTitle: '选择 ${currentSource.title} 导出文件',
        );
        if (picked == null || !mounted) return;
        final files = picked.files
            .where((entry) => entry.path != null)
            .map((entry) => File(entry.path!))
            .toList();
        if (files.isEmpty) return;
        final label = files.length == 1
            ? path.basename(files.single.path)
            : '${files.length} 个文件';
        await _scan(label, () async {
          final notes = <ImportCandidate>[];
          for (final file in files) {
            notes.addAll(await _service.readFile(file));
          }
          return notes;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _scanNotion() async {
    if (_notionToken.text.trim().isEmpty) {
      setState(() => _error = '请填写 Notion Integration Token');
      return;
    }
    final client = NotionImportAdapter();
    try {
      await _scan('Notion API', () => client.load(_notionToken.text.trim()));
    } finally {
      client.close();
    }
  }

  Future<void> _scanOneNote() async {
    if (_oneNoteToken.text.trim().isEmpty) {
      setState(() => _error = '请填写 Microsoft Graph Access Token');
      return;
    }
    final client = OneNoteGraphAdapter();
    try {
      await _scan(
        'Microsoft Graph',
        () => client.load(_oneNoteToken.text.trim()),
      );
    } finally {
      client.close();
    }
  }

  Future<void> _scanSiYuan() async {
    if (_siyuanToken.text.trim().isEmpty) {
      setState(() => _error = '请填写思源 API Token');
      return;
    }
    final client = SiYuanImportAdapter();
    try {
      await _scan('思源本地内核', () => client.load(_siyuanToken.text.trim()));
    } finally {
      client.close();
    }
  }

  Future<void> _scan(
    String inputLabel,
    Future<List<ImportCandidate>> Function() reader,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      if (!_identityEdited) {
        _identity.text = _selected.suggestedIdentity(
          _method == ImportEntryMethod.folder ? inputLabel : null,
        );
      }
      final sourceId = _identity.text.trim();
      if (sourceId.isEmpty) {
        throw const FormatException('请输入用于后续增量导入的来源标识');
      }
      final candidates = await reader();
      if (candidates.isEmpty) {
        throw FormatException('未找到可导入的笔记。请确认选择了 ${_selected.title} 支持的导出格式。');
      }
      final preview = await _service.preview(sourceId, candidates);
      if (preview.items.isEmpty) {
        throw const FormatException('找到文件，但其中没有有效的笔记标题和正文');
      }
      if (mounted) {
        setState(() {
          _pickedLabel = inputLabel;
          _preview = preview;
          _conflictChoice = ImportConflictChoice.keepLocal;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await _service.commit(
        preview,
        conflictChoice: _conflictChoice,
      );
      if (mounted) Navigator.of(context).pop(count);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final wide = viewport.width >= 740;
    final activeColor = context.appAccent;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: context.appPanel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: min(viewport.width - 32, 1050),
        height: min(viewport.height - 32, 770),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 14, 14),
              child: Row(
                children: [
                  Icon(Icons.move_to_inbox_outlined, color: activeColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '从其他应用导入',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.appBorder),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        SizedBox(
                          width: 240,
                          child: _sourceList(vertical: true),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: context.appBorder,
                        ),
                        Expanded(child: _detailPanel()),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 120,
                          child: _sourceList(vertical: false),
                        ),
                        Divider(height: 1, color: context.appBorder),
                        Expanded(child: _detailPanel()),
                      ],
                    ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Divider(height: 1, color: context.appBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                children: [
                  if (_preview != null)
                    Flexible(
                      child: Text(
                        '已扫描 ${_preview!.items.length} 条笔记',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy || _preview == null ? null : _commit,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('确认导入'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceList({required bool vertical}) {
    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(16, 17, 12, 10),
      child: Text(
        '来源应用',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final cards = [
      for (final spec in importSourceSpecs)
        _sourceCard(spec, vertical: vertical),
    ];
    if (!vertical) {
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
        children: cards,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        heading,
        for (final group in ImportSourceGroup.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 10, 6),
            child: Text(
              switch (group) {
                ImportSourceGroup.international => '国际软件',
                ImportSourceGroup.china => '国内软件',
                ImportSourceGroup.generic => '其他',
              },
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final source in importSourceSpecs.where(
            (source) => source.group == group,
          ))
            _sourceCard(source, vertical: true),
        ],
      ],
    );
  }

  Widget _sourceCard(ImportSourceSpec source, {required bool vertical}) {
    final selected = source.app == _selected.app;
    final accent = context.appAccent;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: vertical ? 9 : 4, vertical: 3),
      child: Material(
        color: selected ? context.appActive : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? accent.withValues(alpha: .35)
                : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _busy ? null : () => _chooseSource(source),
          child: Container(
            width: vertical ? null : 148,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  source.icon,
                  size: 22,
                  color: selected
                      ? accent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailPanel() {
    final source = _selected;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(25, 20, 25, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(source.icon, size: 27, color: context.appAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('导入方式', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final method in source.methods)
            _methodCard(method, recommended: method == source.recommended),
          const SizedBox(height: 15),
          _instructions(),
          const SizedBox(height: 16),
          if (_method == ImportEntryMethod.notionApi) ...[
            TextField(
              controller: _notionToken,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Notion Integration Token',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_method == ImportEntryMethod.oneNoteGraph) ...[
            TextField(
              controller: _oneNoteToken,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Microsoft Graph Access Token',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_method == ImportEntryMethod.siyuanApi) ...[
            TextField(
              controller: _siyuanToken,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '思源 API Token',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _selectInput,
              icon: Icon(
                (_method == ImportEntryMethod.notionApi ||
                        _method == ImportEntryMethod.oneNoteGraph ||
                        _method == ImportEntryMethod.siyuanApi)
                    ? Icons.cloud_download_outlined
                    : _method == ImportEntryMethod.folder
                    ? Icons.folder_open_outlined
                    : Icons.upload_file_outlined,
                size: 19,
              ),
              label: Text(
                _method == ImportEntryMethod.notionApi
                    ? '读取 Notion 页面'
                    : _method == ImportEntryMethod.oneNoteGraph
                    ? '读取 OneNote 页面'
                    : _method == ImportEntryMethod.siyuanApi
                    ? '读取思源文档'
                    : _method == ImportEntryMethod.folder
                    ? '选择 ${source.title} 文件夹'
                    : '选择 ${source.title} 导出文件',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            key: ValueKey(source.app),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('增量导入设置', style: TextStyle(fontSize: 13)),
            children: [
              TextField(
                controller: _identity,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '来源标识（重复导入时保持一致）'),
                onChanged: (_) {
                  setState(() {
                    _identityEdited = true;
                    _preview = null;
                    _pickedLabel = null;
                  });
                },
              ),
            ],
          ),
          if (_pickedLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已扫描：${_pickedLabel!}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_preview != null) _previewSection(_preview!),
        ],
      ),
    );
  }

  Widget _methodCard(ImportEntryMethod method, {required bool recommended}) {
    final active = _method == method;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: active ? context.appActive : context.appField,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: active
                ? context.appAccent.withValues(alpha: .6)
                : context.appBorder,
          ),
        ),
        child: InkWell(
          onTap: _busy ? null : () => _chooseMethod(method),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                Icon(
                  active ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: active
                      ? context.appAccent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 19,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              importMethodLabel(method),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 9),
                            Text(
                              '推荐',
                              style: TextStyle(
                                color: context.appAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _instructions() {
    final text = switch (_method) {
      ImportEntryMethod.notionApi =>
        '在 Notion 创建 Internal Integration，将页面共享给它后复制 Integration Token。',
      ImportEntryMethod.oneNoteGraph =>
        '使用具有 Notes.Read 委托权限的 Microsoft Graph Access Token。',
      ImportEntryMethod.siyuanApi => '在本设备运行思源笔记，从“设置 → 关于”复制 API Token。',
      _ => _selected.instructions,
    };
    return ExpansionTile(
      key: ValueKey('import-help-${_selected.app.name}-${_method.name}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text('导入帮助'),
      children: [Align(alignment: Alignment.centerLeft, child: Text(text))],
    );
  }

  Widget _previewSection(ImportPreview preview) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appField,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '导入预览 · ${preview.items.length} 条',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _countChip(preview, ImportAction.add, '新增'),
              _countChip(preview, ImportAction.update, '更新'),
              _countChip(preview, ImportAction.unchanged, '未变化'),
              _countChip(preview, ImportAction.conflict, '冲突'),
            ],
          ),
          if (preview.count(ImportAction.conflict) > 0) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<ImportConflictChoice>(
              initialValue: _conflictChoice,
              decoration: const InputDecoration(labelText: '冲突处理方式'),
              items: const [
                DropdownMenuItem(
                  value: ImportConflictChoice.keepLocal,
                  child: Text('保留本地内容'),
                ),
                DropdownMenuItem(
                  value: ImportConflictChoice.useSource,
                  child: Text('采用导入内容'),
                ),
                DropdownMenuItem(
                  value: ImportConflictChoice.duplicate,
                  child: Text('另存副本'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _conflictChoice = value);
                      }
                    },
            ),
          ],
          const SizedBox(height: 10),
          for (final item in preview.items.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    _actionIcon(item.action),
                    size: 14,
                    color: item.action == ImportAction.conflict
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (preview.items.length > 5)
            Text(
              '另有 ${preview.items.length - 5} 条笔记',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _countChip(ImportPreview preview, ImportAction action, String label) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label ${preview.count(action)}'),
    );
  }

  IconData _actionIcon(ImportAction action) => switch (action) {
    ImportAction.add => Icons.add_circle_outline,
    ImportAction.update => Icons.update,
    ImportAction.unchanged => Icons.remove_circle_outline,
    ImportAction.conflict => Icons.warning_amber_rounded,
  };
}
