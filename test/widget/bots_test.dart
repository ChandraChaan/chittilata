import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/models.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

const withBots = {
  'me': 'Chandra',
  'bot_a': 'Chitti 🤖',
  'bot_b': 'Robo Raju 🤖',
  'bot_c': 'Bujji Bot 🤖',
};

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

  testWidgets('Practice with bots makes a room with 3 bots', (tester) async {
    repo.emitRoom(makeRoom(members: withBots));
    await pump(tester, const HomeScreen());
    await tester.ensureVisible(find.text('Practice with bots').first);
    await tester.pump();
    await tester.tap(find.text('Practice with bots').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.calls, ['createRoom:Chandra', 'addBot', 'addBot', 'addBot']);
    await unmount(tester);
  });

  testWidgets('the host can add bots; bots show as always ready', (
    tester,
  ) async {
    repo.emitRoom(makeRoom(members: withBots));
    await pump(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Add a bot'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bot · always ready'), findsWidgets);
    await tester.tap(find.text('Add a bot'));
    await tester.pump();
    expect(repo.calls, ['addBot']);
    await unmount(tester);
  });

  testWidgets('a bot whose turn it is moves by itself, never shown as late', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        members: withBots,
      ),
    );
    repo.emitRound(
      makeRound(
        order: const ['me', 'bot_a', 'bot_b', 'bot_c'],
        current: 'bot_a',
        next: 'bot_b',
        turnId: 3,
        introEndsAt: DateTime.now().subtract(const Duration(seconds: 10)),
        deadline: DateTime.now().subtract(const Duration(seconds: 60)),
      ),
    );
    repo.emitHand(
      const Hand(
        roundKey: 'g1r01',
        cards: myCards,
        incomingCardId: null,
        character: null,
      ),
    );
    await pump(tester, const RoomScreen(roomId: 'room1'));
    expect(repo.calls, isEmpty);
    // It "thinks" first, then the move is sent once.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3200)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(repo.calls, ['timeout:3']);
    expect(find.textContaining('Play for'), findsNothing);
    expect(find.textContaining('fell asleep'), findsNothing);
    await unmount(tester);
  });
}
