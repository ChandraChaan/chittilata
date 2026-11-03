import 'package:flutter/material.dart';

import 'core/services/feedback.dart';
import 'core/services/invite_links.dart';
import 'core/services/push.dart';
import 'core/services/preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/festivals.dart';
import 'data/game_repository.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/widgets/update_gate.dart';

/// App-wide dependencies, provided to the widget tree.
class AppServices {
  AppServices({
    required this.repo,
    required this.prefs,
    required this.feedback,
    InviteLinks? invites,
    this.push,
  }) : invites = invites ?? InviteLinks();
  final GameRepository repo;
  final Preferences prefs;
  final GameFeedback feedback;
  final InviteLinks invites;

  /// Null in tests (no Firebase Messaging there).
  final PushService? push;
}

/// For opening a room from a tapped notification.
final navigatorKey = GlobalKey<NavigatorState>();

/// Lets screens know when they come back to the top (e.g. home after a game).
final routeObserver = RouteObserver<ModalRoute<void>>();

/// Shows messages from anywhere, even when no screen has its own context.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  /// For callbacks: looks the services up without subscribing to changes.
  static AppServices read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services old) => old.services != services;
}

class ChittilataApp extends StatelessWidget {
  const ChittilataApp({super.key, required this.services, this.home});
  final AppServices services;

  /// Overrides the first screen (used by tests).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return Services(
      services: services,
      child: ListenableBuilder(
        listenable: services.prefs,
        builder: (context, _) =>
            _app(Festival.chosen(services.prefs.festival, DateTime.now())),
      ),
    );
  }

  Widget _app(Festival? festival) => MaterialApp(
    title: 'Chittilata – ChitPlay',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light, festival: festival),
    darkTheme: buildTheme(Brightness.dark, festival: festival),
    themeMode: switch (services.prefs.themeMode) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    },
    scaffoldMessengerKey: scaffoldMessengerKey,
    navigatorKey: navigatorKey,
    navigatorObservers: [services.feedback.navigatorObserver, routeObserver],
    home: home ?? const SplashScreen(),
    builder: (context, child) => UpdateGate(child: child!),
  );
}

/// Fade+slide page route used for every screen change.
Route<T> gameRoute<T>(Widget page, {String? name}) => PageRouteBuilder<T>(
  settings: RouteSettings(name: name),
  transitionDuration: Motion.medium,
  reverseTransitionDuration: Motion.fast,
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (context, anim, _, child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final curved = CurvedAnimation(parent: anim, curve: Motion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);
