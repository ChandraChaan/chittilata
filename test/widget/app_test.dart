import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/game_repository.dart';
import 'package:chittilata/data/models.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:chittilata/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';

late FakeGameRepository repo;
late Preferences prefs;

Future<void> pumpApp(WidgetTester tester, Widget home) async {
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
      home: home,
    ),
  );
  await tester.pump();
}

/// Leaves the room screen so its controller and timers are disposed.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'sound': false});
    prefs = await Preferences.load();
    repo = FakeGameRepository();
  });

  testWidgets('creating a room requires a name, then opens the lobby', (
    tester,
  ) async {
    repo.emitRoom(makeRoom());
    await pumpApp(tester, const HomeScreen());
    await tester.tap(find.text('New Movie Chits room'));
    await tester.pump();
    expect(find.text('Enter your name first'), findsOneWidget);
    expect(repo.calls, isEmpty);

    await tester.enterText(find.byType(TextField), 'Chandra');
    await tester.tap(find.text('New Movie Chits room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.calls, ['createRoom:Chandra']);
    expect(find.text('ABC234'), findsOneWidget);
    expect(prefs.activeRoomId, 'room1');
    await unmount(tester);
  });

  testWidgets('joining validates the code and shows server errors', (
    tester,
  ) async {
    await pumpApp(tester, const HomeScreen());
    await tester.enterText(find.byType(TextField), 'Vasavi');
    await tester.tap(find.text('Join with a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'abc');
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(find.textContaining('6 letters'), findsOneWidget);

    repo.failNext = GameException('not-found', 'No room with that code.');
    await tester.enterText(find.byType(TextField).last, 'zzz999');
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(repo.calls, ['joinRoom:ZZZ999:Vasavi']);
    expect(find.text('No room with that code.'), findsOneWidget);
  });

  testWidgets('lobby: host sees code, players, readiness and a gated Start', (
    tester,
  ) async {
    repo.emitRoom(makeRoom(ready: {'v': true, 's': true}));
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump();
    expect(find.text('ABC234'), findsOneWidget);
    expect(find.text('Chandra (you)'), findsOneWidget);
    expect(find.text('Sai'), findsOneWidget);
    expect(find.text('Not ready'), findsOneWidget);
    expect(find.text('Waiting for everyone to tap Ready…'), findsOneWidget);
    await tester.tap(find.text('Start game'));
    await tester.pump();
    expect(repo.calls, isEmpty);

    repo.emitRoom(makeRoom(ready: {'v': true, 's': true, 'k': true}));
    await tester.pump();
    await tester.tap(find.text('Start game'));
    await tester.pump();
    expect(repo.calls, ['startGame']);
    await unmount(tester);
  });

  testWidgets('lobby: non-host can toggle ready but not edit settings', (
    tester,
  ) async {
    repo = FakeGameRepository(me: 'v');
    repo.emitRoom(makeRoom());
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Only the host can change settings.'), findsOneWidget);
    await tester.tap(find.text("I'm ready"));
    await tester.pump();
    expect(repo.calls, ['setReady:true']);
    await unmount(tester);
  });

  testWidgets(
    'my turn: only my cards shown; select then pass to the next player',
    (tester) async {
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(makeRound());
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

      expect(find.text('Your turn'), findsOneWidget);
      expect(find.text('Your slips · only you can see these'), findsOneWidget);
      for (final c in myCards) {
        expect(find.bySemanticsLabel('Slip: ${c.name}'), findsWidgets);
      }
      expect(find.text('Tap a slip to choose it'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Slip: Devara').last);
      await tester.pump();
      expect(find.text('Pass to Vasavi'), findsOneWidget);
      await tester.tap(find.text('Pass to Vasavi'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.calls, ['pass:0:c2']);
      await unmount(tester);
    },
  );

  testWidgets(
    'not my turn: cards are locked and the countdown names the player',
    (tester) async {
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          current: 's',
          next: 'k',
          turnId: 2,
          deadline: DateTime.now().add(const Duration(seconds: 4)),
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
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Swetha is choosing'), findsOneWidget);
      expect(find.text('Wait for your turn'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^\d seconds left$')),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Slip: RRR').last);
      await tester.pump();
      expect(repo.calls, isEmpty);
      await unmount(tester);
    },
  );

  testWidgets(
    'expired turn: nothing is passed automatically; the late player is told',
    (tester) async {
      repo = FakeGameRepository(me: 's'); // Swetha's turn has run out
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          current: 's',
          next: 'k',
          turnId: 3,
          deadline: DateTime.now().subtract(const Duration(seconds: 3)),
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
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(
        find.text("Time's up! Everyone is waiting for you"),
        findsOneWidget,
      );
      expect(find.text('Pass one slip'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await unmount(tester);
    },
  );

  testWidgets(
    'expired turn: others can nudge a late player who is still online',
    (tester) async {
      repo = FakeGameRepository(me: 'k');
      repo.presence = {'s': Presence(DateTime.now(), 'foreground')};
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          current: 's',
          next: 'k',
          turnId: 3,
          deadline: DateTime.now().subtract(const Duration(seconds: 3)),
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
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Waiting for Swetha ⏰'), findsOneWidget);
      expect(find.textContaining('Play for'), findsNothing);
      await tester.tap(find.text('Nudge 👋'));
      await tester.pump();
      expect(repo.calls, ['chat:nudge:nudge:s']);
      expect(find.text('👋 You nudged Swetha'), findsOneWidget);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await unmount(tester);
    },
  );

  testWidgets(
    'expired turn: once the late player is offline, someone can play for them',
    (tester) async {
      repo = FakeGameRepository(me: 'k'); // no heartbeat from Swetha
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          current: 's',
          next: 'k',
          turnId: 3,
          deadline: DateTime.now().subtract(const Duration(seconds: 3)),
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
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text("Time's up!"), findsOneWidget);
      expect(find.text('Swetha is offline 📵'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await tester.tap(find.text('Play for Swetha'));
      await tester.pump();
      expect(repo.calls, ['timeout:3']);
      await unmount(tester);
    },
  );

  testWidgets('round intro shows the circular order', (tester) async {
    repo.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    repo.emitRound(
      makeRound(introEndsAt: DateTime.now().add(const Duration(seconds: 4))),
    );
    repo.emitHand(
      const Hand(
        roundKey: 'g1r01',
        cards: myCards,
        incomingCardId: null,
        character: null,
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ROUND 1'), findsOneWidget);
    expect(find.text('You → Vasavi → Swetha → Sai → You'), findsOneWidget);
    expect(find.text('You pass first!'), findsOneWidget);
    await unmount(tester);
  });

  final chitIds = [for (var i = 0; i < 16; i++) 'chit$i'];
  DateTime ago(int s) => DateTime.now().subtract(Duration(seconds: s));
  DateTime later(int s) => DateTime.now().add(Duration(seconds: s));

  testWidgets(
    'picking: tap a folded chit, watch it unfold, see it in my tray',
    (tester) async {
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          status: RoundStatus.picking,
          chits: chitIds,
          pickOpensAt: ago(2),
          pickDeadline: later(20),
        ),
      );
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: [],
          incomingCardId: null,
          character: null,
        ),
      );
      repo.nextPickCard = const GameCard(id: 'x1', name: 'Devara');
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Pick 4 more chits'), findsOneWidget);
      expect(find.bySemanticsLabel('Folded chit'), findsNWidgets(16));

      await tester.tap(find.bySemanticsLabel('Folded chit').first);
      await tester.pump();
      expect(repo.calls, ['pick:chit0']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('You picked…'), findsOneWidget);

      // The server confirms: the chit leaves the table and lands in my tray.
      repo.emitRound(
        makeRound(
          status: RoundStatus.picking,
          chits: chitIds,
          picks: const {'chit0': 'me'},
          pickOpensAt: ago(3),
          pickDeadline: later(19),
        ),
      );
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: [GameCard(id: 'x1', name: 'Devara')],
          incomingCardId: null,
          character: null,
        ),
      );
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('You picked…'), findsNothing);
      expect(find.text('1 / 4'), findsOneWidget);
      expect(find.text('Pick 3 more chits'), findsOneWidget);
      expect(find.bySemanticsLabel('Slip: Devara'), findsWidgets);
      await unmount(tester);
    },
  );

  testWidgets(
    'picking: chits cannot be picked while being folded and shuffled',
    (tester) async {
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          status: RoundStatus.picking,
          chits: chitIds,
          pickOpensAt: later(3),
          pickDeadline: later(28),
        ),
      );
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: [],
          incomingCardId: null,
          character: null,
        ),
      );
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Making the chits'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2400));
      final chits = find.bySemanticsLabel('Folded chit');
      if (chits.evaluate().isNotEmpty) {
        await tester.tap(chits.first, warnIfMissed: false);
      }
      await tester.pump();
      expect(repo.calls.where((c) => c.startsWith('pick')), isEmpty);
      await unmount(tester);
    },
  );

  testWidgets(
    'picking: nothing is auto-picked after the deadline; I can still pick',
    (tester) async {
      repo.emitRoom(
        makeRoom(
          status: RoomStatus.playing,
          currentRound: 1,
          roundKey: 'g1r01',
        ),
      );
      repo.emitRound(
        makeRound(
          status: RoundStatus.picking,
          chits: chitIds,
          pickOpensAt: ago(30),
          pickDeadline: ago(4),
        ),
      );
      repo.emitHand(
        const Hand(
          roundKey: 'g1r01',
          cards: [],
          incomingCardId: null,
          character: null,
        ),
      );
      await pumpApp(tester, const RoomScreen(roomId: 'room1'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(repo.calls, isEmpty);
      expect(
        find.text("Time's up! Everyone is waiting for you"),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Folded chit').first);
      await tester.pump();
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single, startsWith('pick:'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await unmount(tester);
    },
  );

  testWidgets('characters: a non-winner picks a chit and privately sees it', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    repo.emitRound(
      makeRound(
        status: RoundStatus.characters,
        winner: const RoundWinner('v', 'RRR', 1000),
        charChits: const ['ca', 'cb', 'cc'],
        charPickOpensAt: ago(1),
        charPickDeadline: later(19),
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
    repo.nextCharacter = const CharacterDef('Police', 500);
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('VASAVI WINS!'), findsOneWidget);
    expect(find.text('Pick one chit to find your character'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Folded chit').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.calls, ['pickCharacter:ca']);
    expect(find.text('Your secret character is…'), findsOneWidget);

    repo.emitHand(
      const Hand(
        roundKey: 'g1r01',
        cards: myCards,
        incomingCardId: null,
        character: CharacterDef('Police', 500),
      ),
    );
    repo.emitRound(
      makeRound(
        status: RoundStatus.characters,
        winner: const RoundWinner('v', 'RRR', 1000),
        charChits: const ['ca', 'cb', 'cc'],
        charPicks: const {'ca': 'me'},
        charPickOpensAt: ago(2),
        charPickDeadline: later(18),
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('You are the Police · +500'), findsOneWidget);
    expect(find.text('Waiting for the others to pick…'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('characters: the winner watches and cannot pick', (tester) async {
    repo.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    repo.emitRound(
      makeRound(
        status: RoundStatus.characters,
        winner: const RoundWinner('me', 'RRR', 1000),
        charChits: const ['ca', 'cb', 'cc'],
        charPickOpensAt: ago(1),
        charPickDeadline: later(19),
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
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('YOU WIN!'), findsOneWidget);
    expect(find.text('The others are picking characters'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Folded chit').first);
    await tester.pump();
    expect(repo.calls, isEmpty);
    await unmount(tester);
  });

  testWidgets('results reveal all hands, characters and the leaderboard', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        totals: {'me': 500, 'v': 1000, 's': 800, 'k': 100},
      ),
    );
    repo.emitRound(
      makeRound(
        status: RoundStatus.revealed,
        winner: const RoundWinner('v', 'RRR', 1000),
        revealed: {
          'me': myCards,
          'v': const [
            GameCard(id: 'a', name: 'RRR'),
            GameCard(id: 'b', name: 'RRR'),
            GameCard(id: 'c', name: 'RRR'),
            GameCard(id: 'd', name: 'RRR'),
          ],
          's': myCards,
          'k': myCards,
        },
        characters: const {
          'me': CharacterDef('Police', 500),
          's': CharacterDef('Queen', 800),
          'k': CharacterDef('Thief', 100),
        },
        scores: const {'me': 500, 'v': 1000, 's': 800, 'k': 100},
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Round results'), findsOneWidget);
    expect(find.text('Vasavi collected four × RRR'), findsOneWidget);
    expect(find.text('Movie winner'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Leaderboard'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Start round 2'), findsOneWidget);
    await tester.tap(find.text('Start round 2'));
    await tester.pump();
    expect(repo.calls, ['nextRound']);
    await unmount(tester);
  });

  testWidgets('starting the next round keeps results up instead of a loader', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    repo.emitRound(
      makeRound(
        status: RoundStatus.revealed,
        winner: const RoundWinner('v', 'RRR', 1000),
        revealed: {'me': myCards, 'v': myCards, 's': myCards, 'k': myCards},
        characters: const {},
        scores: const {'me': 0, 'v': 1000, 's': 0, 'k': 0},
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Round results'), findsOneWidget);

    // Host starts round 2: the room points at g1r02 before its round arrives.
    repo.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 2, roundKey: 'g1r02'),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Loading room…'), findsNothing);
    expect(find.text('Round results'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('final ceremony crowns King and Queen and saves history', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 7, roundKey: 'g1r07'),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.finished,
        currentRound: 7,
        roundKey: 'g1r07',
        standings: const [
          Standing(
            uid: 'v',
            name: 'Vasavi',
            total: 6000,
            movieWins: 3,
            rank: 1,
            title: 'King',
            left: false,
          ),
          Standing(
            uid: 'me',
            name: 'Chandra',
            total: 5200,
            movieWins: 2,
            rank: 2,
            title: 'Queen',
            left: false,
          ),
          Standing(
            uid: 's',
            name: 'Swetha',
            total: 4000,
            movieWins: 1,
            rank: 3,
            title: null,
            left: false,
          ),
          Standing(
            uid: 'k',
            name: 'Sai',
            total: 3000,
            movieWins: 1,
            rank: 4,
            title: null,
            left: false,
          ),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('KING'), findsOneWidget);
    expect(find.text('QUEEN'), findsOneWidget);
    expect(find.text('Final leaderboard'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Play again'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Play again'), findsOneWidget);
    expect(prefs.history.single.standings.first['name'], 'Vasavi');
    await unmount(tester);
  });

  const tiedStandings = [
    Standing(
      uid: 'me',
      name: 'Chandra',
      total: 3000,
      movieWins: 1,
      rank: 1,
      title: 'King',
      left: false,
    ),
    Standing(
      uid: 'v',
      name: 'Vasavi',
      total: 3000,
      movieWins: 1,
      rank: 1,
      title: 'King',
      left: false,
    ),
    Standing(
      uid: 's',
      name: 'Swetha',
      total: 2000,
      movieWins: 1,
      rank: 3,
      title: 'Queen',
      left: false,
    ),
    Standing(
      uid: 'k',
      name: 'Sai',
      total: 100,
      movieWins: 0,
      rank: 4,
      title: null,
      left: false,
    ),
  ];

  TiebreakInfo tie({Map<String, bool> votes = const {}, DateTime? deadline}) =>
      TiebreakInfo(
        title: 'King',
        uids: const ['me', 'v'],
        votes: votes,
        deadline: deadline ?? DateTime.now().add(const Duration(seconds: 30)),
        stage: 'vote',
      );

  testWidgets('tied players are asked whether to play a tie-breaker', (
    tester,
  ) async {
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.tiebreakVote,
        currentRound: 7,
        standings: tiedStandings,
        tiebreak: tie(),
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text("It's a tie for King!"), findsOneWidget);
    expect(find.text('Play tie-breaker'), findsOneWidget);
    await tester.tap(find.text('Play tie-breaker'));
    await tester.pump();
    expect(repo.calls, ['tiebreakVote:true']);

    repo.emitRoom(
      makeRoom(
        status: RoomStatus.tiebreakVote,
        currentRound: 7,
        standings: tiedStandings,
        tiebreak: tie(votes: {'me': true}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Waiting for the others to decide…'), findsOneWidget);
    expect(find.text('Wants a tie-breaker'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a tied player can choose to share the title', (tester) async {
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.tiebreakVote,
        currentRound: 7,
        standings: tiedStandings,
        tiebreak: tie(),
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Share the title'));
    await tester.pump();
    expect(repo.calls, ['tiebreakVote:false']);
    await unmount(tester);
  });

  testWidgets('other players wait, and close the vote after its deadline', (
    tester,
  ) async {
    repo = FakeGameRepository(me: 's');
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.tiebreakVote,
        currentRound: 7,
        standings: tiedStandings,
        tiebreak: tie(
          deadline: DateTime.now().subtract(const Duration(seconds: 5)),
        ),
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Play tie-breaker'), findsNothing);
    expect(
      find.textContaining('The tied players are deciding'),
      findsOneWidget,
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(repo.calls, ['resolveTiebreak']);
    await unmount(tester);
  });

  testWidgets('non-tied players watch the tie-breaker round', (tester) async {
    repo = FakeGameRepository(me: 's');
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 8,
        roundKey: 'g1r01',
        tiebreak: TiebreakInfo(
          title: 'King',
          uids: const ['me', 'v'],
          votes: const {'me': true, 'v': true},
          deadline: DateTime.now(),
          stage: 'playing',
        ),
      ),
    );
    repo.emitRound(makeRound(order: const ['me', 'v'], tiebreak: true));
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('TIE-BREAKER'), findsOneWidget);
    expect(find.text('You are watching the tie-breaker'), findsOneWidget);
    expect(
      find.text('Chandra and Vasavi are playing for the King.'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('settings toggles persist', (tester) async {
    await pumpApp(tester, const SettingsScreen());
    expect(prefs.haptics, isTrue);
    await tester.tap(find.text('Vibration'));
    await tester.pump();
    expect(prefs.haptics, isFalse);
    await tester.tap(find.text('Day'));
    await tester.pump();
    expect(prefs.themeMode, 'light');
  });
}
