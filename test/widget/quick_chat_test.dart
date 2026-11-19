import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/chat.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

late FakeGameRepository repo;
late Preferences prefs;

Future<void> pumpRoom(WidgetTester tester) async {
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
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'sound': false,
      'music': false,
    });
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

  testWidgets('preset phrases are sent from the chat panel', (tester) async {
    await pumpRoom(tester);
    await tester.tap(find.byTooltip('Room chat'));
    await tester.pumpAndSettle();
    expect(find.text('Hurry up! ⏰'), findsOneWidget);
    await tester.tap(find.text('Nice one! 👏'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(repo.calls, ['chat:phrase:nice']);
    // The panel keeps the line in its history...
    expect(find.text('Nice one! 👏'), findsNWidgets(2));
    Navigator.of(tester.element(find.text('Room chat'))).pop();
    await tester.pumpAndSettle();
    // ...and it floats up over the game for everyone.
    expect(find.textContaining('Nice one!'), findsOneWidget);
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

  group('masking', () {
    test('masks blocked words, also disguised ones', () {
      expect(maskChatText('you are a bitch'), 'you are a *****');
      expect(maskChatText('sh1t happens'), '**** happens');
      expect(maskChatText('Fuuuuck!!'), '*********');
      expect(maskChatText('f u c k off'), '* * * * off');
      expect(maskChatText('Who has my fourth RRR?'), 'Who has my fourth RRR?');
      expect(maskChatText('Kshitij passes classes'), 'Kshitij passes classes');
      expect(cleanChatText('  hi   there  '), 'hi there');
      expect(cleanChatText('   '), isNull);
    });

    test('text from an old or modified app is masked on arrival', () {
      final m = ChatMessage.fromMap('m1', {
        'uid': 'v',
        'kind': 'text',
        'code': textCode,
        'text': 'what the fuck',
      }, DateTime.now());
      expect(m!.text, 'what the ****');
    });
  });

  testWidgets('long-press mutes a player: their messages disappear', (
    tester,
  ) async {
    repo.emitMessage(
      ChatMessage(
        id: 'm1',
        uid: 'v',
        kind: ChatKind.text,
        text: 'pass faster!',
        at: DateTime.now(),
      ),
    );
    await pumpRoom(tester);
    await tester.tap(find.byTooltip('Room chat'));
    await tester.pumpAndSettle();
    expect(find.text('pass faster!'), findsOneWidget);
    await tester.longPress(find.text('pass faster!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute Vasavi'));
    await tester.pumpAndSettle();
    expect(find.text('pass faster!'), findsNothing);
    expect(prefs.isMuted('v'), isTrue);
    await finish(tester);
  });

  testWidgets('reporting a message sends it for review and mutes them', (
    tester,
  ) async {
    repo.emitMessage(
      ChatMessage(
        id: 'm2',
        uid: 'v',
        kind: ChatKind.text,
        text: 'something rude',
        at: DateTime.now(),
      ),
    );
    await pumpRoom(tester);
    await tester.tap(find.byTooltip('Room chat'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('something rude'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report this message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abusive or hateful'));
    await tester.pumpAndSettle();
    expect(repo.reports.single, {
      'roomId': 'room1',
      'target': 'v',
      'targetName': 'Vasavi',
      'messageId': 'm2',
      'text': 'something rude',
      'reason': 'abusive',
    });
    expect(prefs.isMuted('v'), isTrue);
    expect(find.text('something rude'), findsNothing);
    await finish(tester);
  });

  testWidgets('typed messages can be switched off; presets still show', (
    tester,
  ) async {
    prefs.typedChat = false;
    repo
      ..emitMessage(
        ChatMessage(
          id: 'm3',
          uid: 'v',
          kind: ChatKind.text,
          text: 'typed words',
          at: DateTime.now(),
        ),
      )
      ..emitMessage(
        ChatMessage(
          id: 'm4',
          uid: 'v',
          kind: ChatKind.phrase,
          text: 'Nice one! 👏',
          at: DateTime.now(),
        ),
      );
    await pumpRoom(tester);
    await tester.tap(find.byTooltip('Room chat'));
    await tester.pumpAndSettle();
    expect(find.text('typed words'), findsNothing);
    expect(find.text('Nice one! 👏'), findsNWidgets(2));
    await finish(tester);
  });
}
