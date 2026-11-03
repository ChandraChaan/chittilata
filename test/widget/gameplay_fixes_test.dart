import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/chat.dart';
import 'package:chittilata/data/models.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:chittilata/ui/widgets/circle_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

/// Regression tests for the 2.4 gameplay fixes and the host controls.
late FakeGameRepository repo;
late Preferences prefs;

DateTime ago(int s) => DateTime.now().subtract(Duration(seconds: s));
DateTime later(int s) => DateTime.now().add(Duration(seconds: s));

const chitIds = [
  'a1', 'a2', 'a3', 'a4', 'b1', 'b2', 'b3', 'b4', //
  'c1', 'c2', 'c3', 'c4', 'd1', 'd2', 'd3', 'd4',
];

Future<void> pumpApp(WidgetTester tester, Widget home) async {
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
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> settle(WidgetTester tester, [int ticks = 8]) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Room playing({
  String host = 'me',
  int currentRound = 1,
  String roundKey = 'g1r01',
  Map<String, Warning> warnings = const {},
  Map<String, String> members = names,
  Map<String, int> totals = const {},
}) => makeRoom(
  status: RoomStatus.playing,
  host: host,
  currentRound: currentRound,
  roundKey: roundKey,
  warnings: warnings,
  members: members,
  totals: totals,
);

const emptyHand = Hand(
  roundKey: 'g1r01',
  cards: [],
  incomingCardId: null,
  character: null,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'sound': false,
      'music': false,
    });
    prefs = await Preferences.load();
    repo = FakeGameRepository();
  });

  group('the last chit', () {
    testWidgets(
      'a movie slip still unfolding when picking ends never blocks the '
      'character chits',
      (tester) async {
        repo.emitRoom(playing());
        repo.emitRound(
          makeRound(
            status: RoundStatus.picking,
            chits: chitIds,
            picks: {for (var i = 0; i < 15; i++) chitIds[i]: 'v'},
            pickOpensAt: ago(10),
            pickDeadline: later(50),
          ),
        );
        repo.emitHand(emptyHand);
        await pumpApp(tester, const RoomScreen(roomId: 'room1'));
        await tester.pump(const Duration(milliseconds: 300));
        // My fourth pick completes the picking: the server moves straight on
        // to passing while my slip is still "unfolding" on screen.
        await tester.tap(find.bySemanticsLabel('Folded chit').first);
        await tester.pump(const Duration(milliseconds: 200));
        expect(repo.calls, ['pick:d4']);
        expect(find.text('You picked…'), findsOneWidget);
        repo.emitRound(makeRound(status: RoundStatus.exchange));
        repo.emitHand(
          const Hand(
            roundKey: 'g1r01',
            cards: myCards,
            incomingCardId: null,
            character: null,
          ),
        );
        // Wait out the screen switch (the old screen fades for 320 ms).
        await settle(tester, 4);
        expect(find.text('You picked…'), findsNothing);
        // Someone wins; everyone else picks a character.
        repo.emitRound(
          makeRound(
            status: RoundStatus.characters,
            winner: const RoundWinner('v', 'RRR', 1000),
            charChits: const ['ca', 'cb', 'cc'],
            charPickOpensAt: ago(1),
            charPickDeadline: later(59),
          ),
        );
        await settle(tester, 3);
        expect(
          find.text('Pick one chit to find your character'),
          findsOneWidget,
        );
        await tester.tap(find.bySemanticsLabel('Folded chit').first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(repo.calls, ['pick:d4', 'pickCharacter:ca']);
        expect(find.text('Your secret character is…'), findsOneWidget);
        await settle(tester, 14);
        await unmount(tester);
      },
    );

    testWidgets(
      'King & Queen: the last role chit picked starts guessing at once, and '
      'the next round\'s chits still respond',
      (tester) async {
        repo.emitRoom(
          makeRoom(
            status: RoomStatus.playing,
            currentRound: 1,
            roundKey: 'g1r01',
            mode: GameMode.kingQueen,
          ),
        );
        repo.emitKqRound(
          makeKqRound(
            status: KqStatus.picking,
            guesser: null,
            chits: const ['r1', 'r2', 'r3', 'r4'],
            picks: const {'r1': 'v', 'r2': 's', 'r3': 'k'},
            pickOpensAt: ago(1),
            pickDeadline: later(59),
          ),
        );
        await pumpApp(tester, const RoomScreen(roomId: 'room1'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.bySemanticsLabel('Folded chit').first);
        await tester.pump(const Duration(milliseconds: 200));
        expect(repo.calls, ['kqPick:r4']);
        // Everyone has picked: guessing starts while my reveal still plays.
        repo.emitKqRound(makeKqRound(guesser: 'v', turnId: 0));
        await tester.pump(const Duration(milliseconds: 400));
        // Round 2 begins: fresh chits, and they must be pickable.
        repo.emitRoom(
          makeRoom(
            status: RoomStatus.playing,
            currentRound: 2,
            roundKey: 'g1r02',
            mode: GameMode.kingQueen,
          ),
        );
        await tester.pump();
        repo.emitKqRound(
          makeKqRound(
            key: 'g1r02',
            roundNo: 2,
            status: KqStatus.picking,
            guesser: null,
            chits: const ['s1', 's2', 's3', 's4'],
            pickOpensAt: ago(1),
            pickDeadline: later(59),
          ),
        );
        await settle(tester, 4);
        expect(find.text('Pick one folded chit'), findsOneWidget);
        expect(find.text('Your secret role is…'), findsNothing);
        await tester.tap(find.bySemanticsLabel('Folded chit').first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(repo.calls, ['kqPick:r4', 'kqPick:s1']);
        await settle(tester, 14);
        await unmount(tester);
      },
    );
  });

  group('return home', () {
    testWidgets(
      'tapping Return to home twice while leaving is slow pops once (no black '
      'screen)',
      (tester) async {
        repo.leaveDelay = const Duration(seconds: 2);
        repo.emitRoom(
          makeRoom(
            status: RoomStatus.finished,
            currentRound: 7,
            roundKey: 'g1r07',
            endedReason: 'host',
            standings: const [
              Standing(
                uid: 'me',
                name: 'Chandra',
                total: 100,
                movieWins: 0,
                rank: 1,
                title: 'King',
                left: false,
              ),
            ],
          ),
        );
        await pumpApp(tester, const HomeScreen());
        final nav = Navigator.of(tester.element(find.byType(HomeScreen)));
        nav.push(
          gameRoute(
            const RoomScreen(roomId: 'room1'),
            name: RoomScreen.routeName,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('GAME OVER'), findsOneWidget);
        await tester.ensureVisible(find.text('Return to home'));
        await tester.tap(find.text('Return to home'));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Return to home'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
        // Also the system back gesture, for good measure.
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 600));
        expect(repo.calls.where((c) => c == 'leave'), hasLength(1));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Movie Chits'), findsOneWidget);
        expect(prefs.activeRoomId, isNull);
      },
    );

    testWidgets('leaving goes home even when the server is unreachable', (
      tester,
    ) async {
      repo.leaveDelay = const Duration(seconds: 30);
      repo.emitRoom(makeRoom());
      await pumpApp(tester, const HomeScreen());
      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        gameRoute(
          const RoomScreen(roomId: 'room1'),
          name: RoomScreen.routeName,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byTooltip('Leave room'));
      await settle(tester, 3);
      await tester.tap(find.text('Leave'));
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    });
  });

  group('the last round', () {
    testWidgets(
      'Movie Chits: the final round\'s results come before GAME OVER',
      (tester) async {
        repo.emitRoom(playing(currentRound: 7, roundKey: 'g1r07'));
        repo.emitRound(
          makeRound(
            key: 'g1r07',
            roundNo: 7,
            status: RoundStatus.characters,
            winner: const RoundWinner('v', 'RRR', 1000),
            charChits: const ['ca', 'cb', 'cc'],
            charPicks: const {'ca': 'me', 'cb': 's', 'cc': 'k'},
            charPickOpensAt: ago(8),
            charPickDeadline: later(52),
            revealAt: later(2),
          ),
        );
        await pumpApp(tester, const RoomScreen(roomId: 'room1'));
        await tester.pump(const Duration(milliseconds: 400));
        // Reveal + game over arrive together from the server.
        repo.emitRound(
          makeRound(
            key: 'g1r07',
            roundNo: 7,
            status: RoundStatus.revealed,
            winner: const RoundWinner('v', 'RRR', 1000),
            revealed: const {
              'me': myCards,
              'v': myCards,
              's': myCards,
              'k': myCards,
            },
            characters: const {
              'me': CharacterDef('Queen', 800),
              's': CharacterDef('Police', 500),
              'k': CharacterDef('Thief', 100),
            },
            scores: const {'me': 800, 'v': 1000, 's': 500, 'k': 100},
          ),
        );
        repo.emitRoom(
          makeRoom(
            status: RoomStatus.finished,
            currentRound: 7,
            roundKey: 'g1r07',
            totals: const {'me': 800, 'v': 1000, 's': 500, 'k': 100},
            standings: const [
              Standing(
                uid: 'v',
                name: 'Vasavi',
                total: 1000,
                movieWins: 1,
                rank: 1,
                title: 'King',
                left: false,
              ),
              Standing(
                uid: 'me',
                name: 'Chandra',
                total: 800,
                movieWins: 0,
                rank: 2,
                title: 'Queen',
                left: false,
              ),
            ],
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Round results'), findsOneWidget);
        expect(find.text('GAME OVER'), findsNothing);
        expect(find.text('See final results'), findsOneWidget);
        await tester.tap(find.text('See final results'));
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('GAME OVER'), findsOneWidget);
        expect(find.text('KING'), findsOneWidget);
        expect(prefs.history.single.rounds, 7);
        await unmount(tester);
      },
    );

    testWidgets('a game the host ended goes straight to the standings', (
      tester,
    ) async {
      repo.emitRoom(playing(currentRound: 3, roundKey: 'g1r03'));
      repo.emitRound(makeRound(key: 'g1r03', roundNo: 3));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 400));
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.finished,
          currentRound: 3,
          roundKey: 'g1r03',
          endedReason: 'host',
          standings: const [
            Standing(
              uid: 'me',
              name: 'Chandra',
              total: 1500,
              movieWins: 1,
              rank: 1,
              title: 'King',
              left: false,
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('GAME OVER'), findsOneWidget);
      expect(find.textContaining('The host ended the game'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('stalemate', () {
    testWidgets('after 4 laps the host can end the round; others see a hint', (
      tester,
    ) async {
      repo.emitRoom(playing());
      repo.emitRound(makeRound(turnId: 15, current: 'me'));
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: myCards,
          incomingCardId: null,
          character: null,
        ),
      );
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('LAP 4'), findsOneWidget);
      expect(find.text('End round'), findsNothing);
      repo.emitRound(makeRound(turnId: 16, current: 'me'));
      await tester.pump(const Duration(milliseconds: 600));
      // The lap count lives in the middle of the circle; the host gets the
      // End-round control in the status panel.
      expect(find.text('LAP 5'), findsOneWidget);
      expect(find.textContaining('No winner after 4 laps'), findsOneWidget);
      await tester.tap(find.text('End round'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.calls, contains('endExchange'));
      await unmount(tester);

      // A guest sees who can end it instead of a button.
      repo = FakeGameRepository(me: 'v');
      repo.emitRoom(playing());
      repo.emitRound(makeRound(turnId: 16, current: 'me'));
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: myCards,
          incomingCardId: null,
          character: null,
        ),
      );
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('End round'), findsNothing);
      expect(find.text('LAP 5'), findsOneWidget);
      expect(find.textContaining('Chandra can end this round'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('with no winner everyone, King chit included, picks a chit', (
      tester,
    ) async {
      repo.emitRoom(playing());
      repo.emitRound(
        makeRound(
          status: RoundStatus.characters,
          stalemate: true,
          turnId: 16,
          charChits: const ['ca', 'cb', 'cc', 'cd'],
          charPickOpensAt: ago(1),
          charPickDeadline: later(59),
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
      repo.nextCharacter = const CharacterDef('King', 1000);
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('NO WINNER THIS ROUND'), findsOneWidget);
      expect(find.text('Pick one chit to find your character'), findsOneWidget);
      expect(find.bySemanticsLabel('Folded chit'), findsNWidgets(4));
      await tester.tap(find.bySemanticsLabel('Folded chit').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['pickCharacter:ca']);
      await settle(tester, 14);
      await unmount(tester);
    });
  });

  group('warnings and removing players', () {
    testWidgets('the host warns from the room menu, then removes after two', (
      tester,
    ) async {
      repo.emitRoom(playing());
      repo.emitRound(makeRound(current: 's'));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Room menu'));
      await settle(tester, 3);
      expect(find.text('Players · 4/10'), findsOneWidget);
      expect(find.text('End game for everyone'), findsOneWidget);
      // Mid-game: warn first, no removal yet.
      expect(find.byTooltip('Remove Swetha'), findsNothing);
      await tester.tap(find.byTooltip('Warn Swetha'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['warn:s']);
      repo.emitRoom(
        playing(
          warnings: {'s': Warning(count: 2, deadline: later(40), by: 'me')},
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('to respond'), findsWidgets);
      await tester.tap(find.byTooltip('Remove Swetha'));
      await settle(tester, 3);
      await tester.tap(find.text('Remove'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['warn:s', 'kick:s']);
      await unmount(tester);
    });

    testWidgets('a warned player sees the countdown and can say I\'m here', (
      tester,
    ) async {
      repo.emitRoom(playing(host: 'v'));
      repo.emitRound(makeRound(current: 'v', next: 's'));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 400));
      repo.emitRoom(
        playing(
          host: 'v',
          warnings: {'me': Warning(count: 1, deadline: later(45), by: 'v')},
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Are you still there?'), findsOneWidget);
      expect(find.textContaining('Respond within 45s'), findsOneWidget);
      await tester.tap(find.text("I'm here!"));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['imHere']);
      await unmount(tester);
    });

    testWidgets('an unanswered warning is enforced by the first phone', (
      tester,
    ) async {
      repo.emitRoom(
        playing(
          warnings: {'k': Warning(count: 1, deadline: ago(3), by: 'me')},
        ),
      );
      repo.emitRound(makeRound(current: 'v', next: 's'));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await settle(tester, 4);
      expect(repo.calls, contains('enforceWarnings'));
      await unmount(tester);
    });

    testWidgets('the host ends the game for everyone from the menu', (
      tester,
    ) async {
      repo.emitRoom(playing());
      repo.emitRound(makeRound(current: 'v', next: 's'));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Room menu'));
      await settle(tester, 3);
      await tester.tap(find.text('End game for everyone'));
      await settle(tester, 3);
      await tester.tap(find.text('End game'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.calls, ['endGame']);
      await unmount(tester);
    });

    testWidgets('a removed player is told why', (tester) async {
      repo.emitRoom(playing());
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 400));
      repo.emitRoom(
        Room(
          id: 'room1',
          code: 'ABC234',
          hostUid: 'v',
          status: RoomStatus.playing,
          memberUids: const ['v', 's', 'k'],
          players: {
            for (final e in names.entries)
              e.key: PlayerInfo(
                uid: e.key,
                name: e.value,
                ready: true,
                left: e.key == 'me',
                joinedAt: 0,
                leftReason: e.key == 'me' ? 'timeout' : null,
              ),
          },
          settings: defaultSettings,
          gameNo: 1,
          currentRound: 1,
          currentRoundKey: 'g1r01',
          totals: const {},
          movieWins: const {},
          finalStandings: null,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('You were removed for not responding'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('joining a running game', () {
    testWidgets('a watcher with a free seat can join from the next round', (
      tester,
    ) async {
      repo = FakeGameRepository(me: 'late');
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
          spectators: const {'late': Spectator(uid: 'late', name: 'Lata')},
        ),
      );
      repo.emitRound(makeRound(current: 'v', next: 's'));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Join the game'), findsOneWidget);
      await tester.tap(find.text('Join the game'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['takeSeat']);
      // Seated: they sit out the round in progress.
      repo.emitRoom(playing(members: {...names, 'late': 'Lata'}));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text("You're in!"), findsOneWidget);
      expect(
        find.textContaining('You get your chits from the next round'),
        findsOneWidget,
      );
      await unmount(tester);
    });
  });

  group('drag and drop', () {
    testWidgets('a slip dragged onto the circle is passed; slips can be '
        'rearranged by dropping one on another', (tester) async {
      repo.emitRoom(playing());
      repo.emitRound(makeRound(current: 'me', next: 'v'));
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: myCards,
          incomingCardId: null,
          character: null,
        ),
      );
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 700));
      // Rearrange: drop Devara onto Pushpa 2's spot.
      final devara = find.bySemanticsLabel('Slip: Devara').last;
      final pushpa = find.bySemanticsLabel('Slip: Pushpa 2').last;
      final target = tester.getCenter(pushpa) + const Offset(12, 0);
      final g = await tester.startGesture(tester.getCenter(devara));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(target);
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, isEmpty);
      final order = tester
          .widgetList<Semantics>(
            find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  (w.properties.label ?? '').startsWith('Slip: '),
            ),
          )
          .map((w) => w.properties.label)
          .toList();
      expect(
        order.indexOf('Slip: Devara'),
        greaterThan(order.indexOf('Slip: Salaar')),
      );
      // Pass: drag RRR up onto the circle.
      final rrr = find.bySemanticsLabel('Slip: RRR').last;
      final circle = tester.getCenter(find.byType(CircleOrder));
      final g2 = await tester.startGesture(tester.getCenter(rrr));
      await tester.pump(const Duration(milliseconds: 100));
      await g2.moveTo(circle);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Drop to pass to Vasavi'), findsOneWidget);
      await g2.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.calls, ['pass:0:c1']);
      await unmount(tester);
    });

    testWidgets('a folded chit dragged into the tray is picked', (
      tester,
    ) async {
      repo.emitRoom(playing());
      repo.emitRound(
        makeRound(
          status: RoundStatus.picking,
          chits: chitIds,
          pickOpensAt: ago(10),
          pickDeadline: later(50),
        ),
      );
      repo.emitHand(emptyHand);
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 300));
      final chit = tester.getCenter(find.bySemanticsLabel('Folded chit').first);
      final tray = tester.getCenter(find.text('0 / 4'));
      final g = await tester.startGesture(chit);
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(Offset(chit.dx, chit.dy + 40));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(tray);
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, hasLength(1));
      expect(repo.calls.first, startsWith('pick:'));
      await settle(tester, 12);
      await unmount(tester);
    });
  });

  group('room chat', () {
    testWidgets('typed messages are sent and shown in the history', (
      tester,
    ) async {
      repo.emitRoom(makeRoom());
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Room chat'));
      await settle(tester, 3);
      expect(find.text('Room chat'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Message the table…'),
        '  Who has my   fourth RRR?  ',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, ['chat:text:Who has my fourth RRR?']);
      expect(find.text('Who has my fourth RRR?'), findsWidgets);
      await settle(tester, 2);
      await tester.pump(const Duration(seconds: 5));
      await unmount(tester);
    });

    testWidgets('quick-match tables get presets only, and unread counts show', (
      tester,
    ) async {
      repo.emitRoom(makeRoom(isPublic: true, createdAt: DateTime.now()));
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 300));
      repo.emitMessage(
        ChatMessage(
          id: 'm1',
          uid: 'v',
          kind: ChatKind.text,
          text: 'hello',
          at: DateTime.now(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1'), findsOneWidget); // unread badge
      await tester.tap(find.byTooltip('Room chat'));
      await settle(tester, 3);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('emojis and preset lines'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await unmount(tester);
    });

    test('free text is tidied and family-safe', () {
      expect(cleanChatText('   '), isNull);
      expect(cleanChatText(' hi   there '), 'hi there');
      expect(cleanChatText('x' * 100)!.length, maxChatText);
      expect(cleanChatText('what the fuck'), 'what the ****');
    });
  });
}
