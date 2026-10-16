import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/home_bubble_count.dart';

/// Only changes the home page's weighted draw; reminder draws are independent.
class HomeBubbleCountSetting extends ConsumerWidget {
  const HomeBubbleCountSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(homeBubbleCountProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Text('主页展示', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('每次刷新数量'),
          subtitle: const Text('5–10 条；仅影响主页，自动浮现仍独立抽取'),
          trailing: DropdownButton<int>(
            key: const Key('homeBubbleCountDropdown'),
            value: count,
            items: [
              for (
                var value = HomeBubbleCount.minimum;
                value <= HomeBubbleCount.maximum;
                value++
              )
                DropdownMenuItem<int>(value: value, child: Text('$value 条')),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(homeBubbleCountProvider.notifier).setCount(value);
              }
            },
          ),
        ),
      ],
    );
  }
}
