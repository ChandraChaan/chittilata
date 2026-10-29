import 'package:flutter/material.dart';

import 'core/services/feedback.dart';
import 'core/services/preferences.dart';
import 'core/theme/app_theme.dart';
import 'data/game_repository.dart';
import 'ui/screens/splash_screen.dart';

/// App-wide dependencies, provided to the widget tree.
class AppServices {
  AppServices({
    required this.repo,
    required this.prefs,
    required this.feedback,
  });
  final GameRepository repo;
  final Preferences prefs;
  final GameFeedback feedback;
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

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
        builder: (context, _) => MaterialApp(
          title: 'Chittilata',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: switch (services.prefs.themeMode) {
            'light' => ThemeMode.light,
            'system' => ThemeMode.system,
            _ => ThemeMode.dark,
          },
          home: home ?? const SplashScreen(),
        ),
      ),
    );
  }
}

/// Fade+slide page route used for every screen change.
Route<T> gameRoute<T>(Widget page) => PageRouteBuilder<T>(
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
