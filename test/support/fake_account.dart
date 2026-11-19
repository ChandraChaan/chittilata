import 'package:chittilata/core/services/account.dart';
import 'package:chittilata/core/services/cloud_profile.dart';

/// In-memory sign-in and cloud profile for widget tests. [cloud] is what
/// the server stores for the Google player; [nextResult] is what the next
/// Google sign-in does.
class FakeAccountBackend implements AccountBackend {
  FakeAccountBackend({this.google, this.cloud = const CloudProfile()});

  @override
  GoogleProfile? google;
  CloudProfile cloud;

  /// The profile the Google account's existing player has (needsSwitch).
  CloudProfile existing = const CloudProfile();
  SignInResult nextResult = SignInResult.linked;
  AccountException? failNext;
  final calls = <String>[];

  static const profile = GoogleProfile(
    email: 'player@example.com',
    name: 'Test Player',
  );

  void _maybeFail() {
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  @override
  Future<SignInResult> signInWithGoogle() async {
    calls.add('signInWithGoogle');
    _maybeFail();
    if (nextResult == SignInResult.linked) google = profile;
    return nextResult;
  }

  @override
  Future<void> switchToExisting() async {
    calls.add('switchToExisting');
    _maybeFail();
    google = profile;
    cloud = existing;
  }

  @override
  Future<void> cancelSwitch() async => calls.add('cancelSwitch');

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _maybeFail();
    google = null;
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    _maybeFail();
    google = null;
    cloud = const CloudProfile();
  }

  @override
  Future<CloudProfile> syncProfile(
    CloudProfile mine, {
    bool preferMine = false,
  }) async {
    calls.add('sync');
    cloud = mine.merge(cloud, preferMine: preferMine);
    return cloud;
  }
}
