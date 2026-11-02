import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/models.dart';
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
    });
    prefs = await Preferences.load();
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

  Room playing({Spectator? watcher}) => makeRoom(
    status: RoomStatus.playing,
    currentRound: 1,
    roundKey: 'g1r01',
    spectators: watcher == null ? const {} : {watcher.uid: watcher},
  );

  testWidgets('a late joiner watches and can ask for their old seat', (
    tester,
  ) async {
    repo = FakeGameRepository(me: 'newphone');
    repo.emitRoom(
      playing(
        watcher: const Spectator(uid: 'newphone', name: 'Sai'),
      ),
    );
    repo.emitRound(makeRound(current: 'v', next: 's'));
    await pump(tester);
    expect(find.text('Watching 👀'), findsOneWidget);
    expect(find.text('Passing now'), findsOneWidget);
    // Nobody has a heartbeat in the fake, so every seat shows as offline.
    await tester.scrollUntilVisible(
      find.text('I am Sai'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('I am Sai'));
    await tester.pump();
    await tester.tap(find.text('I am Sai'));
    await tester.pump();
    expect(repo.calls, ['claimSeat:k']);
    await unmount(tester);
  });

  testWidgets('the host is asked, and can give the seat', (tester) async {
    repo = FakeGameRepository();
    repo.emitRoom(
      playing(
        watcher: const Spectator(uid: 'newphone', name: 'Sai', claims: 'k'),
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
    await pump(tester);
    expect(find.text('Sai says they are Sai on a new phone.'), findsOneWidget);
    await tester.tap(find.text('Give seat'));
    await tester.pump();
    expect(repo.calls, ['answerSeat:newphone:true']);
    await unmount(tester);
  });
}
