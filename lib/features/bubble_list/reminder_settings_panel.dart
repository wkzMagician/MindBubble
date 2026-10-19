import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/reminder_settings.dart';
import '../../services/reminder_runtime.dart';

/// Settings are device-local and do not affect the home selection.
class ReminderSettingsPanel extends ConsumerWidget {
  const ReminderSettingsPanel({super.key});

  String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    ReminderSettings settings,
    bool start,
  ) async {
    final minutes = start ? settings.quietStartMinute : settings.quietEndMinute;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (value == null) return;
    final chosen = value.hour * 60 + value.minute;
    await ref
        .read(reminderSettingsProvider.notifier)
        .update(
          start
              ? settings.copyWith(quietStartMinute: chosen)
              : settings.copyWith(quietEndMinute: chosen),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reminderSettingsProvider);
    final controller = ref.read(reminderSettingsProvider.notifier);
    final index = ReminderIntervals.values
        .indexOf(settings.intervalMinutes)
        .clamp(0, ReminderIntervals.values.length - 1);
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text('自动浮现', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用周期性提醒'),
          value: settings.enabled,
          onChanged: (enabled) async {
            if (enabled && (Platform.isAndroid || Platform.isIOS)) {
              final granted = await ref
                  .read(reminderPlatformProvider)
                  .requestPermission();
              if (!granted) {
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('请在系统设置中允许浮念发送通知')),
                  );
                }
                return;
              }
            }
            await controller.update(settings.copyWith(enabled: enabled));
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('浮现间隔'),
            const Spacer(),
            Text(
              ReminderIntervals.label(settings.intervalMinutes),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        Builder(
          builder: (context) {
            double localIndex = index.toDouble();
            return StatefulBuilder(
              builder: (context, setLocal) => Slider(
                value: localIndex,
                min: 0,
                max: (ReminderIntervals.values.length - 1).toDouble(),
                divisions: ReminderIntervals.values.length - 1,
                label: ReminderIntervals.label(
                  ReminderIntervals.values[localIndex.round()],
                ),
                onChanged: (value) => setLocal(() => localIndex = value),
                onChangeEnd: (value) => controller.update(
                  settings.copyWith(
                    intervalMinutes: ReminderIntervals.values[value.round()],
                  ),
                ),
              ),
            );
          },
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('15 分钟', style: TextStyle(fontSize: 11)),
            Text('24 小时', style: TextStyle(fontSize: 11)),
          ],
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('免打扰时段'),
          value: settings.quietEnabled,
          onChanged: (v) =>
              controller.update(settings.copyWith(quietEnabled: v)),
        ),
        if (settings.quietEnabled)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bedtime_outlined, size: 18),
                  label: Text(_clock(settings.quietStartMinute)),
                  onPressed: () => _pickTime(context, ref, settings, true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('至'),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                  label: Text(_clock(settings.quietEndMinute)),
                  onPressed: () => _pickTime(context, ref, settings, false),
                ),
              ),
            ],
          ),
        if (desktop) ...[
          const SizedBox(height: 20),
          Text('桌面悬浮提醒', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 16),
          const Text('浮现位置'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: settings.overlayCorner,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'topRight', child: Text('右上角')),
              DropdownMenuItem(value: 'bottomRight', child: Text('右下角')),
              DropdownMenuItem(value: 'topLeft', child: Text('左上角')),
              DropdownMenuItem(value: 'bottomLeft', child: Text('左下角')),
            ],
            onChanged: (v) {
              if (v != null) {
                controller.update(settings.copyWith(overlayCorner: v));
              }
            },
          ),
          const SizedBox(height: 18),
          const Text('停留时间'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: settings.overlaySeconds,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 5, child: Text('5 秒')),
              DropdownMenuItem(value: 10, child: Text('10 秒')),
              DropdownMenuItem(value: 20, child: Text('20 秒')),
              DropdownMenuItem(value: 30, child: Text('30 秒')),
            ],
            onChanged: (v) {
              if (v != null) {
                controller.update(settings.copyWith(overlaySeconds: v));
              }
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref.read(reminderRuntimeProvider).previewDesktop(),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('预览当前主题浮现效果'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.keepInTray,
            title: const Text('关闭窗口后继续后台运行'),
            onChanged: (v) =>
                controller.update(settings.copyWith(keepInTray: v)),
          ),
        ],
      ],
    );
  }
}
