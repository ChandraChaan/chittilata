import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/services/feedback.dart';
import 'core/services/preferences.dart';
import 'data/game_repository.dart';
import 'firebase_options.dart';

/// Debug and profile builds can play against local Firebase emulators
/// (`cd functions && npm run serve`), e.g. with bots from
/// `scripts/bots.mjs --emulator`:
///   flutter run --dart-define=USE_EMULATOR=true
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_useEmulator && !kReleaseMode) {
    const host = '10.0.2.2'; // the dev machine, seen from an Android emulator
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(
      region: 'asia-south1',
    ).useFunctionsEmulator(host, 5001);
  }

  // Crash reporting: only collected from release builds. Reports carry stack
  // traces only; we never attach card names, hands, room codes or names.
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await Preferences.load();
  runApp(
    ChittilataApp(
      services: AppServices(
        repo: FirebaseGameRepository(),
        prefs: prefs,
        feedback: GameFeedback(prefs),
      ),
    ),
  );
}
