import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/charades.dart';
import 'package:chittilata/data/models.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

const options = ['RRR', 'Devara', 'Salaar', 'Pushpa 2', 'Bahubali', 'Jersey'];

CharadesRound acting({
  String actor = 'v',
  Map<String, int> guesses = const {},
  bool revealed = false,
  String? solvedBy,
  Map<String, int>? scores,
}) => CharadesRound(
  key: 'g1r01',
  gameNo: 1,
  roundNo: 1,
  revealed: revealed,
  actor: actor,
  options: options,
  startsAt: DateTime.now().subtract(const Duration(seconds: 5)),
  deadline: DateTime.now().add(const Duration(seconds: 60)),
  guesses: guesses,
  solvedBy: solvedBy,
  answer: revealed ? 2 : null,
  scores: scores,
);

void main() {
  late FakeGameRepository repo;
  late Preferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'sound': false,
      'music': false,
    });
    prefs = await Preferences.load();
    repo = FakeGameRepository();
    repo.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        mode: GameMode.charades,
      ),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    useTestScreen(tester);
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
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the actor sees the secret movie; no choices', (tester) async {
    repo.emitCharades(acting(actor: 'me'));
    repo.emitCard(const CharadesCard('g1r01', 'Salaar'));
    await pump(tester);
    expect(find.text('Act it out!'), findsOneWidget);
    expect(find.text('Salaar'), findsOneWidget);
    expect(find.text('Devara'), findsNothing);
    await unmount(tester);
  });

  testWidgets('guessers pick one of six titles, once', (tester) async {
    repo.emitCharades(acting());
    await pump(tester);
    expect(find.text('Watch Vasavi!'), findsOneWidget);
    for (final o in options) {
      expect(find.text(o), findsOneWidget);
    }
    await tester.tap(find.text('Devara'));
    await tester.pump();
    expect(repo.calls, ['guess:1']);

    repo.emitCharades(acting(guesses: {'me': 1}));
    await tester.pump();
    expect(find.text('❌ Not "Devara". Wait for the others…'), findsOneWidget);
    await tester.tap(find.text('RRR'));
    await tester.pump();
    expect(repo.calls, ['guess:1']);
    await unmount(tester);
  });

  testWidgets('the result shows the answer, who got it and the points', (
    tester,
  ) async {
    repo.emitCharades(
      acting(revealed: true, solvedBy: 's', scores: {'s': 210, 'v': 75}),
    );
    await pump(tester);
    expect(find.text('🎉 Swetha got it!'), findsOneWidget);
    expect(find.text('Salaar'), findsOneWidget);
    expect(find.text('+210 this round'), findsOneWidget);
    expect(find.text('Next: Vasavi acts'), findsOneWidget);
    await unmount(tester);
  });
}
