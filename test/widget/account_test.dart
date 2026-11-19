import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/account.dart';
import 'package:chittilata/core/services/cloud_profile.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/ui/screens/profile_screen.dart';
import 'package:chittilata/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_account.dart';
import '../support/fake_repository.dart';
import '../support/screen.dart';

late Preferences prefs;
late FakeAccountBackend backend;
late Account account;
late List<String> userChanges;

Future<void> pump(
  WidgetTester tester,
  Widget home, {
  bool withAccount = true,
}) async {
  useTestScreen(tester);
  await tester.pumpWidget(
    ChittilataApp(
      services: AppServices(
        repo: FakeGameRepository(),
        prefs: prefs,
        feedback: GameFeedback(prefs),
        account: withAccount ? account : null,
      ),
      home: home,
    ),
  );
  await tester.pump();
}

/// Scrolls the screen's list until [text] is built (lists build lazily).
Future<void> scrollTo(
  WidgetTester tester,
  String text, {
  double by = 300,
}) async {
  if (find.text(text).evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    find.text(text),
    by,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> tapText(WidgetTester tester, String text) async {
  await scrollTo(tester, text);
  await tester.ensureVisible(find.text(text).last);
  await tester.pump();
  await tester.tap(find.text(text).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'onboarded': true,
      'sound': false,
      'music': false,
      'playerName': 'Chandra',
    });
    prefs = await Preferences.load();
    prefs.stats.record('game:r1:1', {'games': 1, 'xp': 50});
    backend = FakeAccountBackend();
    userChanges = [];
    account = Account(
      backend,
      prefs,
      syncDelay: Duration.zero,
      beforeUserChange: () async => userChanges.add('before'),
      afterUserChange: () async => userChanges.add('after'),
    )..start();
  });

  testWidgets('the profile is unchanged without the account service', (
    tester,
  ) async {
    await pump(tester, const ProfileScreen(), withAccount: false);
    expect(find.text('Chandra'), findsWidgets);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.text('Lv 1'), findsOneWidget);
  });

  testWidgets('guests see an optional sign-in and nothing syncs', (
    tester,
  ) async {
    await pump(tester, const ProfileScreen());
    expect(find.text('Playing as a guest'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    // Deleting is in Settings for guests, not on the profile.
    expect(find.text('Delete my account and data'), findsNothing);
    expect(find.text('Lv 1'), findsOneWidget);

    // Playing as a guest never touches the cloud profile.
    prefs.stats.record('game:r2:1', {'games': 1});
    prefs.playerName = 'Someone';
    await tester.pump(const Duration(seconds: 1));
    expect(backend.calls, isEmpty);
  });

  testWidgets('signing in links the guest and merges with the cloud', (
    tester,
  ) async {
    backend.cloud = const CloudProfile(
      counters: {'games': 12, 'xp': 900, 'kings': 2},
      badges: {'king', 'regular'},
    );
    await pump(tester, const ProfileScreen());
    await tapText(tester, 'Sign in with Google');

    expect(backend.calls, ['signInWithGoogle', 'sync']);
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.textContaining('player@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Signed in. Your progress is saved.'), findsOneWidget);
    // Local progress went up, the cloud kept the larger numbers.
    expect(prefs.stats.counters['games'], 12);
    expect(backend.cloud.counters['games'], 12);
    expect(backend.cloud.name, 'Chandra');
    await scrollTo(tester, 'Lv 4', by: -300);
    expect(find.text('Lv 4'), findsOneWidget);
    // The same uid: rooms stay, so the push token isn't moved.
    expect(userChanges, isEmpty);

    // From now on, new progress syncs by itself.
    backend.calls.clear();
    prefs.stats.record('game:r9:1', {'games': 1});
    await tester.pump(const Duration(milliseconds: 10));
    expect(backend.calls, ['sync']);
    expect(backend.cloud.counters['games'], 13);
  });

  testWidgets('closing the Google sheet changes nothing', (tester) async {
    backend.nextResult = SignInResult.cancelled;
    await pump(tester, const ProfileScreen());
    await tapText(tester, 'Sign in with Google');
    expect(backend.calls, ['signInWithGoogle']);
    expect(find.text('Playing as a guest'), findsOneWidget);
  });

  testWidgets('a sign-in error shows a message and stays a guest', (
    tester,
  ) async {
    backend.failNext = AccountException('No internet. Try again when online.');
    await pump(tester, const ProfileScreen());
    await tapText(tester, 'Sign in with Google');
    expect(find.text('No internet. Try again when online.'), findsOneWidget);
    expect(find.text('Playing as a guest'), findsOneWidget);
  });

  testWidgets('a Google account with a player asks, then switches and merges', (
    tester,
  ) async {
    backend.nextResult = SignInResult.needsSwitch;
    backend.existing = const CloudProfile(
      name: 'Chandu',
      counters: {'games': 30, 'xp': 2000},
      badges: {'regular'},
    );
    prefs.activeRoomId = 'guestRoom';
    await pump(tester, const ProfileScreen());
    await tapText(tester, 'Sign in with Google');
    expect(find.text('Use your saved profile?'), findsOneWidget);

    await tapText(tester, 'Switch');
    expect(backend.calls, ['signInWithGoogle', 'switchToExisting', 'sync']);
    expect(userChanges, ['before', 'after']);
    expect(prefs.activeRoomId, isNull);
    expect(prefs.playerName, 'Chandu');
    expect(prefs.stats.counters['games'], 30);
    // This phone's badge joins the saved player's.
    expect(backend.cloud.badges, containsAll(['first_game', 'regular']));
    expect(
      find.text('Welcome back! Your profiles are combined.'),
      findsOneWidget,
    );
  });

  testWidgets('declining the switch stays a guest', (tester) async {
    backend.nextResult = SignInResult.needsSwitch;
    await pump(tester, const ProfileScreen());
    await tapText(tester, 'Sign in with Google');
    await tapText(tester, 'Cancel');
    expect(backend.calls, ['signInWithGoogle', 'cancelSwitch']);
    expect(find.text('Playing as a guest'), findsOneWidget);
    expect(prefs.stats.counters['games'], 1);
  });

  testWidgets('signing out saves first, then starts a fresh guest', (
    tester,
  ) async {
    backend.google = FakeAccountBackend.profile;
    await pump(tester, const ProfileScreen());
    expect(find.text('Signed in'), findsOneWidget);
    await tapText(tester, 'Sign out');
    expect(find.text('Sign out?'), findsOneWidget);
    await tapText(tester, 'Sign out');

    expect(backend.calls, ['sync', 'signOut']);
    expect(userChanges, ['before', 'after']);
    expect(backend.cloud.counters['games'], 1);
    expect(prefs.stats.counters, isEmpty);
    expect(prefs.playerName, 'Chandra');
    expect(find.text('Playing as a guest'), findsOneWidget);
  });

  testWidgets('delete my account asks, then deletes everything', (
    tester,
  ) async {
    backend.google = FakeAccountBackend.profile;
    prefs.addHistory(
      MatchRecord(
        key: 'r1-1',
        playedAt: DateTime(2026, 11, 19),
        rounds: 3,
        category: 'hollywood',
        standings: const [],
      ),
    );
    await pump(tester, const SettingsScreen());
    await tapText(tester, 'Delete my account and data');
    expect(find.text('Delete your account and data?'), findsOneWidget);
    await tapText(tester, 'Cancel');
    expect(backend.calls, isNot(contains('deleteAccount')));

    await tapText(tester, 'Delete my account and data');
    await tapText(tester, 'Delete');
    expect(backend.calls, contains('deleteAccount'));
    expect(userChanges, ['before', 'after']);
    expect(prefs.stats.counters, isEmpty);
    expect(prefs.history, isEmpty);
    expect(prefs.playerName, '');
    expect(find.text('Your account and data were deleted.'), findsOneWidget);
    expect(find.text('Playing as a guest'), findsOneWidget);
  });

  testWidgets('guests can delete their data from Settings too', (tester) async {
    await pump(tester, const SettingsScreen());
    await scrollTo(tester, 'Playing as a guest');
    expect(find.text('Playing as a guest'), findsOneWidget);
    await tapText(tester, 'Delete my account and data');
    await tapText(tester, 'Delete');
    expect(backend.calls, ['deleteAccount']);
    expect(prefs.stats.counters, isEmpty);
  });
}
