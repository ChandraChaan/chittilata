import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/invite_links.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

void main() {
  group('invite links', () {
    test('build and read back a room link', () {
      final link = InviteLinks.linkFor('ABC234');
      expect(link.toString(), 'https://chittilata-game.web.app/join/ABC234');
      expect(InviteLinks.codeFrom(link), 'ABC234');
      expect(
        InviteLinks.codeFrom(
          Uri.parse('https://chittilata-game.web.app/join/abc234/'),
        ),
        'ABC234',
      );
      expect(InviteLinks.message('ABC234'), contains(link.toString()));
    });

    test('ignore other hosts, paths and malformed codes', () {
      for (final s in [
        'https://evil.example/join/ABC234',
        'https://chittilata-game.web.app/',
        'https://chittilata-game.web.app/join/ABC',
        'https://chittilata-game.web.app/join/ABC2345',
        'https://chittilata-game.web.app/join/AB C23',
        'https://chittilata-game.web.app/rooms/ABC234',
      ]) {
        expect(InviteLinks.codeFrom(Uri.parse(s)), isNull, reason: s);
      }
    });
  });

  group('opening an invite', () {
    late FakeGameRepository repo;
    late InviteLinks invites;

    Future<void> pump(WidgetTester tester, {String name = ''}) async {
      SharedPreferences.setMockInitialValues({
        'onboarded': true,
        'sound': false,
        'music': false,
        'playerName': name,
      });
      final prefs = await Preferences.load();
      repo = FakeGameRepository();
      repo.emitRoom(makeRoom());
      invites = InviteLinks();
      useTestScreen(tester);
      await tester.pumpWidget(
        ChittilataApp(
          services: AppServices(
            repo: repo,
            prefs: prefs,
            feedback: GameFeedback(prefs),
            invites: invites,
          ),
          home: const HomeScreen(),
        ),
      );
      await tester.pump();
    }

    testWidgets('joins the room straight away when the name is known', (
      tester,
    ) async {
      await pump(tester, name: 'Vasavi');
      invites.receive(InviteLinks.linkFor('ZZZ999'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(repo.calls, ['joinRoom:ZZZ999:Vasavi']);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('ABC234'), findsOneWidget); // the room's lobby
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('asks for a name first, then joins that room', (tester) async {
      await pump(tester);
      invites.receive(InviteLinks.linkFor('ZZZ999'));
      await tester.pump();
      expect(repo.calls, isEmpty);
      expect(find.text('Join room ZZZ999'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Sai');
      await tester.tap(find.text('Join room ZZZ999'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(repo.calls, ['joinRoom:ZZZ999:Sai']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
