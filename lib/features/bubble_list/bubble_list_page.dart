import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/bubble.dart';
import '../../repositories/bubble_repository.dart';
import '../../services/startup_service.dart';
import '../../services/import_service.dart';
import '../../services/sync_service.dart';
import '../../viewmodels/bubble_view_models.dart';
import '../../widgets/bubble_detail_dialog.dart';
import '../../widgets/markdown_block_editor.dart';

class BubbleListPage extends ConsumerStatefulWidget {
  const BubbleListPage({super.key});

  @override
  ConsumerState<BubbleListPage> createState() => _BubbleListPageState();
}

class _BubbleListPageState extends ConsumerState<BubbleListPage> {
  String _query = '';

  void _refresh() => ref.read(bubbleRevisionProvider.notifier).state++;

  @override
  Widget build(BuildContext context) {
    final bubbles = ref.watch(bubblesProvider(_query));
    return Scaffold(
      backgroundColor: const Color(0xFF061620),
      appBar: AppBar(
        title: const Text('浮念'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: '导入文件',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importFile,
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF061620), Color(0xFF0B2834)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
              child: SearchBar(
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor:
                    const WidgetStatePropertyAll(Color(0xFF123442)),
                side: WidgetStatePropertyAll(
                  BorderSide(color: Colors.white.withValues(alpha: .1)),
                ),
                leading: const Icon(Icons.search),
                hintText: '搜索标题或详细描述',
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: bubbles.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('无法读取泡泡：$error')),
                data: (items) => items.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => _BubbleTile(
                          bubble: items[index],
                          colorIndex: index,
                          onOpen: () => _openDetail(items[index]),
                          onEdit: () =>
                              _openEditor(context, bubble: items[index]),
                          onDelete: () => _delete(items[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('新建概念'),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {Bubble? bubble}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BubbleEditorDialog(bubble: bubble),
    );
    if (saved == true) _refresh();
  }

  Future<void> _delete(Bubble bubble) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个泡泡？'),
        content: Text('“${bubble.title}”将从本地数据中移除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(bubbleRepositoryProvider).delete(bubble.id);
      _refresh();
    }
  }

  Future<void> _openSettings() => showDialog<void>(
        context: context,
        builder: (_) => const _SettingsDialog(),
      );

  Future<void> _importFile() async {
    // The full mapping pipeline is intentionally independent of the view;
    // this compact first-run flow recognizes title/description headers.
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'xlsx']);
    if (result == null || result.files.single.path == null) return;
    final rows =
        await ImportService().readTable(File(result.files.single.path!));
    var imported = 0;
    final existing = (await ref.read(bubbleRepositoryProvider).getAll())
        .map((b) => b.title.toLowerCase())
        .toSet();
    for (final row in rows) {
      final title = row.values['title'] ?? row.values['标题'] ?? '';
      final description = row.values['description'] ??
          row.values['正文'] ??
          row.values['描述'] ??
          '';
      if (title.trim().isEmpty ||
          description.trim().isEmpty ||
          !existing.add(title.trim().toLowerCase())) {
        continue;
      }
      await ref.read(bubbleRepositoryProvider).save(Bubble(
          id: '${DateTime.now().microsecondsSinceEpoch}-$imported',
          title: title.trim(),
          description: description.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      imported++;
    }
    _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导入 $imported 个泡泡')));
    }
  }

  Future<void> _openDetail(Bubble bubble) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => BubbleDetailDialog(
        bubble: bubble,
        onFrequencyChanged: (frequency) => ref
            .read(bubbleRepositoryProvider)
            .updateFrequency(bubble.id, frequency),
        onEdit: () => _openEditor(context, bubble: bubble),
        onDelete: () => ref.read(bubbleRepositoryProvider).delete(bubble.id),
      ),
    );
    if (changed == true) _refresh();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bubble_chart_outlined, size: 56),
            const SizedBox(height: 16),
            Text('让一个重要想法先沉入海底', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('写下标题和详细描述，让它在未来重新浮现。'),
          ]),
        ),
      );
}

class _SettingsDialog extends ConsumerStatefulWidget {
  const _SettingsDialog();

  @override
  ConsumerState<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<_SettingsDialog> {
  bool? _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(startupServiceProvider).isEnabled().then((enabled) {
      if (mounted) setState(() => _enabled = enabled);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('设置'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('云端同步（WebDAV）'),
              subtitle: const Text('坚果云、Nextcloud 等；设置账号、应用密码和加密口令。'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                  context: context, builder: (_) => const _SyncDialog()),
            ),
            const Divider(),
            if (!ref.read(startupServiceProvider).isSupported)
              const Text('当前平台不支持登录后自动运行。Android 会在下次打开应用时恢复本地状态与同步。')
            else if (_enabled == null)
              const Center(child: CircularProgressIndicator())
            else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开机后自动运行'),
                subtitle: const Text('登录 Windows 后自动打开浮念。'),
                value: _enabled!,
                onChanged: _saving ? null : _setStartupEnabled,
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );

  Future<void> _setStartupEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(startupServiceProvider).setEnabled(enabled);
      if (mounted) setState(() => _enabled = enabled);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SyncDialog extends ConsumerStatefulWidget {
  const _SyncDialog();
  @override
  ConsumerState<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends ConsumerState<_SyncDialog> {
  final _server =
      TextEditingController(text: 'https://dav.jianguoyun.com/dav/');
  final _username = TextEditingController();
  final _appPassword = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ref.read(syncServiceProvider).loadConfig().then((config) {
      if (!mounted) return;
      if (config != null) {
        _server.text = config.serverUrl;
        _username.text = config.username;
        _appPassword.text = config.appPassword;
      }
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _appPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('云端同步（WebDAV）'),
        content: SizedBox(
            width: 480,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        '以坚果云为例：登录官网 → 账户信息 → 安全选项 → 添加应用密码；不要填写登录密码。保存后，下次打开应用会自动读取这些设置。'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _server,
                        decoration:
                            const InputDecoration(labelText: 'WebDAV 服务器地址')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _username,
                        decoration:
                            const InputDecoration(labelText: '账号（通常是邮箱）')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: _appPassword,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: '应用密码 / API Key')),
                  ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存并启用'))
        ],
      );
  Future<void> _save() async {
    if ([_server.text, _username.text, _appPassword.text]
        .any((text) => text.trim().isEmpty)) {
      return;
    }
    setState(() => _saving = true);
    await ref.read(syncServiceProvider).configureWebDav(
        serverUrl: _server.text,
        username: _username.text,
        appPassword: _appPassword.text);
    if (mounted) Navigator.pop(context);
  }
}

class _BubbleTile extends StatelessWidget {
  const _BubbleTile({
    required this.bubble,
    required this.colorIndex,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });
  final Bubble bubble;
  final int colorIndex;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _accents = [
    Color(0xFF57D6C8),
    Color(0xFF8494FF),
    Color(0xFFE985C8),
    Color(0xFFFFC56E),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = _accents[colorIndex % _accents.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: .2), const Color(0xFF102A36)],
        ),
        border: Border.all(color: accent.withValues(alpha: .28)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
          onTap: onOpen,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .2),
              border: Border.all(color: accent.withValues(alpha: .62)),
            ),
            child: Icon(
              Icons.bubble_chart_outlined,
              color: accent,
            ),
          ),
          title: Text(
            bubble.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(bubble.description,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
              tooltip: '编辑',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined)),
        ),
      ),
    );
  }
}

class BubbleEditorDialog extends ConsumerStatefulWidget {
  const BubbleEditorDialog({this.bubble, super.key});
  final Bubble? bubble;

  @override
  ConsumerState<BubbleEditorDialog> createState() => _BubbleEditorState();
}

class _BubbleEditorState extends ConsumerState<BubbleEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  bool _saving = false;
  String? _descriptionError;

  @override
  void initState() {
    super.initState();
    final bubble = widget.bubble;
    _title = TextEditingController(text: bubble?.title);
    _description = TextEditingController(text: bubble?.description);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: SizedBox(
        width: min(screen.width - 36, 1080),
        height: min(screen.height - 36, 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF071A25),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 46,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(26, 20, 18, 18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF244DA9), Color(0xFF7648A9)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.bubble == null ? '创建概念泡泡' : '编辑概念泡泡',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF123846),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF66D8CD).withValues(alpha: .32),
                        ),
                      ),
                      child: TextFormField(
                        controller: _title,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: '标题',
                          prefixIcon: Icon(Icons.title),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        validator: _required,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                      child: MarkdownBlockEditor(
                        controller: _description,
                        errorText: _descriptionError,
                        onChanged: (_) {
                          if (_descriptionError != null) {
                            setState(() => _descriptionError = null);
                          }
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                    color: const Color(0xFF0B2733),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.check),
                          label: Text(_saving ? '保存中…' : '保存泡泡'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项为必填项' : null;

  Future<void> _save() async {
    final titleIsValid = _formKey.currentState!.validate();
    final descriptionIsValid = _description.text.trim().isNotEmpty;
    if (!descriptionIsValid) {
      setState(() => _descriptionError = '请至少填写一个正文内容块');
    }
    if (!titleIsValid || !descriptionIsValid) return;
    setState(() => _saving = true);
    final existing = widget.bubble;
    final bubble = Bubble(
      id: existing?.id ??
          '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
      title: _title.text.trim(),
      description: _description.text.trim(),
      createdAt: existing?.createdAt ?? DateTime.now(),
      lastShownAt: existing?.lastShownAt,
      shownCount: existing?.shownCount ?? 0,
      updatedAt: DateTime.now(),
      appearanceFrequency: existing?.appearanceFrequency ?? 3,
    );
    await ref.read(bubbleRepositoryProvider).save(bubble);
    if (mounted) Navigator.pop(context, true);
  }
}
