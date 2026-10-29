import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/services/feedback.dart';
import '../core/services/preferences.dart';
import '../data/game_repository.dart';
import '../data/models.dart';

enum Phase {
  loading,
  lobby,
  intro,
  exchange,
  characters,
  results,
  aborted,
  finished,
  closed,
  removed,
}

/// Server-matching grace after a deadline (see DEADLINE_GRACE_MS on server).
const _graceMs = 1000;

/// Owns every live subscription for one room and turns the server's
/// authoritative documents into UI state. It never decides game outcomes;
/// it only asks the server to act (pass, timeout, reveal).
class RoomController extends ChangeNotifier with WidgetsBindingObserver {
  RoomController({
    required this.repo,
    required this.roomId,
    required this.prefs,
    required this.feedback,
  }) {
    WidgetsBinding.instance.addObserver(this);
    _roomSub = repo.watchRoom(roomId).listen(_onRoom, onError: _onStreamError);
    _handSub = repo.watchHand(roomId).listen(_onHand, onError: (_) {});
    _presenceSub = repo.watchPresence(roomId).listen((p) {
      presence = p;
      notifyListeners();
    }, onError: (_) {});
    _connSub = repo.watchConnected(roomId).listen((c) {
      if (c != connected) {
        connected = c;
        notifyListeners();
      }
    }, onError: (_) {});
    _beat();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _beat());
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  final GameRepository repo;
  final String roomId;
  final Preferences prefs;
  final GameFeedback feedback;

  Room? room;
  Round? round;
  Hand? _hand;
  Map<String, Presence> presence = {};
  bool connected = true;
  bool roomMissing = false;
  String? selectedCardId;
  bool busy = false;

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<Round?>? _roundSub;
  StreamSubscription<Hand?>? _handSub;
  StreamSubscription<Map<String, Presence>>? _presenceSub;
  StreamSubscription<bool>? _connSub;
  Timer? _heartbeat;
  Timer? _ticker;
  String? _watchingRoundKey;
  final _claimedTimeouts = <String>{};
  final _claimedReveals = <String>{};
  int _lastWarnSecond = -1;
  String? _lastActionKey;
  String? _lastWinnerKey;
  bool _foreground = true;
  bool _disposed = false;
  final _rand = Random();

  String? get uid => repo.uid;
  bool get isHost => room?.hostUid == uid;

  /// Server-aligned "now".
  DateTime get now => DateTime.now().add(repo.clockOffset);

  /// The private hand, but only if it belongs to the round on screen.
  Hand? get hand =>
      (_hand != null && round != null && _hand!.roundKey == round!.key)
      ? _hand
      : null;

  bool get myTurn =>
      phase == Phase.exchange && round?.currentUid == uid && hand != null;

  Phase get phase {
    final r = room;
    if (roomMissing) return Phase.closed;
    if (r == null) return Phase.loading;
    if (r.status == RoomStatus.closed) return Phase.closed;
    if (uid != null && !r.memberUids.contains(uid)) return Phase.removed;
    if (r.status == RoomStatus.lobby) return Phase.lobby;
    if (r.status == RoomStatus.finished) return Phase.finished;
    final rd = round;
    if (rd == null || rd.key != r.currentRoundKey) return Phase.loading;
    return switch (rd.status) {
      RoundStatus.exchange =>
        now.isBefore(rd.introEndsAt) ? Phase.intro : Phase.exchange,
      RoundStatus.characters => Phase.characters,
      RoundStatus.revealed => Phase.results,
      RoundStatus.aborted => Phase.aborted,
    };
  }

  /// Milliseconds left on the current turn (negative once expired).
  int get turnRemainingMs {
    final rd = round;
    if (rd == null) return 0;
    return rd.turnDeadline.difference(now).inMilliseconds;
  }

  double get turnProgress {
    final rd = round;
    if (rd == null || rd.turnSeconds == 0) return 0;
    return (turnRemainingMs / (rd.turnSeconds * 1000)).clamp(0.0, 1.0);
  }

  int get introRemainingSeconds {
    final rd = round;
    if (rd == null) return 0;
    return max(
      0,
      (rd.introEndsAt.difference(now).inMilliseconds / 1000).ceil(),
    );
  }

  int get revealRemainingSeconds {
    final at = round?.revealAt;
    if (at == null) return 0;
    return max(0, (at.difference(now).inMilliseconds / 1000).ceil());
  }

  bool isOnline(String playerUid) {
    if (playerUid == uid) return connected;
    final p = presence[playerUid];
    if (p?.lastSeen == null) return false;
    return now.difference(p!.lastSeen!).inSeconds < 60 &&
        p.state == 'foreground';
  }

  bool isAway(String playerUid) {
    final p = presence[playerUid];
    return p != null &&
        p.state == 'background' &&
        p.lastSeen != null &&
        now.difference(p.lastSeen!).inSeconds < 60;
  }

  // ---------- streams ----------

  void _onRoom(Room? r) {
    if (r == null) {
      roomMissing = true;
      notifyListeners();
      return;
    }
    final previous = room;
    room = r;
    final key = r.currentRoundKey;
    if (key != null && key != _watchingRoundKey) {
      _watchingRoundKey = key;
      _roundSub?.cancel();
      round = null;
      selectedCardId = null;
      _roundSub = repo
          .watchRound(roomId, key)
          .listen(_onRound, onError: (_) {});
    }
    if (r.status == RoomStatus.finished &&
        previous?.status != RoomStatus.finished) {
      feedback.play(Sfx.fanfare);
      feedback.heavy();
      _saveHistory(r);
    }
    if (r.status == RoomStatus.closed || !r.memberUids.contains(uid)) {
      prefs.activeRoomId = null;
    }
    notifyListeners();
  }

  void _onRound(Round? rd) {
    if (rd == null) return;
    final prev = round;
    round = rd;
    if (prev?.turnId != rd.turnId) {
      selectedCardId = null;
      _lastWarnSecond = -1;
    }
    final la = rd.lastAction;
    final laKey = la == null ? null : '${rd.key}:${la.turnId}';
    if (la != null && laKey != _lastActionKey && prev != null) {
      _lastActionKey = laKey;
      if (la.isTimeout) {
        feedback.play(Sfx.timeout);
        _messages.add(
          la.fromUid == uid
              ? "Time's up! A card was passed for you."
              : "Time's up for ${room?.nameOf(la.fromUid)} — a card was auto-passed.",
        );
      } else if (la.fromUid != uid && la.toUid != uid) {
        feedback.play(Sfx.tap);
      }
    } else {
      _lastActionKey ??= laKey;
    }
    final winKey = rd.winner == null ? null : rd.key;
    if (winKey != null && winKey != _lastWinnerKey) {
      _lastWinnerKey = winKey;
      if (prev != null) {
        feedback.play(Sfx.win);
        feedback.heavy();
      }
    }
    if (rd.status == RoundStatus.revealed &&
        prev?.status != RoundStatus.revealed &&
        prev != null) {
      feedback.play(Sfx.roundEnd);
    }
    notifyListeners();
  }

  void _onHand(Hand? h) {
    final prev = _hand;
    _hand = h;
    if (h != null &&
        h.incomingCardId != null &&
        h.incomingCardId != prev?.incomingCardId &&
        prev?.roundKey == h.roundKey) {
      feedback.play(Sfx.receive);
      feedback.light();
    }
    if (h?.character != null && prev?.character == null) {
      feedback.play(Sfx.reveal);
      feedback.medium();
    }
    notifyListeners();
  }

  void _onStreamError(Object e) {
    // Permission denied means we are no longer a member (removed or closed).
    roomMissing = true;
    prefs.activeRoomId = null;
    notifyListeners();
  }

  // ---------- timers ----------

  void _tick() {
    final rd = round;
    final p = phase;
    if (rd != null && p == Phase.exchange) {
      final ms = turnRemainingMs;
      if (myTurn && rd.timed) {
        final s = (ms / 1000).ceil();
        if (s <= 5 && s > 0 && s != _lastWarnSecond) {
          _lastWarnSecond = s;
          feedback.play(Sfx.tick);
          if (s <= 3) feedback.warning();
        }
      }
      _maybeClaimTimeout(rd, ms);
    }
    if (rd != null && p == Phase.characters) _maybeReveal(rd);
    if (p == Phase.intro || p == Phase.exchange || p == Phase.characters) {
      notifyListeners();
    }
  }

  /// Any client may ask the server to apply an expired turn. The player after
  /// the stuck one asks first; others stagger so calls rarely collide.
  void _maybeClaimTimeout(Round rd, int remainingMs) {
    final idx = rd.order.indexOf(uid ?? '');
    final stagger = rd.nextUid == uid ? 300 : 1500 + max(0, idx) * 400;
    if (remainingMs > -(_graceMs + stagger)) return;
    final key = '${rd.key}:${rd.turnId}';
    if (!_claimedTimeouts.add(key)) return;
    repo.claimTimeout(roomId, rd.key, rd.turnId).catchError((_) {});
  }

  void _maybeReveal(Round rd) {
    final at = rd.revealAt;
    if (at == null) return;
    final idx = max(0, rd.order.indexOf(uid ?? ''));
    if (now.isBefore(at.add(Duration(milliseconds: 200 + idx * 500)))) return;
    if (!_claimedReveals.add(rd.key)) return;
    repo.revealRound(roomId, rd.key).catchError((_) {
      _claimedReveals.remove(rd.key);
    });
  }

  void _beat() {
    if (_disposed) return;
    repo.heartbeat(roomId, foreground: _foreground).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg != _foreground) {
      _foreground = fg;
      _beat();
    }
  }

  // ---------- actions ----------

  void select(String cardId) {
    if (!myTurn || busy) return;
    selectedCardId = selectedCardId == cardId ? null : cardId;
    feedback.selection();
    feedback.play(Sfx.select);
    notifyListeners();
  }

  Future<void> passSelected() async {
    final rd = round;
    final cardId = selectedCardId;
    if (rd == null || cardId == null || !myTurn || busy) return;
    busy = true;
    notifyListeners();
    final requestId =
        '$uid-${rd.key}-${rd.turnId}-${_rand.nextInt(1 << 32).toRadixString(36)}';
    feedback.medium();
    feedback.play(Sfx.pass);
    try {
      await _withRetry(
        () => repo.passCard(roomId, rd.key, rd.turnId, cardId, requestId),
      );
    } on GameException catch (e) {
      _messages.add(e.message);
    } finally {
      busy = false;
      selectedCardId = null;
      notifyListeners();
    }
  }

  /// Retries once on transient failures; the server dedupes by requestId.
  Future<void> _withRetry(Future<void> Function() f) async {
    try {
      await f();
    } on GameException catch (e) {
      if (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal') {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await f();
      } else {
        rethrow;
      }
    }
  }

  Future<bool> run(Future<void> Function() action) async {
    if (busy) return false;
    busy = true;
    notifyListeners();
    try {
      await action();
      return true;
    } on GameException catch (e) {
      _messages.add(e.message);
      return false;
    } catch (e) {
      _messages.add('Network problem. Check your connection and try again.');
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> setReady(bool v) => run(() => repo.setReady(roomId, v));
  Future<bool> updateSettings(Map<String, Object?> patch) =>
      run(() => repo.updateSettings(roomId, patch));
  Future<bool> kick(String player) =>
      run(() => repo.kickPlayer(roomId, player));
  Future<bool> startGame() => run(() => repo.startGame(roomId));
  Future<bool> nextRound() => run(() => repo.nextRound(roomId));
  Future<bool> revealNow() => run(() => repo.revealRound(roomId, round!.key));
  Future<bool> playAgain() => run(() => repo.playAgain(roomId));

  Future<void> leave() async {
    try {
      await repo.leaveRoom(roomId);
    } catch (_) {
      // Leaving locally still succeeds; the server will expire stale rooms.
    }
    prefs.activeRoomId = null;
  }

  void _saveHistory(Room r) {
    final standings = r.finalStandings;
    if (standings == null) return;
    prefs.addHistory(
      MatchRecord(
        key: '${r.id}-${r.gameNo}',
        playedAt: DateTime.now(),
        rounds: r.currentRound,
        category: r.settings.category.name,
        standings: standings.map((s) => s.toJson()).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _roomSub?.cancel();
    _roundSub?.cancel();
    _handSub?.cancel();
    _presenceSub?.cancel();
    _connSub?.cancel();
    _heartbeat?.cancel();
    _ticker?.cancel();
    _messages.close();
    super.dispose();
  }
}
