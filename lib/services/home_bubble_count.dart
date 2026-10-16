import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Number of notes shown by a home refresh; independent of reminder sampling.
class HomeBubbleCount {
  static const minimum = 5;
  static const maximum = 10;
  static const defaultValue = 5;
  static const storageKey = 'home.bubbleCount';

  static int normalize(int count) => count.clamp(minimum, maximum);
}

final homeBubbleCountProvider =
    StateNotifierProvider<HomeBubbleCountController, int>(
      (_) => HomeBubbleCountController()..load(),
    );

class HomeBubbleCountController extends StateNotifier<int> {
  HomeBubbleCountController() : super(HomeBubbleCount.defaultValue);
  int _revision = 0;

  Future<void> load() async {
    final revision = _revision;
    final preferences = await SharedPreferences.getInstance();
    final saved = HomeBubbleCount.normalize(
      preferences.getInt(HomeBubbleCount.storageKey) ??
          HomeBubbleCount.defaultValue,
    );
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(HomeBubbleCount.storageKey, count);
  }
}
