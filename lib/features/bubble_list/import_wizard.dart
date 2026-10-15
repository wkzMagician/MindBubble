import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../repositories/bubble_repository.dart';
import '../../services/bubble_document_store.dart';
import '../../services/bulk_import_service.dart';
import '../../services/notion_import_adapter.dart';

class ImportWizard extends ConsumerStatefulWidget {
  const ImportWizard({super.key});
  @override
  ConsumerState<ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends ConsumerState<ImportWizard> {
  final _source = TextEditingController();
  final _notionToken = TextEditingController();
  ImportPreview? _preview;
  bool _busy = false;
  String? _error;
  ImportConflictChoice _conflictChoice = ImportConflictChoice.keepLocal;

  BulkImportService get _service => BulkImportService(
    ref.read(bubbleRepositoryProvider),
    ref.read(bubbleDocumentStoreProvider),
  );

  @override
  void dispose() {
    _source.dispose();
    _notionToken.dispose();
    super.dispose();
  }

  Future<void> _select({required bool folder}) async {
    try {
      if (folder) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择笔记文件夹',
        );
        if (dir == null) return;
        await _scan(dir, () => _service.readDirectory(Directory(dir)));
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'zip',
            'md',
            'markdown',
            'enex',
            'json',
            'csv',
            'xlsx',
          ],
          allowMultiple: true,
        );
        if (result == null) return;
        final files = result.files
            .where((file) => file.path != null)
            .map((file) => File(file.path!))
            .toList();
        if (files.isEmpty) return;
        await _scan(files.first.path, () async {
          final notes = <ImportCandidate>[];
          for (final file in files) {
            notes.addAll(await _service.readFile(file));
          }
          return notes;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  Future<void> _scanNotion() async {
    if (_source.text.trim().isEmpty) _source.text = 'notion';
    final client = NotionImportAdapter();
    try {
      await _scan('notion', () => client.load(_notionToken.text));
    } finally {
      client.close();
    }
  }

  Future<void> _scan(
    String selected,
    Future<List<ImportCandidate>> Function() reader,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      if (_source.text.trim().isEmpty) {
        _source.text = path.basenameWithoutExtension(selected);
      }
      final notes = await reader();
      final preview = await _service.preview(_source.text.trim(), notes);
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
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
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('批量增量导入'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _source,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '来源名称',
                  helperText: '同一来源每次使用相同名称，自动识别新增和更新',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _select(folder: true),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件夹'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _select(folder: false),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('选择文件 / ZIP'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notionToken,
                obscureText: true,
                enabled: !_busy && _preview == null,
                decoration: const InputDecoration(
                  labelText: 'Notion Integration Token',
                  helperText: '仅本次连接使用；请先将页面共享给 Notion Integration',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _scanNotion,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('从 Notion API 增量导入'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '支持 Obsidian / Logseq Markdown、Notion ZIP、Evernote ENEX、Google Keep JSON、CSV 和 XLSX',
                style: TextStyle(fontSize: 12),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (preview != null) ...[
                const Divider(height: 30),
                Text(
                  '扫描结果 · ${preview.items.length} 条笔记',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    _count(preview, ImportAction.add, '新增'),
                    _count(preview, ImportAction.update, '更新'),
                    _count(preview, ImportAction.unchanged, '未变化'),
                    _count(preview, ImportAction.conflict, '冲突'),
                  ],
                ),
                if (preview.count(ImportAction.conflict) > 0) ...[
                  const SizedBox(height: 15),
                  DropdownButtonFormField<ImportConflictChoice>(
                    initialValue: _conflictChoice,
                    decoration: const InputDecoration(labelText: '冲突处理'),
                    items: const [
                      DropdownMenuItem(
                        value: ImportConflictChoice.keepLocal,
                        child: Text('保留本地'),
                      ),
                      DropdownMenuItem(
                        value: ImportConflictChoice.useSource,
                        child: Text('采用来源'),
                      ),
                      DropdownMenuItem(
                        value: ImportConflictChoice.duplicate,
                        child: Text('保存副本'),
                      ),
                    ],
                    onChanged: (choice) {
                      if (choice != null) {
                        setState(() => _conflictChoice = choice);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '冲突示例：${preview.items.where((e) => e.action == ImportAction.conflict).take(4).map((e) => e.note.title).join('、')}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: _busy || preview == null ? null : _commit,
          icon: const Icon(Icons.check),
          label: const Text('确认导入'),
        ),
      ],
    );
  }

  Widget _count(ImportPreview preview, ImportAction action, String label) =>
      Chip(label: Text('$label ${preview.count(action)}'));
}
