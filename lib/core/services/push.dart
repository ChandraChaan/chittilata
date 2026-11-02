import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../data/game_repository.dart';
import 'preferences.dart';

/// "Your turn" and nudge notifications. The server only sends them while
/// this phone isn't showing the game; this class just registers the phone.
// Registration tokens (not the newer installation-ID API) because the server
// sends with firebase-admin's token-based sendEach.
// ignore_for_file: deprecated_member_use

class PushService {
  PushService(this._repo, this._prefs, {FirebaseMessaging? messaging})
    : _messagingOverride = messaging;

  final GameRepository _repo;
  final Preferences _prefs;
  final FirebaseMessaging? _messagingOverride;
  StreamSubscription<String>? _refresh;
  bool _asked = false;

  FirebaseMessaging get _fm => _messagingOverride ?? FirebaseMessaging.instance;

  /// Called on entering a room: asks for permission once (Android 13+
  /// shows a system prompt) and saves this phone's token.
  Future<void> enable() async {
    if (!_prefs.notifications || _asked) return;
    _asked = true;
    try {
      final settings = await _fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await _fm.getToken();
      if (token != null) await _repo.savePushToken(token);
      _refresh ??= _fm.onTokenRefresh.listen(
        (t) => _repo.savePushToken(t).catchError((_) {}),
      );
    } catch (e) {
      debugPrint('push unavailable: $e');
    }
  }

  /// Settings switch: off removes the token so the server can't reach us.
  Future<void> setEnabled(bool on) async {
    _prefs.notifications = on;
    if (on) {
      _asked = false;
      await enable();
    } else {
      _asked = false;
      await _refresh?.cancel();
      _refresh = null;
      try {
        await _repo.deletePushToken();
        await _fm.deleteToken();
      } catch (e) {
        debugPrint('push disable failed: $e');
      }
    }
  }

  /// The room a tapped notification belongs to (app opened from it).
  Stream<String> get openedRooms async* {
    try {
      final first = await _fm.getInitialMessage();
      final id = first?.data['roomId'];
      if (id is String) yield id;
      yield* FirebaseMessaging.onMessageOpenedApp
          .map((m) => m.data['roomId'])
          .where((id) => id is String)
          .cast<String>();
    } catch (_) {}
  }
}
