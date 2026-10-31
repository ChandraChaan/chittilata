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

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Room kqRoom({
  RoomStatus status = RoomStatus.playing,
  Map<String, bool> ready = const {},
  int currentRound = 1,
  Map<String, int> totals = const {},
  List<Standing>? standings,
  Map<String, int> kingWins = const {},
}) => makeRoom(
  status: status,
  ready: ready,
  currentRound: currentRound,
  roundKey: status == RoomStatus.lobby ? null : 'g1r01',
  totals: totals,
  standings: standings,
  mode: GameMode.kingQueen,
  kingWins: kingWins,
);

const myThief = KqMyRole(
  roundKey: 'g1r01',
  index: 3,
  name: 'Thief',
  points: 100,
);
const myKing = KqMyRole(
  roundKey: 'g1r01',
  index: 0,
  name: 'King',
  points: 1000,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarded': true, 'sound': false});
    prefs = await Preferences.load();
    repo = FakeGameRepository();
  });

  testWidgets('home offers both modes; King & Queen creates its own room', (
    tester,
  ) async {
    repo.emitRoom(kqRoom(status: RoomStatus.lobby, currentRound: 0));
    await pumpApp(tester, const HomeScreen());
    expect(find.text('Movie Chits'), findsOneWidget);
    expect(find.text('King & Queen'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Chandra');
    await tester.ensureVisible(find.text('New King & Queen room'));
    await tester.tap(find.text('New King & Queen room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(repo.calls, ['createRoom:Chandra:kingQueen']);
    expect(find.text('👑 King & Queen lobby'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('King & Queen lobby shows the role chain and needs 4 players', (
    tester,
  ) async {
    repo.emitRoom(
      kqRoom(
        status: RoomStatus.lobby,
        currentRound: 0,
        ready: {'v': true, 's': true, 'k': true},
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump();
    expect(find.text('Roles for 4 players (in finding order)'), findsOneWidget);
    for (final r in ['King 1000', 'Queen 800', 'Police 500', 'Thief 100']) {
      expect(find.text(r), findsOneWidget);
    }
    expect(find.text('Minister 700'), findsNothing);
    await tester.tap(find.text('Start game'));
    await tester.pump();
    expect(repo.calls, ['startGame']);
    await unmount(tester);
  });

  testWidgets('picking: tap a folded role chit and see it privately', (
    tester,
  ) async {
    repo.emitRoom(kqRoom());
    repo.emitKqRound(
      makeKqRound(
        status: KqStatus.picking,
        guesser: null,
        chits: const ['r1', 'r2', 'r3', 'r4'],
        pickOpensAt: DateTime.now().subtract(const Duration(seconds: 1)),
        pickDeadline: DateTime.now().add(const Duration(seconds: 19)),
      ),
    );
    repo.emitKqRole(
      const KqMyRole(roundKey: 'g1r01', index: null, name: null, points: null),
    );
    repo.nextKqRole = const KqRoleDef(
      key: '1',
      name: 'Queen',
      points: 800,
      core: false,
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pick one folded chit'), findsOneWidget);
    expect(find.bySemanticsLabel('Folded chit'), findsNWidgets(4));
    await tester.tap(find.bySemanticsLabel('Folded chit').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.calls, ['kqPick:r1']);
    expect(find.text('Your secret role is…'), findsOneWidget);
    // A second pick is refused locally while the first is pending/done.
    await tester.tap(
      find.bySemanticsLabel('Folded chit').last,
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.calls, ['kqPick:r1']);
    await unmount(tester);
  });

  testWidgets('the King selects a candidate and confirms the guess', (
    tester,
  ) async {
    repo.emitRoom(kqRoom());
    repo.emitKqRound(makeKqRound(excluded: const ['v'], guesser: 'me'));
    repo.emitKqRole(myKing);
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Find the Queen!'), findsOneWidget);
    expect(find.text('not the Queen'), findsOneWidget);
    // Excluded players can't be picked.
    await tester.tap(find.bySemanticsLabel(RegExp('^Vasavi')));
    await tester.pump();
    expect(find.text('Tap a player to guess'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Swetha')));
    await tester.pump();
    expect(find.text('Is Swetha the Queen?'), findsOneWidget);
    await tester.tap(find.text('Is Swetha the Queen?'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.calls, ['kqGuess:0:s']);
    await unmount(tester);
  });

  testWidgets('a late King is buzzed but can still guess', (tester) async {
    repo.emitRoom(kqRoom());
    repo.emitKqRound(
      makeKqRound(
        guesser: 'me',
        turnDeadline: DateTime.now().subtract(const Duration(seconds: 8)),
      ),
    );
    repo.emitKqRole(myKing);
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Time's up! Everyone is waiting for you"), findsOneWidget);
    expect(find.text('Make your guess'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Swetha')));
    await tester.pump();
    await tester.tap(find.text('Is Swetha the Queen?'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.calls, ['kqGuess:0:s']);
    await unmount(tester);
  });

  testWidgets('other players watch; their secret role stays on their screen', (
    tester,
  ) async {
    repo.emitRoom(kqRoom());
    repo.emitKqRound(makeKqRound(guesser: 'v'));
    repo.emitKqRole(myThief);
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Vasavi (King) is finding the Queen'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Your role: Thief, 100 points, secret'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel(RegExp('^Swetha')));
    await tester.pump();
    expect(repo.calls, isEmpty);
    expect(find.textContaining('Is Swetha'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a wrong guess that swaps my role tells me privately', (
    tester,
  ) async {
    repo.emitRoom(kqRoom());
    repo.emitKqRound(makeKqRound(guesser: 'v'));
    repo.emitKqRole(myThief);
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(milliseconds: 400));
    repo.emitKqRound(
      makeKqRound(
        guesser: 'me',
        excluded: const ['v'],
        turnId: 1,
        history: const [
          KqGuessRecord(
            step: 0,
            guesser: 'v',
            target: 'me',
            correct: false,
            kind: 'guess',
          ),
        ],
      ),
    );
    repo.emitKqRole(myKing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('You swapped roles: you are now the King.'),
      findsOneWidget,
    );
    expect(find.text('Find the Queen!'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an expired guess turn is never auto-guessed; offline guessers '
      'can be played for', (tester) async {
    repo = FakeGameRepository(me: 'k');
    repo.emitRoom(kqRoom());
    repo.emitKqRound(
      makeKqRound(
        guesser: 's',
        turnDeadline: DateTime.now().subtract(const Duration(seconds: 6)),
      ),
    );
    repo.emitKqRole(myThief);
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(repo.calls, isEmpty);
    await tester.tap(find.text('Play for Swetha'));
    await tester.pump();
    expect(repo.calls, ['kqTimeout:0']);
    await unmount(tester);
  });

  testWidgets('results reveal every role and points; host starts next round', (
    tester,
  ) async {
    repo.emitRoom(
      kqRoom(totals: const {'me': 1000, 'v': 800, 's': 500, 'k': 100}),
    );
    repo.emitKqRound(
      makeKqRound(
        status: KqStatus.revealed,
        guesser: null,
        revealedRoles: const {'me': 0, 'v': 1, 's': 2, 'k': 3},
        scores: const {'me': 1000, 'v': 800, 's': 500, 'k': 100},
      ),
    );
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Roles revealed'), findsOneWidget);
    expect(find.text('Police'), findsOneWidget);
    expect(find.text('+800'), findsOneWidget);
    await tester.tap(find.text('Start round 2'));
    await tester.pump();
    expect(repo.calls, ['nextRound']);
    await unmount(tester);
  });

  testWidgets('final ceremony counts rounds finished as King', (tester) async {
    repo.emitRoom(kqRoom());
    await pumpApp(tester, const RoomScreen(roomId: 'room1'));
    repo.emitRoom(
      kqRoom(
        status: RoomStatus.finished,
        currentRound: 5,
        kingWins: const {'v': 3},
        standings: const [
          Standing(
            uid: 'v',
            name: 'Vasavi',
            total: 4200,
            movieWins: 3,
            rank: 1,
            title: 'King',
            left: false,
          ),
          Standing(
            uid: 'me',
            name: 'Chandra',
            total: 3000,
            movieWins: 1,
            rank: 2,
            title: 'Queen',
            left: false,
          ),
          Standing(
            uid: 's',
            name: 'Swetha',
            total: 2000,
            movieWins: 1,
            rank: 3,
            title: null,
            left: false,
          ),
          Standing(
            uid: 'k',
            name: 'Sai',
            total: 900,
            movieWins: 0,
            rank: 4,
            title: null,
            left: false,
          ),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('KING'), findsOneWidget);
    expect(find.text('3 rounds as King'), findsOneWidget);
    expect(find.text('1 round as King'), findsNWidgets(2));
    expect(prefs.history.single.category, 'King & Queen');
    await unmount(tester);
  });
}
