import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/invite_links.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/groups.dart';
import 'package:chittilata/ui/screens/groups_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/screen.dart';

const family = Group(
  id: 'g1',
  name: 'Family',
  code: 'FAM123',
  ownerUid: 'me',
  memberUids: ['me', 'v', 's'],
  members: {
    'me': GroupMember(name: 'Chandra', avatar: '🦁'),
    'v': GroupMember(name: 'Vasavi'),
    's': GroupMember(name: 'Swetha'),
  },
);

void main() {
  group('seasons', () {
    test('are calendar months in India time', () {
      expect(Season.idFor(DateTime.utc(2026, 11, 30, 19)), '2026-12');
      expect(Season.idFor(DateTime.utc(2026, 11, 30, 18)), '2026-11');
      expect(Season.previous('2026-01'), '2025-12');
      expect(Season.previous('2026-11'), '2026-10');
      expect(Season.label('2026-11'), 'November 2026');
    });

    test('rank by points, then King titles', () {
      const s = Season(
        id: '2026-11',
        points: {'a': 100, 'b': 300, 'c': 300},
        games: {'a': 1, 'b': 2, 'c': 2},
        kings: {'c': 1},
      );
      expect(s.ranking, ['c', 'b', 'a']);
    });

    test('group invite links are read separately from room links', () {
      final link = InviteLinks.groupLinkFor('FAM123');
      expect(InviteLinks.groupCodeFrom(link), 'FAM123');
      expect(InviteLinks.codeFrom(link), isNull);
      final invites = InviteLinks()..receive(link);
      expect(invites.pendingGroup, 'FAM123');
      expect(invites.pending, isNull);
    });
  });

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
    await tester.pump();
  }

  testWidgets('create a group from the groups screen', (tester) async {
    await pump(tester, const GroupsScreen());
    expect(find.text('No groups yet'), findsOneWidget);
    await tester.tap(find.text('Create a group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Family');
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(repo.calls, ['createGroup:Family']);
  });

  testWidgets('a group shows its code, monthly leaderboard and champion', (
    tester,
  ) async {
    repo.groups.add(family);
    final now = Season.idFor(DateTime.now());
    final last = Season.previous(now);
    repo.seasons['g1/$now'] = const Season(
      id: '',
      points: {'me': 1200, 'v': 2500},
      games: {'me': 2, 'v': 2},
      kings: {'v': 1},
    );
    repo.seasons['g1/$last'] = const Season(
      id: '',
      points: {'s': 9000},
      games: {'s': 5},
    );
    await pump(tester, const GroupScreen(groupId: 'g1'));
    expect(find.text('FAM123'), findsOneWidget);
    expect(find.text('2500'), findsOneWidget);
    expect(find.text('🥇'), findsOneWidget);
    expect(find.textContaining('Swetha was champion'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('New Movie Chits game'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('New Movie Chits game'));
    await tester.pump();
    expect(repo.calls, ['createRoom:Chandra']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
