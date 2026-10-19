import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../viewmodels/bubble_view_models.dart';
import '../model_settings/model_settings_panel.dart';
import 'pending_note_analysis.dart';

class AnalyzePendingNotesButton extends ConsumerWidget {
  const AnalyzePendingNotesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(pendingNoteAnalysisProvider);
    final notes = ref.watch(bubblesProvider(''));
    final count = notes.valueOrNull?.where(noteNeedsAnalysis).length ?? 0;
    final running = progress.isRunning;
    final label = running
        ? progress.total == 0
              ? modelLabel(context, '准备分析…', 'Preparing…')
              : modelLabel(
                  context,
                  '分析中 ${progress.processed}/${progress.total}',
                  'Analyzing ${progress.processed}/${progress.total}',
                )
        : modelLabel(context, 'AI 分析 ($count)', 'AI analysis ($count)');
    final tooltip = running
        ? label
        : modelLabel(
            context,
            count == 0 && notes.hasValue
                ? '所有笔记均已分析'
                : '一键分析所有未分析的笔记（$count 条）',
            count == 0 && notes.hasValue
                ? 'All notes have been analyzed'
                : 'Analyze all pending notes ($count)',
          );
    final VoidCallback? onPressed =
        running || notes.isLoading || (notes.hasValue && count == 0)
        ? null
        : () => _analyze(context, ref);
    final icon = running
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.total == 0 || progress.processed == 0
                  ? null
                  : progress.processed / progress.total,
            ),
          )
        : const Icon(Icons.auto_awesome_outlined);

    if (MediaQuery.sizeOf(context).width < 600) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: running || count == 0
            ? icon
            : Badge(label: Text('$count'), child: icon),
      );
    }
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      ),
    );
  }

  Future<void> _analyze(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(pendingNoteAnalysisProvider.notifier)
        .analyzePending();
    if (!context.mounted || result.isRunning) return;
    final summary = modelLabel(
      context,
      '已分析 ${result.analyzed} 条，失败 ${result.failed} 条，'
          '跳过 ${result.skipped} 条，未处理 ${result.total - result.processed} 条。',
      'Analyzed ${result.analyzed}, failed ${result.failed}, '
          'skipped ${result.skipped}, remaining ${result.total - result.processed}.',
    );
    if (result.issue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.total == 0
                ? modelLabel(
                    context,
                    '所有笔记均已分析',
                    'All notes have been analyzed',
                  )
                : summary,
          ),
        ),
      );
      return;
    }

    final message = switch (result.issue!) {
      PendingAnalysisIssue.unconfigured => modelLabel(
        context,
        '尚未配置分析模型，请先在模型设置中选择并配置模型。',
        'No analysis model is configured. Choose and configure one in Models.',
      ),
      PendingAnalysisIssue.invalidConfiguration => modelLabel(
        context,
        '模型配置无法使用，请检查服务地址和模型名称。',
        'The model configuration is invalid. Check the service URL and model name.',
      ),
      PendingAnalysisIssue.modelFailed => modelLabel(
        context,
        '模型分析失败，已停止后续批次。请检查模型名称、API 凭据、'
            '服务连接或订阅登录状态后重试。已完成的分析已保存。',
        'Model analysis failed; later batches were stopped. Check the model name, '
            'API credentials, service connection or subscription sign-in, then retry. '
            'Completed analyses have been saved.',
      ),
      PendingAnalysisIssue.storageFailed => modelLabel(
        context,
        '无法读取或保存笔记，请检查文档目录是否可用后重试。',
        'Notes could not be read or saved. Check the document directory and retry.',
      ),
    };
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(modelLabel(context, '批量 AI 分析', 'Bulk AI analysis')),
        content: Text('$message\n\n$summary'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(modelLabel(context, '关闭', 'Close')),
          ),
          if (result.issue != PendingAnalysisIssue.storageFailed)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(modelLabel(context, '模型设置', 'Models')),
            ),
        ],
      ),
    );
    if (openSettings == true && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => const ModelSettingsDialog(),
      );
    }
  }
}
