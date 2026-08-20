import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mind_bubble/features/ocean/ocean_page.dart';
import 'package:mind_bubble/l10n/app_localizations.dart';
import 'package:mind_bubble/models/bubble.dart';
import 'package:mind_bubble/viewmodels/bubble_view_models.dart';

void main() {
  testWidgets('ocean page renders its bubble content', (tester) async {
    tester.view.physicalSize = const Size(900, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayBubblesProvider.overrideWith((_) async => [_bubble()]),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const OceanPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(OceanPage), findsOneWidget);
    expect(find.text('A calm idea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Bubble _bubble() => Bubble(
  id: 'golden-bubble',
  title: 'A calm idea',
  description: 'A stable visual fixture.',
  createdAt: DateTime.utc(2026, 8, 14),
  updatedAt: DateTime.utc(2026, 8, 14),
);
