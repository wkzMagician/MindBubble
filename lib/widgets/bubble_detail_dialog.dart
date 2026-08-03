import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/bubble.dart';

class BubbleDetailDialog extends StatefulWidget {
  const BubbleDetailDialog({
    required this.bubble,
    required this.onFrequencyChanged,
    this.onEdit,
    this.onDelete,
    super.key,
  });
  final Bubble bubble;
  final Future<void> Function(int frequency) onFrequencyChanged;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  @override
  State<BubbleDetailDialog> createState() => _BubbleDetailDialogState();
}

class _BubbleDetailDialogState extends State<BubbleDetailDialog> {
  late double _frequency = widget.bubble.appearanceFrequency.toDouble();
  bool _saving = false;
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF071B27),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(28, 20, 16, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF3158B8), Color(0xFF8B4EC4)],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.bubble.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.close,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
                  color: const Color(0xFF103949),
                  child: SingleChildScrollView(
                    child: MarkdownBody(
                      data: widget.bubble.description,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                          color: Color(0xFFE1F4F4),
                          height: 1.72,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
                color: const Color(0xFF0A2633),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, size: 18),
                        const SizedBox(width: 8),
                        Text(context.l10n.frequency),
                        const Spacer(),
                        Text(_frequencyLabel(context.l10n, _frequency.round())),
                      ],
                    ),
                    Slider(
                      value: _frequency,
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: _frequencyLabel(context.l10n, _frequency.round()),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _frequency = value),
                      onChangeEnd: _saveFrequency,
                    ),
                    Row(
                      children: [
                        if (widget.onDelete != null)
                          TextButton.icon(
                            onPressed: _saving ? null : _delete,
                            icon: const Icon(Icons.delete_outline),
                            label: Text(context.l10n.delete),
                          ),
                        const Spacer(),
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
  Future<void> _saveFrequency(double value) async {
    setState(() => _saving = true);
    try {
      await widget.onFrequencyChanged(value.round());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.confirmDeleteTitle),
        content: Text(context.l10n.confirmDeleteBody(widget.bubble.title)),
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
      if (mounted) Navigator.pop(context, true);
    }
  }

  String _frequencyLabel(AppLocalizations l10n, int frequency) =>
      switch (frequency) {
        1 => l10n.frequency1,
        2 => l10n.frequency2,
        3 => l10n.frequency3,
        4 => l10n.frequency4,
        _ => l10n.frequency5,
      };
}
