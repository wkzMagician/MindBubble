import 'dart:async';

import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ModelAccountLogin extends StatefulWidget {
  const ModelAccountLogin({
    super.key,
    required this.provider,
    required this.auth,
  });
  final ModelAccountProvider provider;
  final ModelAccountAuth auth;
  @override
  State<ModelAccountLogin> createState() => _ModelAccountLoginState();
}

class _ModelAccountLoginState extends State<ModelAccountLogin> {
  final _code = TextEditingController();
  ChatGptDeviceGrant? _device;
  OpenRouterGrant? _router;
  Timer? _timer;
  bool _busy = true;
  String? _error;
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    _timer?.cancel();
    try {
      if (widget.provider == ModelAccountProvider.chatgpt) {
        final device = await widget.auth.beginChatGpt();
        if (!mounted) return;
        setState(() {
          _device = device;
          _busy = false;
          _error = null;
        });
        _schedulePoll();
      } else {
        final router = widget.auth.beginOpenRouter();
        if (mounted) {
          setState(() {
            _router = router;
            _busy = false;
            _error = null;
          });
        }
      }
    } on Object {
      _failed();
    }
  }

  void _schedulePoll() {
    _timer = Timer(_device!.interval, _poll);
  }

  Future<void> _poll() async {
    try {
      final session = await widget.auth.pollChatGpt(_device!);
      if (!mounted) return;
      if (session != null) {
        Navigator.pop(context, session);
      } else {
        _schedulePoll();
      }
    } on Object {
      _failed();
    }
  }

  Future<void> _open() async {
    final uri = _device?.verificationUrl ?? _router?.authorizationUrl;
    if (uri == null) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _failed();
      }
    } on Object {
      _failed();
    }
  }

  Future<void> _finish() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.auth.finishOpenRouter(_router!, _code.text);
      _code.clear();
      if (mounted) Navigator.pop(context, session);
    } on Object {
      _failed();
    }
  }

  void _failed() {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = t(
          '授权未完成。请检查网络、账号权限或重新发起登录。',
          'Sign-in did not complete. Check your connection and account access, or start again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.provider == ModelAccountProvider.chatgpt
          ? 'ChatGPT'
          : 'OpenRouter',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_device != null) ...[
              Text(
                t(
                  '打开授权页面，输入以下代码，完成后回到应用。',
                  'Open the sign-in page, enter this code, then return to the app.',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _device!.userCode,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: t('复制代码', 'Copy code'),
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: _device!.userCode),
                    ),
                  ),
                ],
              ),
              Text(
                t(
                  '首次使用需在 ChatGPT 安全设置中启用 Codex 设备授权。',
                  'Enable Codex device authorization in ChatGPT security settings before the first sign-in.',
                ),
              ),
            ],
            if (_router != null) ...[
              Text(
                t(
                  '打开 OpenRouter 授权页面。授权后复制页面给出的授权码，回到这里粘贴。',
                  'Open OpenRouter and approve access. Copy the authorization code from the page and paste it here.',
                ),
              ),
              TextField(
                controller: _code,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: t('授权码', 'Authorization code'),
                ),
              ),
            ],
            if (_device != null || _router != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton(
                  onPressed: _busy ? null : _open,
                  child: Text(t('打开授权页面', 'Open authorization page')),
                ),
              ),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  _begin();
                },
                child: Text(t('重新发起登录', 'Restart sign-in')),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      if (_router != null)
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: Text(t('完成登录', 'Finish sign-in')),
        ),
    ],
  );
}
