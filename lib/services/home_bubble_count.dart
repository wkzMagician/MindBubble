import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/recommendations/recommendation_config.dart';

/// Number of notes in a home batch, stored with the shared recommendation config.
class HomeBubbleCount {
  static const minimum = 5;
  static const maximum = 10;
  static const defaultValue = 5;
  static const storageKey = 'home.bubbleCount';

  static int normalize(int count) => count.clamp(minimum, maximum);
}

final homeBubbleCountProvider =
    StateNotifierProvider<HomeBubbleCountController, int>((ref) {
      final controller = HomeBubbleCountController(
        initialCount: ref.read(recommendationConfigProvider).bubbleCount,
        onChanged: (count) async {
          final config = await RecommendationConfig.load();
          await ref
              .read(recommendationConfigProvider.notifier)
              .update(config.copyWith(bubbleCount: count));
        },
      );
      ref.listen(
        recommendationConfigProvider,
        (_, config) => controller.adopt(config.bubbleCount),
      );
      return controller..load();
    });

class HomeBubbleCountController extends StateNotifier<int> {
  HomeBubbleCountController({
    int initialCount = HomeBubbleCount.defaultValue,
    Future<void> Function(int)? onChanged,
  }) : _onChanged = onChanged,
       super(initialCount);
  final Future<void> Function(int)? _onChanged;
  int _revision = 0;

  Future<void> load() async {
    final revision = _revision;
    final saved = (await RecommendationConfig.load()).bubbleCount;
    if (mounted && revision == _revision) state = saved;
  }

  Future<void> setCount(int count) async {
    if (count < HomeBubbleCount.minimum || count > HomeBubbleCount.maximum) {
      throw RangeError.range(
        count,
        HomeBubbleCount.minimum,
        HomeBubbleCount.maximum,
        'count',
      );
    }
    _revision++;
    state = count;
    if (_onChanged != null) {
      await _onChanged(count);
    } else {
      await (await RecommendationConfig.load())
          .copyWith(bubbleCount: count)
          .save();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(HomeBubbleCount.storageKey, count);
  }

  void adopt(int count) {
    if (mounted && state != count) {
      _revision++;
      state = count;
    }
  }
}
