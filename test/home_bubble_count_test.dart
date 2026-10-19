import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mind_bubble/features/bubble_list/home_bubble_count_setting.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/services/bubble_refresh_service.dart';
import 'package:mind_bubble/features/recommendations/recommendation_event_store.dart';
import 'package:mind_bubble/services/home_bubble_count.dart';
import 'package:mind_bubble/repositories/bubble_repository.dart';
import 'package:mind_bubble/services/bubble_document_store.dart';
import 'package:mind_bubble/viewmodels/bubble_view_models.dart';

class _FakeBubbleRepository implements BubbleRepository {
  _FakeBubbleRepository(this.notes);
  final List<Bubble> notes;
  @override
  final RecommendationEventStore events = RecommendationEventStore.memory();

  @override
  Future<List<Bubble>> getAll({
    String query = '',
    bool includeDeleted = false,
  }) async => notes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'home refresh quantity defaults to 5 and clamps persisted values',
    () async {
      SharedPreferences.setMockInitialValues({});
      final initialContainer = ProviderContainer();
      await initialContainer.read(homeBubbleCountProvider.notifier).load();
      expect(initialContainer.read(homeBubbleCountProvider), 5);
      initialContainer.dispose();

      SharedPreferences.setMockInitialValues({HomeBubbleCount.storageKey: 15});
      final restoredContainer = ProviderContainer();
      final restored = restoredContainer.read(homeBubbleCountProvider.notifier);
      await restored.load();
      expect(restoredContainer.read(homeBubbleCountProvider), 10);
      await restored.setCount(7);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(HomeBubbleCount.storageKey), 7);
      await expectLater(restored.setCount(4), throwsRangeError);
      await expectLater(restored.setCount(11), throwsRangeError);
      restoredContainer.dispose();
    },
  );

  test('weighted home selector supports every count from 5 to 10', () {
    final timestamp = DateTime(2026, 10, 16);
    final library = List.generate(
      15,
      (i) => Bubble(
        id: 'n$i',
        title: 'Note $i',
        description: 'body',
        createdAt: timestamp,
        updatedAt: timestamp,
        appearanceFrequency: 2,
      ),
    );
    for (var count = 5; count <= 10; count++) {
      final selector = BubbleRefreshSelector(random: Random(count));
      final first = selector.draw(library, count: count);
      final second = selector.draw(library, count: count);
      expect(first, hasLength(count));
      expect(
        second.every((n) => library.any((original) => original.id == n.id)),
        isTrue,
      );
    }
    expect(
      BubbleRefreshSelector().draw(library.take(3).toList(), count: 10),
      hasLength(3),
    );
  });

  test(
    'homepage provider redraws at the configured size without reminders',
    () async {
      SharedPreferences.setMockInitialValues({});
      final when = DateTime(2026, 10, 16);
      final notes = List.generate(
        12,
        (i) => Bubble(
          id: 'note-$i',
          title: 'Bubble $i',
          description: 'note',
          createdAt: when,
          updatedAt: when,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          bubbleRepositoryProvider.overrideWithValue(
            _FakeBubbleRepository(notes),
          ),
          documentStoreRevisionProvider.overrideWith((_) => Stream.value(0)),
        ],
      );
      final subscription = container.listen(displayBubblesProvider, (_, __) {});
      try {
        expect(
          await container
              .read(displayBubblesProvider.future)
              .timeout(const Duration(seconds: 5)),
          hasLength(5),
        );
        await container.read(homeBubbleCountProvider.notifier).setCount(10);
        expect(
          await container
              .read(displayBubblesProvider.future)
              .timeout(const Duration(seconds: 5)),
          hasLength(10),
        );
        container.read(homeRefreshVersionProvider.notifier).state++;
        expect(
          await container
              .read(displayBubblesProvider.future)
              .timeout(const Duration(seconds: 5)),
          hasLength(10),
        );
        await container.read(homeBubbleCountProvider.notifier).setCount(6);
        expect(
          await container
              .read(displayBubblesProvider.future)
              .timeout(const Duration(seconds: 5)),
          hasLength(6),
        );
      } finally {
        subscription.close();
        container.dispose();
      }
    },
  );

  testWidgets('home count selector updates and persists chosen quantity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(650, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 430, child: HomeBubbleCountSetting()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('每次刷新数量'), findsOneWidget);
    expect(find.text('5 条'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeBubbleCountDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 条').last);
    await tester.pumpAndSettle();
    expect(find.text('8 条'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(HomeBubbleCount.storageKey), 8);
    expect(tester.takeException(), isNull);
  });
}
