import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bubble.dart';
import '../../services/scheduler_service.dart';
import '../../repositories/bubble_repository.dart';
import '../../viewmodels/bubble_view_models.dart';
import '../../widgets/bubble_detail_dialog.dart';
import '../bubble_list/bubble_list_page.dart';
import 'bubble_field.dart';
import 'ocean_background.dart';

class OceanPage extends ConsumerStatefulWidget {
  const OceanPage({super.key});

  @override
  ConsumerState<OceanPage> createState() => _OceanPageState();
}

class _OceanPageState extends ConsumerState<OceanPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  DateTime? _testDate;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _load() => ref.invalidate(todayBubblesProvider);

  Future<void> _pickTestDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _testDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: '选择用于调度测试的日期',
    );
    if (date == null) return;
    _testDate = DateTime(date.year, date.month, date.day, 12);
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _animation,
                builder: (_, __) => OceanBackground(progress: _animation.value),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('浮念', style: TextStyle(fontSize: 25)),
                              SizedBox(height: 4),
                              Text('今天，让几颗想法重新浮现。'),
                            ],
                          ),
                        ),
                        if (kDebugMode)
                          IconButton(
                            tooltip: '模拟日期',
                            onPressed: _pickTestDate,
                            icon: const Icon(Icons.bug_report_outlined),
                          ),
                        IconButton(
                          tooltip: '管理泡泡',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const BubbleListPage()),
                          ),
                          icon: const Icon(Icons.format_list_bulleted),
                        ),
                      ],
                    ),
                  ),
                  if (_testDate != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '测试日期：${SchedulerService.dateKey(_testDate!)}',
                        style: const TextStyle(color: Color(0xFF9AD6E7)),
                      ),
                    ),
                  Expanded(
                    child: ref.watch(todayBubblesProvider).when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) =>
                              Center(child: Text('无法生成今日浮现：$error')),
                          data: (bubbles) => bubbles.isEmpty
                              ? const Center(child: Text('先在“管理泡泡”里记录一个想法吧。'))
                              : BubbleField(
                                  bubbles: bubbles, onBubbleTap: _showBubble),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _showBubble(Bubble bubble) => showDialog<void>(
        context: context,
        builder: (context) => BubbleDetailDialog(
          bubble: bubble,
          onFrequencyChanged: (frequency) => ref
              .read(bubbleRepositoryProvider)
              .updateFrequency(bubble.id, frequency),
          onEdit: () => _editBubble(bubble),
          onDelete: () => ref.read(bubbleRepositoryProvider).delete(bubble.id),
        ),
      );

  Future<void> _editBubble(Bubble bubble) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => BubbleEditorDialog(bubble: bubble),
    );
    if (saved == true) {
      ref.read(bubbleRevisionProvider.notifier).state++;
    }
  }
}
