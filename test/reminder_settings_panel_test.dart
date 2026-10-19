import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mind_bubble/features/bubble_list/reminder_settings_panel.dart';

void main() {
  testWidgets(
    'reminder settings show nonlinear slider, DND range and desktop preview',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ReminderSettingsPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动浮现'), findsOneWidget);
      expect(find.text('启用周期性提醒'), findsOneWidget);
      expect(find.text('2 小时'), findsOneWidget);
      expect(find.text('15 分钟'), findsOneWidget);
      expect(find.text('24 小时'), findsOneWidget);
      expect(find.text('免打扰时段'), findsOneWidget);
      expect(find.text('23:00'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('预览当前主题浮现效果'), findsOneWidget);
      // Section heading and two separate field labels must never overlap.
      final section = tester.getRect(find.text('桌面悬浮提醒'));
      final positionLabel = tester.getRect(find.text('浮现位置'));
      final durationLabel = tester.getRect(find.text('停留时间'));
      final positionField = tester.getRect(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(section.bottom, lessThan(positionLabel.top));
      expect(positionLabel.bottom, lessThan(positionField.top));
      expect(positionField.bottom, lessThan(durationLabel.top));
      expect(tester.takeException(), isNull);
    },
  );
}
