import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

void main() {
  late FakeGameRepository repo;
  late Preferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'sound': false,
      'music': false,
      'playerName': 'Chandra',
    });
    prefs = await Preferences.load();
    repo = FakeGameRepository();
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    useTestScreen(tester);
    await tester.pumpWidget(
      ChittilataApp(
        services: AppServices(
          repo: repo,
          prefs: prefs,
          feedback: GameFeedback(prefs),
        ),
        home: home,
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Play online finds a table for the chosen game', (tester) async {
    repo.emitRoom(makeRoom(isPublic: true, createdAt: DateTime.now()));
    await pump(tester, const HomeScreen());
    await tester.ensureVisible(find.text('👑 K & Q'));
    await tester.pump();
    await tester.tap(find.text('👑 K & Q'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.calls, ['quickMatch:kingQueen:Chandra']);
    await unmount(tester);
  });

  testWidgets('a public table counts down and then starts by itself', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(
        isPublic: true,
        createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
      ),
    );
    await pump(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump();
    expect(find.textContaining('Quick match · starts in'), findsOneWidget);
    expect(repo.calls, isEmpty);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 12)),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(repo.calls, ['startGame']);
    await unmount(tester);
  });
}
