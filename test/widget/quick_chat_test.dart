import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/chat.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';

late FakeGameRepository repo;
late Preferences prefs;

Future<void> pumpRoom(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChittilataApp(
      services: AppServices(
        repo: repo,
        prefs: prefs,
        feedback: GameFeedback(prefs),
      ),
      home: const RoomScreen(roomId: 'room1'),
    ),
  );
  await tester.pump();
}

/// Lets bubbles float away and timers stop before the test ends.
Future<void> finish(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'sound': false});
    prefs = await Preferences.load();
    repo = FakeGameRepository();
    repo.emitRoom(makeRoom());
  });

  testWidgets('one tap on an emoji sends it and it floats up for me', (
    tester,
  ) async {
    await pumpRoom(tester);
    await tester.tap(find.bySemanticsLabel('Send 😂'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.calls, ['chat:emoji:laugh']);
    expect(find.text('You'), findsOneWidget);
    // A second tap straight away is throttled (the rules allow one a second).
    await tester.tap(find.bySemanticsLabel('Send 🔥'));
    await tester.pump();
    expect(repo.calls, ['chat:emoji:laugh']);
    await finish(tester);
  });

  testWidgets('preset phrases are sent from the chat sheet', (tester) async {
    await pumpRoom(tester);
    await tester.tap(find.byTooltip('Quick chat'));
    await tester.pumpAndSettle();
    expect(find.text('త్వరగా! ⏰'), findsOneWidget);
    await tester.tap(find.text('Good game! 🤝'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(repo.calls, ['chat:phrase:gg']);
    expect(
      find.textContaining('Good game!'),
      findsOneWidget,
    ); // floating bubble
    await finish(tester);
  });

  testWidgets('a nudge aimed at me shows big; old messages are not replayed', (
    tester,
  ) async {
    repo.emitChat(
      ChatEvent(
        id: 'old1',
        uid: 'v',
        kind: ChatKind.phrase,
        code: 'hurry',
        at: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    );
    await pumpRoom(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Hurry up! ⏰'), findsNothing);

    repo.emitChat(
      ChatEvent(
        id: 'n1',
        uid: 'v',
        kind: ChatKind.nudge,
        code: nudgeCode,
        to: 'me',
        at: DateTime.now(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Vasavi nudged you!'), findsOneWidget);
    await finish(tester);
  });
}
