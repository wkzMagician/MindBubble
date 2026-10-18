import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/bubble_repository.dart';
import '../model_settings/model_settings_panel.dart';
import 'recommendation_config.dart';
import 'recommendation_metrics.dart';

class RecommendationSettingsPanel extends ConsumerWidget {
  const RecommendationSettingsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.auto_awesome_outlined),
    title: Text(modelLabel(context, '自适应推荐', 'Adaptive recommendations')),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) => const _ConfigDialog(),
    ),
  );
}

class _ConfigDialog extends ConsumerStatefulWidget {
  const _ConfigDialog();
  @override
  ConsumerState<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends ConsumerState<_ConfigDialog> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _values;
  bool _saving = false;
  String? _error;
  late final Future<RecommendationMetrics> _metrics;
  @override
  void initState() {
    super.initState();
    final config = ref.read(recommendationConfigProvider);
    _values = [
      config.temperature,
      config.explorationRate,
      config.diversityWeight,
      config.feedbackStep,
      config.generalizationWeight,
      config.notificationCount,
    ].map((v) => TextEditingController(text: '$v')).toList();
    _metrics = _loadMetrics();
  }

  Future<RecommendationMetrics> _loadMetrics() async {
    final repo = ref.read(bubbleRepositoryProvider);
    return RecommendationMetrics(await repo.getAll(), await repo.events.read());
  }

  @override
  void dispose() {
    for (final c in _values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final n = _values.map((c) => double.parse(c.text)).toList();
      await ref
          .read(recommendationConfigProvider.notifier)
          .update(
            RecommendationConfig(
              temperature: n[0],
              explorationRate: n[1],
              diversityWeight: n[2],
              feedbackStep: n[3],
              generalizationWeight: n[4],
              notificationCount: n[5].toInt(),
              bubbleCount: ref.read(recommendationConfigProvider).bubbleCount,
            ),
          );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = modelLabel(context, '保存失败', 'Save failed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      modelLabel(context, '采样温度', 'Temperature'),
      modelLabel(context, '探索比例', 'Exploration rate'),
      modelLabel(context, '多样性强度', 'Diversity weight'),
      modelLabel(context, '反馈步长', 'Feedback step'),
      modelLabel(context, '偏好泛化强度', 'Generalization weight'),
      modelLabel(context, '每次通知笔记数', 'Notes per notification batch'),
    ];
    const minima = [.01, 0.0, 0.0, 0.0, 0.0, 1.0];
    const maxima = [10.0, 1.0, 10.0, .6, 1.0, 10.0];
    return AlertDialog(
      title: Text(modelLabel(context, '自适应推荐', 'Adaptive recommendations')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _values.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: _values[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: labels[i]),
                      validator: (text) {
                        final n = double.tryParse(text ?? '');
                        return n == null ||
                                !n.isFinite ||
                                n < minima[i] ||
                                n > maxima[i] ||
                                (i == 5 && n != n.roundToDouble())
                            ? '${minima[i]}–${maxima[i]}'
                            : null;
                      },
                    ),
                  ),
                FutureBuilder<RecommendationMetrics>(
                  future: _metrics,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text(
                        modelLabel(context, '统计读取失败', 'Could not load metrics'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    final m = snapshot.data!;
                    return ExpansionTile(
                      title: Text(modelLabel(context, '效果统计', 'Metrics')),
                      children: [_metricsView(context, m)],
                    );
                  },
                ),
                if (_error != null) Text(_error!),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(modelLabel(context, '取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(modelLabel(context, '保存', 'Save')),
        ),
      ],
    );
  }

  Widget _metricsView(BuildContext context, RecommendationMetrics m) {
    Widget row(String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          Text(value),
        ],
      ),
    );
    String label(String zh, String en) => modelLabel(context, zh, en);
    String feedback(Map<String, int> counts) =>
        '${label('多', 'More')} ${counts['more'] ?? 0} · '
        '${label('合适', 'Right')} ${counts['suitable'] ?? 0} · '
        '${label('少', 'Less')} ${counts['less'] ?? 0} · '
        '${label('停', 'Stop')} ${counts['stop'] ?? 0}';
    final distribution = m.exposures.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalFeedback = m.feedback.values.fold<int>(0, (a, b) => a + b);
    final positive = totalFeedback == 0
        ? 0
        : 100 * (m.feedback['more'] ?? 0) / totalFeedback;
    final negative = totalFeedback == 0
        ? 0
        : 100 *
              ((m.feedback['less'] ?? 0) + (m.feedback['stop'] ?? 0)) /
              totalFeedback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          label('笔记覆盖率', 'Note coverage'),
          '${(100 * m.coverage).toStringAsFixed(1)}%',
        ),
        row(
          label('正向 / 负向反馈', 'Positive / negative feedback'),
          '${positive.toStringAsFixed(0)}% / ${negative.toStringAsFixed(0)}%',
        ),
        Text('${label('全部反馈', 'All feedback')}: ${feedback(m.feedback)}'),
        const SizedBox(height: 8),
        Text(
          '${label('通知反馈', 'Notification feedback')}: ${feedback(m.notificationFeedback)}',
        ),
        row(label('正文打开次数', 'Body opens'), '${m.opens}'),
        row(
          label('阅读时间（分钟）', 'Reading time (minutes)'),
          (m.readingSeconds / 60).toStringAsFixed(1),
        ),
        row(label('搜索访问', 'Search visits'), '${m.searches}'),
        row(
          label('批次内平均相似度', 'Mean batch similarity'),
          m.meanSimilarity?.toStringAsFixed(3) ?? '—',
        ),
        const Divider(),
        Text(label('重复曝光间隔', 'Repeat exposure intervals')),
        for (final bucket in [
          (0.0, 1.0, '< 1 h'),
          (1.0, 24.0, '1–24 h'),
          (24.0, 168.0, '1–7 d'),
          (168.0, double.infinity, '≥ 7 d'),
        ])
          row(
            bucket.$3,
            '${m.intervalsHours.where((h) => h >= bucket.$1 && h < bucket.$2).length}',
          ),
        const Divider(),
        Text(label('笔记曝光分布', 'Note exposure distribution')),
        for (final entry in distribution)
          row(m.titles[entry.key] ?? entry.key, '${entry.value}'),
      ],
    );
  }
}
