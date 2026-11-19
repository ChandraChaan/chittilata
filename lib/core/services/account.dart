import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'cloud_profile.dart';
import 'preferences.dart';

/// The Google account a player signed in with.
class GoogleProfile {
  const GoogleProfile({this.email, this.name});
  final String? email;
  final String? name;
}

enum SignInResult {
  /// This phone's player is now linked to the Google account (same uid,
  /// rooms and groups kept).
  linked,

  /// The Google account already has a ChitPlay profile: call
  /// [Account.switchToExisting] (after asking) or [Account.cancelSwitch].
  needsSwitch,

  /// The player closed the Google sheet.
  cancelled,
}

/// A user-facing account error.
class AccountException implements Exception {
  AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sign-in, the cloud profile and account deletion. Firebase in production,
/// an in-memory fake in tests.
abstract class AccountBackend {
  /// Null while playing as a guest (anonymous).
  GoogleProfile? get google;

  /// Links the current (anonymous) player to a Google account.
  Future<SignInResult> signInWithGoogle();

  /// After [SignInResult.needsSwitch]: removes this phone's guest player
  /// (leaving its rooms and groups) and signs in to the Google account's
  /// existing player.
  Future<void> switchToExisting();

  /// Forgets a pending switch.
  Future<void> cancelSwitch();

  /// Signs out of Google and continues as a new guest.
  Future<void> signOut();

  /// Deletes the cloud profile and the account on the server (leaving rooms
  /// and groups), then continues as a new guest.
  Future<void> deleteAccount();

  /// Merges [mine] into the stored profile and returns the result.
  Future<CloudProfile> syncProfile(CloudProfile mine, {bool preferMine});
}

/// What the UI uses: wraps the backend and keeps this phone's profile and
/// the cloud copy in step while signed in with Google. Guests never touch
/// the cloud profile.
class Account extends ChangeNotifier {
  Account(
    this._backend,
    this._prefs, {
    this.beforeUserChange,
    this.afterUserChange,
    this.syncDelay = const Duration(seconds: 3),
  });

  final AccountBackend _backend;
  final Preferences _prefs;

  /// Runs while still signed in as the old player (e.g. drop its push token).
  final Future<void> Function()? beforeUserChange;

  /// Runs once signed in as the new player (e.g. register the push token).
  final Future<void> Function()? afterUserChange;
  final Duration syncDelay;

  Timer? _timer;
  bool _started = false;
  bool _identityChanged = false;
  bool _busy = false;

  GoogleProfile? get google => _backend.google;
  bool get signedIn => google != null;

  /// A sign-in, sign-out or deletion is in progress.
  bool get busy => _busy;

  /// Starts syncing profile changes (call once, after sign-in at launch).
  void start() {
    if (_started) return;
    _started = true;
    _prefs.onProfileChanged = ({bool identity = false}) {
      if (!signedIn) return;
      _identityChanged |= identity;
      _timer?.cancel();
      _timer = Timer(syncDelay, () => unawaited(sync()));
    };
    if (signedIn) unawaited(sync());
  }

  /// Merges this phone's profile with the cloud copy, both ways. Failures
  /// (offline) are fine: the next change or launch tries again.
  Future<void> sync() async {
    if (!signedIn) return;
    _timer?.cancel();
    final preferMine = _identityChanged;
    _identityChanged = false;
    try {
      final merged = await _backend.syncProfile(
        CloudProfile.fromPrefs(_prefs),
        preferMine: preferMine,
      );
      _prefs.applyProfile(
        name: merged.name,
        avatar: merged.avatar,
        counters: merged.counters,
        badges: merged.badges,
        seen: merged.seen,
        history: merged.history,
      );
    } catch (e) {
      _identityChanged |= preferMine;
      debugPrint('profile sync failed: $e');
    }
  }

  Future<T> _run<T>(Future<T> Function() f) async {
    _busy = true;
    notifyListeners();
    try {
      return await f();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<SignInResult> signInWithGoogle() => _run(() async {
    final r = await _backend.signInWithGoogle();
    if (r == SignInResult.linked) await sync();
    return r;
  });

  Future<void> switchToExisting() => _run(() async {
    await beforeUserChange?.call();
    await _backend.switchToExisting();
    // The guest's rooms belong to the guest; its stats come along.
    _prefs.activeRoomId = null;
    await sync();
    await afterUserChange?.call();
  });

  Future<void> cancelSwitch() => _backend.cancelSwitch();

  Future<void> signOut() => _run(() async {
    _timer?.cancel();
    // Save anything not yet synced: it's about to leave this phone.
    await sync();
    await beforeUserChange?.call();
    await _backend.signOut();
    _prefs.clearProfile();
    await afterUserChange?.call();
  });

  Future<void> deleteAccount() => _run(() async {
    _timer?.cancel();
    await beforeUserChange?.call();
    await _backend.deleteAccount();
    _prefs.clearProfile(identity: true);
    await afterUserChange?.call();
  });

  @override
  void dispose() {
    _timer?.cancel();
    _prefs.onProfileChanged = null;
    super.dispose();
  }
}

class FirebaseAccountBackend implements AccountBackend {
  FirebaseAccountBackend({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = db ?? FirebaseFirestore.instance,
       _fn = functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       _gsi = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;
  final GoogleSignIn _gsi;
  Future<void>? _initialized;
  AuthCredential? _pending;

  // The web client id comes from google-services.json.
  Future<void> _ready() => _initialized ??= _gsi.initialize();

  @override
  GoogleProfile? get google {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    final g = u.providerData
        .where((p) => p.providerId == GoogleAuthProvider.PROVIDER_ID)
        .firstOrNull;
    if (g == null) return null;
    return GoogleProfile(
      email: g.email ?? u.email,
      name: g.displayName ?? u.displayName,
    );
  }

  @override
  Future<SignInResult> signInWithGoogle() async {
    final AuthCredential cred;
    try {
      await _ready();
      final account = await _gsi.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw AccountException('Google sign-in did not finish. Try again.');
      }
      cred = GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return SignInResult.cancelled;
      }
      debugPrint('google sign-in failed: ${e.code} ${e.description}');
      throw AccountException('Google sign-in is not available right now.');
    }
    final user = _auth.currentUser;
    try {
      if (user == null) {
        await _auth.signInWithCredential(cred);
      } else {
        await user.linkWithCredential(cred);
      }
      return SignInResult.linked;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'credential-already-in-use':
          _pending = e.credential ?? cred;
          return SignInResult.needsSwitch;
        case 'provider-already-linked':
          return SignInResult.linked;
        case 'network-request-failed':
          throw AccountException('No internet. Try again when online.');
      }
      debugPrint('link failed: ${e.code}');
      await _signOutGoogle();
      throw AccountException('Could not sign in. Please try again.');
    }
  }

  @override
  Future<void> switchToExisting() async {
    final cred = _pending;
    if (cred == null) throw AccountException('Sign in with Google again.');
    _pending = null;
    // The guest player is left behind for good: clean it up first.
    await _deleteOnServer();
    try {
      await _auth.signInWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      debugPrint('switch failed: ${e.code}');
      await _auth.signOut();
      await _auth.signInAnonymously();
      await _signOutGoogle();
      throw AccountException('Could not sign in. Please try again.');
    }
  }

  @override
  Future<void> cancelSwitch() async {
    _pending = null;
    await _signOutGoogle();
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    await _signOutGoogle();
    await _auth.signInAnonymously();
  }

  @override
  Future<void> deleteAccount() async {
    await _deleteOnServer();
    await _auth.signOut();
    try {
      await _ready();
      await _gsi.disconnect();
    } catch (_) {
      await _signOutGoogle();
    }
    await _auth.signInAnonymously();
  }

  Future<void> _deleteOnServer() async {
    try {
      await _fn
          .httpsCallable(
            'deleteAccount',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          )
          .call<Map<String, dynamic>>({});
    } on FirebaseFunctionsException catch (e) {
      throw AccountException(
        e.code == 'unavailable'
            ? 'No internet. Try again when online.'
            : (e.message ?? 'Something went wrong. Please try again.'),
      );
    }
  }

  Future<void> _signOutGoogle() async {
    try {
      await _ready();
      await _gsi.signOut();
    } catch (_) {}
  }

  @override
  Future<CloudProfile> syncProfile(
    CloudProfile mine, {
    bool preferMine = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || google == null) return mine;
    final ref = _db.doc('users/$uid');
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      final cloud = data == null
          ? const CloudProfile()
          : CloudProfile.fromMap(data);
      final merged = mine.merge(cloud, preferMine: preferMine);
      if (data == null || !merged.sameAs(cloud)) {
        tx.set(ref, {
          ...merged.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return merged;
    });
  }
}
