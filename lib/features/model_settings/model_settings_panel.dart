import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/bubble_repository.dart';
import '../recommendations/note_analyzer.dart';
import 'model_account_login.dart';
import 'model_settings.dart';

String modelLabel(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

class ModelSettingsPanel extends ConsumerWidget {
  const ModelSettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.psychology_outlined),
    title: Text(modelLabel(context, '模型设置', 'Models')),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) => const ModelSettingsDialog(),
    ),
  );
}

class ModelSettingsDialog extends ConsumerStatefulWidget {
  const ModelSettingsDialog({super.key});
  @override
  ConsumerState<ModelSettingsDialog> createState() =>
      _ModelSettingsDialogState();
}

class _ConnectionDraft {
  final endpoint = TextEditingController();
  final model = TextEditingController();
  final executable = TextEditingController();
  final credential = TextEditingController();
  final connections = <ModelAccess, ModelConnection>{};
  ModelAccess access = ModelAccess.api;
  bool hasKey = false, clearKey = false;
  ModelConnection get connection => ModelConnection(
    access: access,
    model: model.text.trim(),
    endpoint: endpoint.text.trim(),
    executable: executable.text.trim().isEmpty
        ? 'codex'
        : executable.text.trim(),
  );
  void restore(ModelAccess next) {
    access = next;
    final saved =
        connections[next] ??
        ModelConnection(
          access: next,
          model: '',
          endpoint: next == ModelAccess.local ? 'http://127.0.0.1:11434' : '',
        );
    endpoint.text = saved.endpoint;
    model.text = saved.model;
    executable.text = saved.executable;
  }

  void switchTo(ModelAccess next) {
    connections[access] = connection;
    restore(next);
  }

  void dispose() {
    for (final c in [endpoint, model, executable, credential]) {
      c.dispose();
    }
  }
}

class _ModelSettingsDialogState extends ConsumerState<ModelSettingsDialog> {
  final _form = GlobalKey<FormState>();
  final _text = _ConnectionDraft(), _vectors = _ConnectionDraft();
  ModelAccountProvider? _account = ModelAccountProvider.chatgpt;
  final _signedIn = <ModelAccountProvider, bool>{};
  bool _loading = true, _saving = false, _embeddingBusy = false;
  String? _error, _progress;
  bool get _desktop => const {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);
  String t(String zh, String en) => modelLabel(context, zh, en);
  ModelSettingsRepository get _repository =>
      ref.read(modelSettingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _repository.load();
      for (final pair in [(_text, false), (_vectors, true)]) {
        final draft = pair.$1;
        for (final access in ModelAccess.values) {
          draft.connections[access] = value.connectionFor(
            access,
            forEmbedding: pair.$2,
          );
        }
        final selected = pair.$2 ? value.embedding : value.generation;
        draft.restore(
          !_desktop && selected.access == ModelAccess.local
              ? ModelAccess.api
              : selected.access,
        );
        draft.hasKey = await _repository.hasCredential(
          connection: draft.connections[ModelAccess.api],
          forEmbedding: pair.$2,
        );
      }
      _account =
          value.generationAccount ??
          (_desktop && value.generation.access == ModelAccess.subscription
              ? null
              : ModelAccountProvider.chatgpt);
      for (final p in ModelAccountProvider.values) {
        _signedIn[p] = await _repository.hasAccount(p);
      }
      if (mounted) setState(() => _loading = false);
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = t('读取模型设置失败', 'Could not load model settings');
        });
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _vectors.dispose();
    super.dispose();
  }

  Future<bool> _save({bool close = true}) async {
    if (!_form.currentState!.validate()) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _text.connections[_text.access] = _text.connection;
      _vectors.connections[_vectors.access] = _vectors.connection;
      await _repository.save(
        ModelSettings(
          generation: _text.connection,
          connections: Map.of(_text.connections),
          generationAccount: _account,
          embedding: _vectors.connection,
          embeddingConnections: Map.of(_vectors.connections),
        ),
        credential: _text.credential.text,
        clearCredential: _text.clearKey,
        embeddingCredential: _vectors.credential.text,
        clearEmbeddingCredential: _vectors.clearKey,
      );
      _text.credential.clear();
      _vectors.credential.clear();
      _text.clearKey = false;
      _vectors.clearKey = false;
      _text.hasKey = await _repository.hasCredential(
        connection: _text.connections[ModelAccess.api],
      );
      _vectors.hasKey = await _repository.hasCredential(
        connection: _vectors.connections[ModelAccess.api],
        forEmbedding: true,
      );
      if (mounted && close) Navigator.pop(context);
      return true;
    } on Object {
      if (mounted) {
        setState(
          () => _error = t(
            '保存失败，请检查安全存储是否可用',
            'Save failed. Check secure storage.',
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _login(ModelAccountProvider provider) async {
    final session = await showDialog<AccountSession>(
      context: context,
      builder: (_) =>
          ModelAccountLogin(provider: provider, auth: _repository.accountAuth),
    );
    if (session == null) return;
    try {
      await _repository.saveAccount(provider, session);
      if (mounted) setState(() => _signedIn[provider] = true);
    } on Object {
      if (mounted) {
        setState(
          () => _error = t('登录信息保存失败', 'Could not securely save sign-in'),
        );
      }
    }
  }

  Future<void> _fillVectors() async {
    if (!await _save(close: false) || !mounted) return;
    setState(() {
      _embeddingBusy = true;
      _error = null;
      _progress = null;
    });
    try {
      final embedder = await _repository.embedding(await _repository.load());
      if (embedder == null) {
        throw const ModelException('Embedding model is not configured');
      }
      final notes = (await ref.read(bubbleRepositoryProvider).getAll())
          .where(
            (n) =>
                !n.isDeleted &&
                (n.effectiveProfile.embedding.isEmpty ||
                    n.effectiveProfile.embeddingModel != embedder.identity),
          )
          .toList();
      var done = 0, failed = 0;
      for (var i = 0; i < notes.length; i += NoteAnalyzer.embeddingBatchSize) {
        if (!mounted) break;
        final batch = notes
            .skip(i)
            .take(NoteAnalyzer.embeddingBatchSize)
            .toList();
        final repository = ref.read(bubbleRepositoryProvider);
        await repository.analyzeNotes(batch, embeddingsOnly: true);
        for (final note in batch) {
          final saved = await repository.getById(note.id);
          if (saved != null &&
              saved.effectiveProfile.embedding.isNotEmpty &&
              saved.effectiveProfile.embeddingModel == embedder.identity) {
            done++;
          } else {
            failed++;
          }
        }
        if (mounted) {
          setState(
            () => _progress = t(
              '已生成 $done / ${notes.length} 篇',
              '$done / ${notes.length} completed',
            ),
          );
        }
      }
      if (mounted) {
        setState(
          () => _progress = failed == 0
              ? t('已补全 $done 篇笔记的向量', 'Completed embeddings for $done notes')
              : t(
                  '已完成 $done 篇，$failed 篇失败，可重试',
                  '$done completed, $failed failed. You can retry.',
                ),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = t(
            '向量生成失败，请检查模型服务和登录状态',
            'Embedding failed. Check the model service and sign-in.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _embeddingBusy = false);
    }
  }

  String? _url(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    return uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment
        ? null
        : t('请输入有效的 HTTP(S) 地址', 'Enter a valid HTTP(S) URL');
  }

  Widget _accountRow(ModelAccountProvider provider) => Row(
    children: [
      Expanded(
        child: Text(
          _signedIn[provider] == true
              ? t('已登录', 'Signed in')
              : t('未登录', 'Not signed in'),
        ),
      ),
      if (_signedIn[provider] == true)
        TextButton(
          onPressed: () async {
            await _repository.signOut(provider);
            if (mounted) setState(() => _signedIn[provider] = false);
          },
          child: Text(t('退出登录', 'Sign out')),
        ),
      OutlinedButton(
        onPressed: () => _login(provider),
        child: Text(
          _signedIn[provider] == true
              ? t('重新登录', 'Sign in again')
              : t('登录', 'Sign in'),
        ),
      ),
    ],
  );

  Widget _section(_ConnectionDraft draft, {required bool embedding}) {
    final prefix = embedding ? 'embedding' : 'generation';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          embedding ? t('向量模型', 'Embedding model') : t('文本模型', 'Text model'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ModelAccess>(
          key: ValueKey('$prefix-access'),
          initialValue: draft.access,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('连接方式', 'Connection')),
          items: [
            DropdownMenuItem(
              value: ModelAccess.api,
              child: Text(t('API（兼容 OpenAI）', 'API (OpenAI compatible)')),
            ),
            DropdownMenuItem(
              value: ModelAccess.subscription,
              child: Text(t('账号登录', 'Account sign-in')),
            ),
            if (_desktop)
              const DropdownMenuItem(
                value: ModelAccess.local,
                child: Text('Ollama'),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => draft.switchTo(v));
          },
        ),
        const SizedBox(height: 12),
        if (draft.access == ModelAccess.subscription) ...[
          if (embedding) ...[
            const Text('OpenRouter'),
            _accountRow(ModelAccountProvider.openRouter),
          ] else ...[
            DropdownButtonFormField<String>(
              key: ValueKey('account-${_account?.name ?? 'cli'}'),
              initialValue: _account?.name ?? 'cli',
              decoration: InputDecoration(
                labelText: t('账号服务', 'Account service'),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'chatgpt',
                  child: Text('ChatGPT'),
                ),
                const DropdownMenuItem(
                  value: 'openRouter',
                  child: Text('OpenRouter'),
                ),
                if (_desktop)
                  DropdownMenuItem(
                    value: 'cli',
                    child: Text(t('Codex CLI（桌面）', 'Codex CLI (desktop)')),
                  ),
              ],
              onChanged: (v) => setState(
                () => _account = ModelAccountProvider.values
                    .where((p) => p.name == v)
                    .firstOrNull,
              ),
            ),
            if (_account != null) _accountRow(_account!),
            if (_account == null)
              TextFormField(
                controller: draft.executable,
                decoration: const InputDecoration(
                  labelText: 'Codex CLI executable',
                ),
              ),
          ],
        ] else ...[
          TextFormField(
            key: ValueKey('$prefix-endpoint'),
            controller: draft.endpoint,
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (value) =>
                draft.model.text.trim().isEmpty &&
                    draft.credential.text.trim().isEmpty
                ? null
                : _url(value),
            decoration: InputDecoration(labelText: t('服务地址', 'Service URL')),
          ),
          if (draft.access == ModelAccess.api) ...[
            TextFormField(
              key: ValueKey('$prefix-key'),
              controller: draft.credential,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                helperText: draft.hasKey
                    ? t('已保存密钥，留空继续使用', 'Saved key is used when left blank')
                    : null,
              ),
            ),
            if (draft.hasKey)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('删除已保存的密钥', 'Delete saved API key')),
                value: draft.clearKey,
                onChanged: (v) => setState(() => draft.clearKey = v ?? false),
              ),
          ],
        ],
        TextFormField(
          key: ValueKey('$prefix-model'),
          controller: draft.model,
          onChanged: (_) => setState(() {}),
          autocorrect: false,
          decoration: InputDecoration(
            labelText: t('模型名', 'Model name'),
            helperText: embedding
                ? t('留空时停用向量生成', 'Leave blank to disable embeddings')
                : draft.access == ModelAccess.subscription && _account == null
                ? t(
                    '留空时使用 CLI 默认模型',
                    'Leave blank to use the CLI default model',
                  )
                : t('留空时停用文本分析', 'Leave blank to disable text analysis'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t('模型设置', 'Models')),
    content: SizedBox(
      width: 560,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: SingleChildScrollView(
                child: AbsorbPointer(
                  absorbing: _saving || _embeddingBusy,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section(_text, embedding: false),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(),
                      ),
                      _section(_vectors, embedding: true),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey('fill-note-embeddings'),
                        onPressed: _vectors.model.text.trim().isEmpty
                            ? null
                            : _fillVectors,
                        icon: const Icon(Icons.hub_outlined),
                        label: Text(
                          t('补全笔记向量', 'Fill missing note embeddings'),
                        ),
                      ),
                      if (_progress != null) Text(_progress!),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: _saving || _embeddingBusy
            ? null
            : () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(
        onPressed: _loading || _saving || _embeddingBusy ? null : _save,
        child: Text(t('保存', 'Save')),
      ),
    ],
  );
}
