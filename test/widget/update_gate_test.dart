import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/app_updater.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/app_config.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
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
    repo = FakeGameRepository();
    AppUpdater.currentBuild = () async => 6;
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
        home: const HomeScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('no config: nothing is shown', (tester) async {
    await pump(tester);
    expect(find.text('Update required'), findsNothing);
    expect(find.text('New version available'), findsNothing);
  });

  testWidgets('an older build than minBuild is blocked until it updates', (
    tester,
  ) async {
    await pump(tester);
    repo.appConfig.add(const AppConfig(minBuild: 7, message: 'Big fixes.'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Big fixes.'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    // The home screen underneath can't be used.
    await tester.tap(find.text('Join with a code'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Join a room'), findsNothing);

    // Lowering the requirement (or installing the update) lets them in.
    repo.appConfig.add(const AppConfig(minBuild: 6));
    await tester.pump();
    await tester.pump();
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets('a newer latestBuild is offered once and can be dismissed', (
    tester,
  ) async {
    await pump(tester);
    repo.appConfig.add(const AppConfig(latestBuild: 7));
    await tester.pump();
    await tester.pump();
    expect(find.text('New version available'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('New version available'), findsNothing);
    expect(prefs.dismissedUpdate, 7);

    // The same version isn't offered again; a newer one is.
    repo.appConfig.add(const AppConfig(latestBuild: 7));
    await tester.pump();
    await tester.pump();
    expect(find.text('New version available'), findsNothing);
    repo.appConfig.add(const AppConfig(latestBuild: 8));
    await tester.pump();
    await tester.pump();
    expect(find.text('New version available'), findsOneWidget);
  });

  testWidgets('up-to-date builds see nothing', (tester) async {
    await pump(tester);
    repo.appConfig.add(const AppConfig(minBuild: 6, latestBuild: 6));
    await tester.pump();
    await tester.pump();
    expect(find.text('Update required'), findsNothing);
    expect(find.text('New version available'), findsNothing);
  });

  test('config parsing tolerates missing and odd values', () {
    expect(AppConfig.fromMap(null).minBuild, 0);
    final c = AppConfig.fromMap({
      'minBuild': '6',
      'latestBuild': 7.0,
      'message': '  ',
      'updateUrl': 'https://example.com',
    });
    expect(c.minBuild, 6);
    expect(c.latestBuild, 7);
    expect(c.message, isNull);
    expect(c.updateUrl, 'https://example.com');
  });
}
