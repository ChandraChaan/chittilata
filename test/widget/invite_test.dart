import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/contact_invite.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/invite_links.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:flutter/services.dart';
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

  group('inviting a contact', () {
    test('WhatsApp numbers in international form', () {
      expect(
        ContactInvite.whatsappNumber('+91 98765 43210', country: 'US'),
        '919876543210',
      );
      expect(
        ContactInvite.whatsappNumber('098765 43210', country: 'IN'),
        '919876543210',
      );
      expect(
        ContactInvite.whatsappNumber('98765-43210', country: 'IN'),
        '919876543210',
      );
      expect(
        ContactInvite.whatsappNumber('0044 7700 900123', country: 'IN'),
        '447700900123',
      );
      // A local number abroad: let WhatsApp ask who to send it to.
      expect(
        ContactInvite.whatsappNumber('(415) 555-0100', country: 'US'),
        isNull,
      );
      expect(
        ContactInvite.whatsappUri(
          '(415) 555-0100',
          'hi',
          country: 'US',
        ).toString(),
        'https://wa.me/?text=hi',
      );
      expect(
        ContactInvite.smsUri('+91 98765 43210', 'Join me').toString(),
        'sms:+919876543210?body=Join%20me',
      );
    });
  });

  group('lobby invite options', () {
    const channel = MethodChannel('chitplay/contacts');

    Future<void> pumpLobby(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarded': true,
        'sound': false,
        'music': false,
      });
      final prefs = await Preferences.load();
      final repo = FakeGameRepository()..emitRoom(makeRoom());
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

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('QR code shows the room link to scan', (tester) async {
      await pumpLobby(tester);
      await tester.tap(find.text('QR code'));
      await tester.pumpAndSettle();
      expect(find.text('Scan to join'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^QR code to join room [A-Z0-9]{6}$')),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('a picked contact can be invited on WhatsApp or by SMS', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {'name': 'Asha', 'number': '+91 98765 43210'},
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await pumpLobby(tester);
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      expect(find.text('Invite Asha'), findsOneWidget);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      expect(find.text('Send a text message'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('backing out of the picker does nothing', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await pumpLobby(tester);
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      expect(find.text('Send on WhatsApp'), findsNothing);
      await unmount(tester);
    });
  });
}
