import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../features/model_settings/model_settings_panel.dart';
import '../features/recommendations/note_profile.dart';
import '../l10n/l10n.dart';
import '../models/bubble.dart';
import '../services/bubble_document_store.dart';
import 'markdown_content.dart';

class BubbleDetailDialog extends StatefulWidget {
  const BubbleDetailDialog({
    required this.bubble,
    required this.onFrequencyChanged,
    this.documentStore,
    this.onEdit,
    this.onDelete,
    this.onFeedback,
    this.onProfile,
    this.onReanalyze,
    this.onReadingComplete,
    super.key,
  });
  final Bubble bubble;
  final BubbleDocumentStore? documentStore;
  final Future<void> Function(int frequency) onFrequencyChanged;
  final Future<Bubble?> Function(FrequencyFeedback feedback)? onFeedback;
  final Future<Bubble?> Function(Bubble current)? onProfile;
  final Future<Bubble?> Function()? onReanalyze;
  final void Function(double seconds)? onReadingComplete;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  @override
  State<BubbleDetailDialog> createState() => _BubbleDetailDialogState();
}

class _BubbleDetailDialogState extends State<BubbleDetailDialog>
    with WidgetsBindingObserver {
  final Stopwatch _reading = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reading.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reading.start();
    } else {
      _reading.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reading.stop();
    widget.onReadingComplete?.call(_reading.elapsedMilliseconds / 1000);
    super.dispose();
  }

  late Bubble _bubble = widget.bubble;
  bool _saving = false;
  String? _message;

  Future<void> _feedback(FrequencyFeedback value) async {
    setState(() => _saving = true);
    try {
      final updated = await widget.onFeedback!(value);
      if (!mounted) return;
      if (updated != null) _bubble = updated;
      if (value == FrequencyFeedback.stop) {
        Navigator.pop(context);
        return;
      }
      setState(
        () => _message = modelLabel(context, '反馈已记录', 'Feedback recorded'),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _message = modelLabel(
            context,
            '反馈保存失败',
            'Could not save feedback',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _update(Future<Bubble?> Function() action) async {
    setState(() => _saving = true);
    try {
      final value = await action();
      if (value != null && mounted) {
        setState(() {
          _bubble = value;
          _message =
              '${modelLabel(context, '分析状态', 'Analysis status')}: ${value.effectiveProfile.analysisStatus}';
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = modelLabel(
            context,
            '操作失败，笔记已保留',
            'Operation failed; your note is preserved',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.confirmDeleteTitle),
        content: Text(context.l10n.confirmDeleteBody(_bubble.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _bubble.cueTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.close,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (_bubble.showSummary)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(_bubble.effectiveProfile.summary),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: MarkdownContent(
                data: _bubble.description,
                store: widget.documentStore,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(height: 1.72),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.onFeedback != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final feedback in FrequencyFeedback.values)
                        OutlinedButton(
                          onPressed: _saving ? null : () => _feedback(feedback),
                          child: Text(switch (feedback) {
                            FrequencyFeedback.more => modelLabel(
                              context,
                              '多提醒',
                              'More often',
                            ),
                            FrequencyFeedback.suitable => modelLabel(
                              context,
                              '频率合适',
                              'About right',
                            ),
                            FrequencyFeedback.less => modelLabel(
                              context,
                              '少提醒',
                              'Less often',
                            ),
                            FrequencyFeedback.stop => modelLabel(
                              context,
                              '停止提醒',
                              'Stop reminding',
                            ),
                          }),
                        ),
                    ],
                  ),
                if (widget.onFeedback == null)
                  Slider(
                    value: _bubble.appearanceFrequency.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    onChanged: (v) async {
                      await widget.onFrequencyChanged(v.round());
                      if (mounted) {
                        setState(
                          () => _bubble = _bubble.copyWith(
                            appearanceFrequency: v.round(),
                          ),
                        );
                      }
                    },
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message!),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (widget.onProfile != null)
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _update(() => widget.onProfile!(_bubble)),
                        icon: const Icon(Icons.tune),
                        label: Text(modelLabel(context, '推荐属性', 'Profile')),
                      ),
                    if (widget.onReanalyze != null)
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _update(widget.onReanalyze!),
                        icon: const Icon(Icons.psychology_outlined),
                        label: Text(modelLabel(context, '重新分析', 'Reanalyze')),
                      ),
                    if (widget.onEdit != null)
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () {
                                Navigator.pop(context);
                                widget.onEdit!();
                              },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(context.l10n.edit),
                      ),
                    if (widget.onDelete != null)
                      TextButton.icon(
                        onPressed: _saving ? null : _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(context.l10n.delete),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
