import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';

/// A user-facing error from the game server.
class GameException implements Exception {
  GameException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Presence snapshot for one player.
class Presence {
  const Presence(this.lastSeen, this.state);
  final DateTime? lastSeen;
  final String state;
}

/// Everything the UI needs from the backend. Implemented by Firebase in
/// production and by an in-memory fake in widget tests.
abstract class GameRepository {
  String? get uid;
  Future<String> signIn();

  /// Server time minus local time, refined after every server call.
  Duration get clockOffset;

  Stream<Room?> watchRoom(String roomId);
  Stream<Round?> watchRound(String roomId, String roundKey);
  Stream<Hand?> watchHand(String roomId);
  Stream<Map<String, Presence>> watchPresence(String roomId);
  Stream<bool> watchConnected(String roomId);
  Future<List<Round>> loadRounds(String roomId, int gameNo);
  Future<void> heartbeat(String roomId, {required bool foreground});

  Future<({String roomId, String code})> createRoom(String name);
  Future<({String roomId, String code})> joinRoom(String code, String name);
  Future<void> setReady(String roomId, bool ready);
  Future<void> updateSettings(String roomId, Map<String, Object?> patch);
  Future<void> kickPlayer(String roomId, String uid);
  Future<void> leaveRoom(String roomId);
  Future<void> startGame(String roomId);
  Future<void> nextRound(String roomId);
  Future<void> passCard(
    String roomId,
    String roundKey,
    int turnId,
    String cardId,
    String requestId,
  );
  Future<void> claimTimeout(String roomId, String roundKey, int turnId);

  /// Picks a folded movie chit; returns the slip it revealed (yours only).
  Future<GameCard> pickChit(String roomId, String roundKey, String chitId);
  Future<void> autoPickChits(String roomId, String roundKey);

  /// Picks a folded character chit; returns the sealed character.
  Future<CharacterDef> pickCharacter(
    String roomId,
    String roundKey,
    String chitId,
  );
  Future<void> autoPickCharacters(String roomId, String roundKey);
  Future<void> revealRound(String roomId, String roundKey);
  Future<void> playAgain(String roomId);
  Future<void> tiebreakVote(String roomId, bool accept);
  Future<void> resolveTiebreakVote(String roomId);
}

class FirebaseGameRepository implements GameRepository {
  FirebaseGameRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = db ?? FirebaseFirestore.instance,
       _fn = functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;
  Duration _offset = Duration.zero;
  int _bestRtt = 1 << 30;

  @override
  String? get uid => _auth.currentUser?.uid;

  @override
  Duration get clockOffset => _offset;

  @override
  Future<String> signIn() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    unawaited(_call('ping', {}).catchError((_) => <String, dynamic>{}));
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> _room(String id) =>
      _db.collection('rooms').doc(id);

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    final sent = DateTime.now();
    try {
      final res = await _fn
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<Map<String, dynamic>>(data);
      final got = DateTime.now();
      final out = Map<String, dynamic>.from(res.data);
      final serverNow = out['serverNow'];
      final rtt = got.difference(sent).inMilliseconds;
      // Keep the offset measured on the fastest round trip (least skew).
      if (serverNow is num && rtt <= _bestRtt + 150) {
        _bestRtt = min(_bestRtt, rtt);
        final mid = sent.millisecondsSinceEpoch + rtt ~/ 2;
        _offset = Duration(milliseconds: serverNow.toInt() - mid);
      }
      return out;
    } on FirebaseFunctionsException catch (e) {
      throw GameException(e.code, e.message ?? 'Something went wrong.');
    }
  }

  @override
  Stream<Room?> watchRoom(String roomId) => _room(
    roomId,
  ).snapshots().map((s) => s.exists ? Room.fromSnapshot(s) : null);

  @override
  Stream<bool> watchConnected(String roomId) => _room(
    roomId,
  ).snapshots(includeMetadataChanges: true).map((s) => !s.metadata.isFromCache);

  @override
  Stream<Round?> watchRound(String roomId, String roundKey) => _room(roomId)
      .collection('rounds')
      .doc(roundKey)
      .snapshots()
      .map((s) => s.exists ? Round.fromSnapshot(s) : null);

  @override
  Stream<Hand?> watchHand(String roomId) => _room(roomId)
      .collection('hands')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? Hand.fromSnapshot(s) : null);

  @override
  Stream<Map<String, Presence>> watchPresence(String roomId) => _room(roomId)
      .collection('presence')
      .snapshots()
      .map(
        (q) => {
          for (final d in q.docs)
            d.id: Presence(
              (d.data()['lastSeen'] as Timestamp?)?.toDate(),
              d.data()['state'] as String? ?? 'foreground',
            ),
        },
      );

  @override
  Future<List<Round>> loadRounds(String roomId, int gameNo) async {
    final q = await _room(
      roomId,
    ).collection('rounds').where('gameNo', isEqualTo: gameNo).get();
    final rounds = q.docs.map((d) => Round.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.roundNo.compareTo(b.roundNo));
    return rounds;
  }

  @override
  Future<void> heartbeat(String roomId, {required bool foreground}) =>
      _room(roomId).collection('presence').doc(uid).set({
        'lastSeen': FieldValue.serverTimestamp(),
        'state': foreground ? 'foreground' : 'background',
      });

  @override
  Future<({String roomId, String code})> createRoom(String name) async {
    final r = await _call('createRoom', {'name': name});
    return (roomId: r['roomId'] as String, code: r['code'] as String);
  }

  @override
  Future<({String roomId, String code})> joinRoom(
    String code,
    String name,
  ) async {
    final r = await _call('joinRoom', {'code': code, 'name': name});
    return (roomId: r['roomId'] as String, code: r['code'] as String);
  }

  @override
  Future<void> setReady(String roomId, bool ready) =>
      _call('setReady', {'roomId': roomId, 'ready': ready});

  @override
  Future<void> updateSettings(String roomId, Map<String, Object?> patch) =>
      _call('updateSettings', {'roomId': roomId, 'settings': patch});

  @override
  Future<void> kickPlayer(String roomId, String uid) =>
      _call('kickPlayer', {'roomId': roomId, 'uid': uid});

  @override
  Future<void> leaveRoom(String roomId) =>
      _call('leaveRoom', {'roomId': roomId});

  @override
  Future<void> startGame(String roomId) =>
      _call('startGame', {'roomId': roomId});

  @override
  Future<void> nextRound(String roomId) =>
      _call('nextRound', {'roomId': roomId});

  @override
  Future<void> passCard(
    String roomId,
    String roundKey,
    int turnId,
    String cardId,
    String requestId,
  ) => _call('passCard', {
    'roomId': roomId,
    'roundKey': roundKey,
    'turnId': turnId,
    'cardId': cardId,
    'requestId': requestId,
  });

  @override
  Future<void> claimTimeout(String roomId, String roundKey, int turnId) =>
      _call('claimTimeout', {
        'roomId': roomId,
        'roundKey': roundKey,
        'turnId': turnId,
      });

  @override
  Future<GameCard> pickChit(
    String roomId,
    String roundKey,
    String chitId,
  ) async {
    final r = await _call('pickChit', {
      'roomId': roomId,
      'roundKey': roundKey,
      'chitId': chitId,
    });
    return GameCard.fromMap(r['card']);
  }

  @override
  Future<void> autoPickChits(String roomId, String roundKey) =>
      _call('autoPickChits', {'roomId': roomId, 'roundKey': roundKey});

  @override
  Future<CharacterDef> pickCharacter(
    String roomId,
    String roundKey,
    String chitId,
  ) async {
    final r = await _call('pickCharacter', {
      'roomId': roomId,
      'roundKey': roundKey,
      'chitId': chitId,
    });
    return CharacterDef.fromMap(r['character']);
  }

  @override
  Future<void> autoPickCharacters(String roomId, String roundKey) =>
      _call('autoPickCharacters', {'roomId': roomId, 'roundKey': roundKey});

  @override
  Future<void> revealRound(String roomId, String roundKey) =>
      _call('revealRound', {'roomId': roomId, 'roundKey': roundKey});

  @override
  Future<void> playAgain(String roomId) =>
      _call('playAgain', {'roomId': roomId});

  @override
  Future<void> tiebreakVote(String roomId, bool accept) =>
      _call('tiebreakVote', {'roomId': roomId, 'accept': accept});

  @override
  Future<void> resolveTiebreakVote(String roomId) =>
      _call('resolveTiebreakVote', {'roomId': roomId});
}
