import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/core/theme/festivals.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';

void main() {
  test('Auto switches on around each festival only', () {
    expect(Festival.on(DateTime(2027, 1, 14)), Festival.sankranti);
    expect(Festival.on(DateTime(2027, 1, 20)), isNull);
    expect(Festival.on(DateTime(2026, 11, 8)), Festival.diwali);
    expect(Festival.on(DateTime(2027, 4, 7)), Festival.ugadi);
    expect(Festival.on(DateTime(2026, 7, 1)), isNull);
    expect(Festival.chosen('off', DateTime(2026, 11, 8)), isNull);
    expect(Festival.chosen('ugadi', DateTime(2026, 7, 1)), Festival.ugadi);
  });

  for (final f in Festival.values) {
    for (final dark in [true, false]) {
      testWidgets('${f.label} (${dark ? 'night' : 'day'}) home fits a small '
          'phone with large text', (tester) async {
        SharedPreferences.setMockInitialValues({
          'onboarded': true,
          'sound': false,
          'music': false,
          'festival': f.name,
          'themeMode': dark ? 'dark' : 'light',
        });
        final prefs = await Preferences.load();
        tester.view.physicalSize = const Size(640, 1280);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          ChittilataApp(
            services: AppServices(
              repo: FakeGameRepository(),
              prefs: prefs,
              feedback: GameFeedback(prefs),
            ),
            home: const HomeScreen(),
          ),
        );
        await tester.pump();
        expect(find.text(f.greeting), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
