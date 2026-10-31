import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/services/feedback.dart';
import '../core/services/preferences.dart';
import '../data/chat.dart';
import '../data/game_repository.dart';
import '../data/models.dart';

enum Phase {
  loading,
  lobby,
  picking,
  kqPicking,
  kqGuessing,
  intro,
  exchange,
  characters,
  results,
  aborted,
  tiebreakVote,
  finished,
  closed,
  removed,
}

/// Server-matching grace after a deadline (see DEADLINE_GRACE_MS on server).
const _graceMs = 1000;

/// Others may play for a late player after this much overtime, or once the
/// late player is offline (see PLAY_FOR_AFTER_MS / OFFLINE_AFTER_MS on server).
const playForAfter = Duration(seconds: 45);
const _offlineAfter = Duration(seconds: 45);

/// The players the table is waiting on after their deadline passed.
class LateState {
  const LateState(this.uids, this.deadline);
  final List<String> uids;
  final DateTime deadline;
}

/// A quick-chat message on screen, until it floats away.
class ChatBubble {
  ChatBubble(this.seq, this.event, this.name, this.shownAt);
  final int seq;
  final ChatEvent event;
  final String name;
  final DateTime shownAt;
}

/// Owns every live subscription for one room and turns the server's
/// authoritative documents into UI state. It never decides game outcomes;
/// it only asks the server to act (pass, reveal, or play for a late player
/// when someone at the table chooses to). Nothing is ever played
/// automatically: a late player is buzzed and can be nudged instead.
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
    _chatSub = repo.watchChat(roomId).listen(_onChat, onError: (_) {});
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

  /// Chits I tapped that the server has not confirmed yet.
  final pendingChits = <String>{};

  /// Slips/characters just revealed by my own picks, oldest first; the UI
  /// plays the unfolding reveal and then calls [consumeReveal].
  final revealQueue = <Object>[];

  /// Quick-chat messages currently floating on screen, oldest first.
  final chatFeed = <ChatBubble>[];
  final _seenChat = <String, String>{};
  int _chatSeq = 0;
  DateTime _lastSend = DateTime(0);
  final _lastNudge = <String, DateTime>{};
  StreamSubscription<List<ChatEvent>>? _chatSub;
  String? _lateKey;
  int _lastBuzzSecond = -100;

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<Round?>? _roundSub;
  StreamSubscription<Hand?>? _handSub;
  StreamSubscription<KqRound?>? _kqRoundSub;
  StreamSubscription<KqMyRole?>? _kqRoleSub;

  /// King & Queen: the public round, my secret role, and who I'm about to guess.
  KqRound? kqRound;
  KqMyRole? _kqRole;
  String? kqSelectedTarget;
  StreamSubscription<Map<String, Presence>>? _presenceSub;
  StreamSubscription<bool>? _connSub;
  Timer? _heartbeat;
  Timer? _ticker;
  String? _watchingRoundKey;
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

  /// True while a tie-breaker round is played by others and I only watch.
  bool get spectating =>
      round != null && uid != null && !round!.order.contains(uid);

  bool get isTiedPlayer => room?.tiebreak?.uids.contains(uid) ?? false;

  int get tiebreakVoteRemainingSeconds {
    final d = room?.tiebreak?.deadline;
    if (d == null) return 0;
    return max(0, (d.difference(now).inMilliseconds / 1000).ceil());
  }

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
    if (r.status == RoomStatus.tiebreakVote) return Phase.tiebreakVote;
    if (r.isKq) return _kqPhase(r);
    final rd = round;
    if (rd == null) return Phase.loading;
    // The host started a new round but its document hasn't arrived yet:
    // keep showing the finished round instead of flashing a loader.
    if (rd.key != r.currentRoundKey) {
      if (rd.gameNo != r.gameNo) return Phase.loading;
      return rd.status == RoundStatus.aborted ? Phase.aborted : Phase.results;
    }
    return switch (rd.status) {
      RoundStatus.picking => Phase.picking,
      RoundStatus.exchange =>
        now.isBefore(rd.introEndsAt) ? Phase.intro : Phase.exchange,
      RoundStatus.characters => Phase.characters,
      RoundStatus.revealed => Phase.results,
      RoundStatus.aborted => Phase.aborted,
    };
  }

  Phase _kqPhase(Room r) {
    final kr = kqRound;
    if (kr == null) return Phase.loading;
    if (kr.key != r.currentRoundKey) {
      // Next round requested but not yet loaded: keep the finished round.
      if (kr.gameNo != r.gameNo) return Phase.loading;
      return kr.status == KqStatus.aborted ? Phase.aborted : Phase.results;
    }
    return switch (kr.status) {
      KqStatus.picking => Phase.kqPicking,
      KqStatus.guessing => Phase.kqGuessing,
      KqStatus.revealed => Phase.results,
      KqStatus.aborted => Phase.aborted,
    };
  }

  /// My King & Queen role, only if it belongs to the round on screen.
  KqMyRole? get kqRole =>
      (_kqRole != null &&
          kqRound != null &&
          _kqRole!.roundKey == kqRound!.key &&
          _kqRole!.name != null)
      ? _kqRole
      : null;

  bool get kqMyTurn =>
      phase == Phase.kqGuessing &&
      kqRound?.guesser == uid &&
      !now.isBefore(kqRound!.guessOpensAt ?? now) &&
      kqTurnRemainingMs > -_graceMs;

  int get kqTurnRemainingMs {
    final d = kqRound?.turnDeadline;
    return d == null ? 0 : d.difference(now).inMilliseconds;
  }

  double get kqTurnProgress {
    final kr = kqRound;
    if (kr == null || kr.turnSeconds == 0) return 0;
    return (kqTurnRemainingMs / (kr.turnSeconds * 1000)).clamp(0.0, 1.0);
  }

  int get kqAnnounceRemainingSeconds {
    final o = kqRound?.guessOpensAt;
    if (o == null) return 0;
    return max(0, (o.difference(now).inMilliseconds / 1000).ceil());
  }

  bool get kqChitsOpen {
    final kr = kqRound;
    return kr != null &&
        kr.status == KqStatus.picking &&
        kr.pickOpensAt != null &&
        !now.isBefore(kr.pickOpensAt!);
  }

  bool get canKqPick =>
      kqChitsOpen &&
      kqRound!.players.contains(uid) &&
      !kqRound!.picks.containsValue(uid) &&
      pendingChits.isEmpty;

  int get kqPickRemainingSeconds {
    final d = kqRound?.pickDeadline;
    return d == null
        ? 0
        : max(0, (d.difference(now).inMilliseconds / 1000).ceil());
  }

  void _onKqRound(KqRound? kr) {
    if (kr == null) return;
    final prev = kqRound;
    kqRound = kr;
    if (prev?.turnId != kr.turnId) kqSelectedTarget = null;
    if (prev != null && prev.key == kr.key) {
      if (kr.picks.length > prev.picks.length) {
        feedback.play(Sfx.pick);
        feedback.selection();
      }
      for (final h in kr.history.skip(prev.history.length)) {
        final who = room?.nameOf(h.guesser) ?? 'Someone';
        final whom = h.target == uid
            ? 'you'
            : (room?.nameOf(h.target) ?? 'someone');
        final role = kr.chain[(h.step + 1).clamp(0, kr.chain.length - 1)];
        if (h.correct) {
          feedback.play(h.kind == 'forced' ? Sfx.pick : Sfx.reveal);
          feedback.medium();
          _messages.add(
            h.kind == 'forced'
                ? 'Only $whom could be the $role!'
                : '$who found the $role: $whom!',
          );
        } else {
          feedback.play(Sfx.timeout);
          feedback.warning();
          _messages.add(
            h.kind == 'timeout'
                ? '${h.guesser == uid ? 'You' : who} took too long, so a random guess was made: $whom. Wrong, so they swapped roles.'
                : '$who guessed $whom for $role. Wrong! They swapped roles.',
          );
        }
      }
      if (kr.status == KqStatus.revealed && prev.status != KqStatus.revealed) {
        feedback.play(Sfx.roundEnd);
        feedback.heavy();
      }
    }
    notifyListeners();
  }

  void _onKqRole(KqMyRole? r) {
    final prev = _kqRole;
    _kqRole = r;
    if (r != null &&
        prev != null &&
        prev.roundKey == r.roundKey &&
        prev.index != null &&
        r.index != null &&
        prev.index != r.index) {
      feedback.play(Sfx.unfold);
      feedback.heavy();
      _messages.add('You swapped roles: you are now the ${r.name}.');
    }
    notifyListeners();
  }

  void kqSelect(String target) {
    if (!kqMyTurn || busy || !(kqRound?.candidates.contains(target) ?? false)) {
      return;
    }
    kqSelectedTarget = kqSelectedTarget == target ? null : target;
    feedback.selection();
    feedback.play(Sfx.select);
    notifyListeners();
  }

  Future<void> kqConfirmGuess() async {
    final kr = kqRound;
    final target = kqSelectedTarget;
    if (kr == null || target == null || !kqMyTurn || busy) return;
    busy = true;
    notifyListeners();
    final requestId =
        '$uid-${kr.key}-${kr.turnId}-${_rand.nextInt(1 << 32).toRadixString(36)}';
    feedback.medium();
    try {
      await _withRetry(
        () => repo.kqGuess(roomId, kr.key, kr.turnId, target, requestId),
      );
    } on GameException catch (e) {
      _messages.add(e.message);
    } finally {
      busy = false;
      kqSelectedTarget = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> kqPick(String chitId) async {
    final kr = kqRound;
    if (kr == null || !canKqPick || kr.picks.containsKey(chitId)) return;
    if (!pendingChits.add(chitId)) return;
    feedback.selection();
    feedback.play(Sfx.pick);
    notifyListeners();
    try {
      final role = await _retryValue(
        () => repo.kqPickChit(roomId, kr.key, chitId),
      );
      revealQueue.add(role);
      feedback.medium();
    } on GameException catch (e) {
      _messages.add(
        e.code == 'already-exists'
            ? 'Someone grabbed that chit first!'
            : e.message,
      );
    } finally {
      pendingChits.remove(chitId);
      if (!_disposed) notifyListeners();
    }
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
    if (r.isKq) {
      _kqRoleSub ??= repo
          .watchMyKqRole(roomId)
          .listen(_onKqRole, onError: (_) {});
      if (key != null && key != _watchingRoundKey) {
        _watchingRoundKey = key;
        _kqRoundSub?.cancel();
        kqSelectedTarget = null;
        _kqRoundSub = repo
            .watchKqRound(roomId, key)
            .listen(_onKqRound, onError: (_) {});
      }
    } else if (key != null && key != _watchingRoundKey) {
      _watchingRoundKey = key;
      _roundSub?.cancel();
      selectedCardId = null;
      _roundSub = repo
          .watchRound(roomId, key)
          .listen(_onRound, onError: (_) {});
    }
    if (r.status == RoomStatus.tiebreakVote &&
        previous?.status != RoomStatus.tiebreakVote) {
      feedback.play(Sfx.reveal);
      feedback.medium();
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
    if (prev != null && prev.key == rd.key) _feedbackForOthersPicks(prev, rd);
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
              ? 'You took too long, so a card was passed for you.'
              : '${room?.nameOf(la.fromUid)} took too long, so a card was passed for them.',
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

  DateTime _lastPickSound = DateTime(0);

  void _feedbackForOthersPicks(Round prev, Round rd) {
    final newPicks = [
      ...rd.picks.entries.where((e) => !prev.picks.containsKey(e.key)),
      ...rd.charPicks.entries.where((e) => !prev.charPicks.containsKey(e.key)),
    ].where((e) => e.value != uid);
    if (newPicks.isEmpty) return;
    final t = DateTime.now();
    if (t.difference(_lastPickSound).inMilliseconds < 180) return;
    _lastPickSound = t;
    feedback.play(Sfx.pick);
    feedback.selection();
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
    if (rd != null && p == Phase.exchange && myTurn && rd.timed) {
      final s = (turnRemainingMs / 1000).ceil();
      if (s <= 5 && s > 0 && s != _lastWarnSecond) {
        _lastWarnSecond = s;
        feedback.play(Sfx.tick);
        if (s <= 3) feedback.warning();
      }
    }
    if (rd != null && p == Phase.characters) _maybeReveal(rd);
    if (p == Phase.tiebreakVote) _maybeCloseVote();
    final kr = kqRound;
    if (kr != null && p == Phase.kqGuessing && kqMyTurn && kr.timed) {
      final s = (kqTurnRemainingMs / 1000).ceil();
      if (s <= 5 && s > 0 && s != _lastWarnSecond) {
        _lastWarnSecond = s;
        feedback.play(Sfx.tick);
        if (s <= 3) feedback.warning();
      }
    }
    _buzzIfLate();
    final pruned = _pruneChat();
    if (pruned ||
        p == Phase.picking ||
        p == Phase.kqPicking ||
        p == Phase.kqGuessing ||
        p == Phase.intro ||
        p == Phase.exchange ||
        p == Phase.characters ||
        p == Phase.tiebreakVote) {
      notifyListeners();
    }
  }

  // ---------- late players ----------

  /// Who the table is waiting on past their deadline, if anyone.
  LateState? get late {
    final t = now;
    LateState? after(DateTime? deadline, Iterable<String> who) {
      if (deadline == null) return null;
      final uids = who.toList();
      if (uids.isEmpty) return null;
      if (!t.isAfter(deadline.add(const Duration(milliseconds: _graceMs)))) {
        return null;
      }
      return LateState(uids, deadline);
    }

    final rd = round;
    final kr = kqRound;
    switch (phase) {
      case Phase.picking when rd != null:
        final counts = <String, int>{};
        for (final u in rd.picks.values) {
          counts[u] = (counts[u] ?? 0) + 1;
        }
        return after(
          rd.pickDeadline,
          rd.order.where((u) => (counts[u] ?? 0) < 4),
        );
      case Phase.characters when rd != null && rd.revealAt == null:
        final picked = rd.charPicks.values.toSet();
        return after(
          rd.charPickDeadline,
          rd.order.where((u) => u != rd.winner?.uid && !picked.contains(u)),
        );
      case Phase.exchange when rd != null:
        return after(rd.turnDeadline, [rd.currentUid]);
      case Phase.kqPicking when kr != null:
        final picked = kr.picks.values.toSet();
        return after(
          kr.pickDeadline,
          kr.players.where((u) => !picked.contains(u)),
        );
      case Phase.kqGuessing when kr != null && kr.guesser != null:
        return after(kr.turnDeadline, [kr.guesser!]);
      default:
        return null;
    }
  }

  bool get iAmLate => late?.uids.contains(uid) ?? false;

  /// Seconds past the deadline (0 when nobody is late).
  int get overtimeSeconds {
    final l = late;
    return l == null ? 0 : max(0, now.difference(l.deadline).inSeconds);
  }

  /// No heartbeat for a while: the app is closed or the phone lost signal.
  bool isOffline(String player) {
    final seen = presence[player]?.lastSeen;
    return seen == null || now.difference(seen) > _offlineAfter;
  }

  /// Whether I may play for the late players now (the server checks too).
  bool get canPlayForLate {
    final l = late;
    if (l == null || l.uids.contains(uid)) return false;
    return now.difference(l.deadline) > playForAfter || l.uids.every(isOffline);
  }

  /// Plays for the late players: a random pass, pick or guess, exactly as a
  /// timeout used to, but only because someone at the table chose to.
  Future<bool> playForLate() {
    final rd = round;
    final kr = kqRound;
    final l = late;
    if (l == null || !canPlayForLate) return Future.value(false);
    final names = l.uids.map((u) => room?.nameOf(u) ?? 'Player').join(', ');
    return run(() async {
      switch (phase) {
        case Phase.exchange:
          await repo.claimTimeout(roomId, rd!.key, rd.turnId);
        case Phase.picking:
          await repo.autoPickChits(roomId, rd!.key);
          _messages.add('Chits were picked for $names.');
        case Phase.characters:
          await repo.autoPickCharacters(roomId, rd!.key);
          _messages.add('Characters were picked for $names.');
        case Phase.kqPicking:
          await repo.kqAutoPick(roomId, kr!.key);
          _messages.add('Chits were picked for $names.');
        case Phase.kqGuessing:
          await repo.kqClaimTimeout(roomId, kr!.key, kr.turnId);
        default:
          break;
      }
    });
  }

  /// Buzzes my phone when my time runs out, and again every 10 seconds.
  void _buzzIfLate() {
    final l = late;
    if (l == null || !l.uids.contains(uid)) {
      _lateKey = null;
      return;
    }
    final key = '${phase.name}:${l.deadline.millisecondsSinceEpoch}';
    if (key != _lateKey) {
      _lateKey = key;
      _lastBuzzSecond = -100;
      feedback.play(Sfx.timeout);
    }
    final over = now.difference(l.deadline).inSeconds;
    if (over - _lastBuzzSecond >= 10) {
      _lastBuzzSecond = over;
      feedback.buzz();
    }
  }

  // ---------- quick chat ----------

  void _onChat(List<ChatEvent> events) {
    var added = false;
    for (final e in events) {
      if (_seenChat[e.uid] == e.id) continue;
      final first = !_seenChat.containsKey(e.uid);
      _seenChat[e.uid] = e.id;
      // On joining, only show what was sent in the last few seconds.
      if (first && now.difference(e.at) > const Duration(seconds: 6)) continue;
      if (e.text == null) continue;
      chatFeed.add(
        ChatBubble(_chatSeq++, e, room?.nameOf(e.uid) ?? 'Player', now),
      );
      added = true;
      if (e.kind == ChatKind.nudge && e.to == uid) {
        feedback.play(Sfx.timeout);
        feedback.buzz();
      } else if (e.uid != uid) {
        feedback.selection();
      }
    }
    if (chatFeed.length > 12) chatFeed.removeRange(0, chatFeed.length - 12);
    if (added) notifyListeners();
  }

  bool _pruneChat() {
    final before = chatFeed.length;
    chatFeed.removeWhere(
      (b) => now.difference(b.shownAt) > const Duration(seconds: 4),
    );
    return chatFeed.length != before;
  }

  /// Sends a preset emoji or phrase; at most one per second (rules enforce it).
  bool sendQuick(ChatKind kind, String code) {
    final t = DateTime.now();
    if (t.difference(_lastSend) < const Duration(milliseconds: 1100)) {
      return false;
    }
    _lastSend = t;
    feedback.selection();
    repo
        .sendChat(roomId, id: _chatId(), kind: kind, code: code)
        .catchError((_) {});
    return true;
  }

  bool canNudge(String target) {
    final last = _lastNudge[target];
    return target != uid &&
        (last == null ||
            DateTime.now().difference(last) > const Duration(seconds: 8));
  }

  /// Buzzes [target]'s phone with a 👋 everyone sees.
  void nudge(String target) {
    if (!canNudge(target)) return;
    final t = DateTime.now();
    if (t.difference(_lastSend) < const Duration(milliseconds: 1100)) return;
    _lastSend = t;
    _lastNudge[target] = t;
    feedback.medium();
    repo
        .sendChat(
          roomId,
          id: _chatId(),
          kind: ChatKind.nudge,
          code: nudgeCode,
          to: target,
        )
        .catchError((_) {});
    notifyListeners();
  }

  String _chatId() => _rand.nextInt(1 << 32).toRadixString(36);

  /// After the vote deadline any member asks the server to close the vote.
  void _maybeCloseVote() {
    final tb = room?.tiebreak;
    if (tb == null || tb.stage != 'vote') return;
    final idx = max(0, room!.memberUids.indexOf(uid ?? ''));
    if (now.isBefore(
      tb.deadline.add(Duration(milliseconds: 800 + idx * 500)),
    )) {
      return;
    }
    final key = 'vote:${room!.gameNo}';
    if (!_claimedReveals.add(key)) return;
    repo.resolveTiebreakVote(roomId).catchError((_) {
      _claimedReveals.remove(key);
    });
  }

  void _maybeReveal(Round rd) {
    final at = rd.revealAt;
    if (at == null) return; // characters are still being picked
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

  /// Whether the folded chits can be picked yet (after the shuffle).
  bool get chitsOpen {
    final rd = round;
    return rd != null &&
        rd.status == RoundStatus.picking &&
        rd.pickOpensAt != null &&
        !now.isBefore(rd.pickOpensAt!);
  }

  bool get characterChitsOpen {
    final rd = round;
    return rd != null &&
        rd.status == RoundStatus.characters &&
        rd.revealAt == null &&
        rd.charPickOpensAt != null &&
        !now.isBefore(rd.charPickOpensAt!);
  }

  int get myChitCount => hand?.cards.length ?? 0;

  bool get canPickChit =>
      chitsOpen &&
      round!.order.contains(uid) &&
      myChitCount + pendingChits.length < 4;

  bool get canPickCharacter =>
      characterChitsOpen &&
      round!.order.contains(uid) &&
      round!.winner?.uid != uid &&
      !round!.charPicks.containsValue(uid) &&
      pendingChits.isEmpty;

  /// Seconds left to pick (movie or character chits).
  int get pickRemainingSeconds {
    final rd = round;
    final d = rd?.status == RoundStatus.picking
        ? rd?.pickDeadline
        : rd?.charPickDeadline;
    if (d == null) return 0;
    return max(0, (d.difference(now).inMilliseconds / 1000).ceil());
  }

  Future<void> pickChit(String chitId) async {
    final rd = round;
    if (rd == null || !canPickChit || rd.picks.containsKey(chitId)) return;
    if (!pendingChits.add(chitId)) return;
    feedback.selection();
    feedback.play(Sfx.pick);
    notifyListeners();
    try {
      final card = await _retryValue(
        () => repo.pickChit(roomId, rd.key, chitId),
      );
      revealQueue.add(card);
      feedback.medium();
    } on GameException catch (e) {
      _messages.add(
        e.code == 'already-exists'
            ? 'Someone grabbed that chit first!'
            : e.message,
      );
    } finally {
      pendingChits.remove(chitId);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> pickCharacter(String chitId) async {
    final rd = round;
    if (rd == null || !canPickCharacter || rd.charPicks.containsKey(chitId)) {
      return;
    }
    if (!pendingChits.add(chitId)) return;
    feedback.selection();
    feedback.play(Sfx.pick);
    notifyListeners();
    try {
      final c = await _retryValue(
        () => repo.pickCharacter(roomId, rd.key, chitId),
      );
      revealQueue.add(c);
      feedback.medium();
    } on GameException catch (e) {
      _messages.add(
        e.code == 'already-exists'
            ? 'Someone grabbed that chit first!'
            : e.message,
      );
    } finally {
      pendingChits.remove(chitId);
      if (!_disposed) notifyListeners();
    }
  }

  /// Called by the UI when it has finished playing a reveal.
  void consumeReveal() {
    if (revealQueue.isNotEmpty) revealQueue.removeAt(0);
    notifyListeners();
  }

  /// Like [_withRetry] for calls that return a value; picks are idempotent.
  Future<T> _retryValue<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on GameException catch (e) {
      if (e.code == 'unavailable' ||
          e.code == 'deadline-exceeded' ||
          e.code == 'internal') {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return f();
      }
      rethrow;
    }
  }

  Future<bool> setReady(bool v) => run(() => repo.setReady(roomId, v));
  Future<bool> updateKqSettings(Map<String, Object?> patch) =>
      run(() => repo.updateKqSettings(roomId, patch));
  Future<bool> updateSettings(Map<String, Object?> patch) =>
      run(() => repo.updateSettings(roomId, patch));
  Future<bool> kick(String player) =>
      run(() => repo.kickPlayer(roomId, player));
  Future<bool> startGame() => run(() => repo.startGame(roomId));
  Future<bool> nextRound() => run(() => repo.nextRound(roomId));
  Future<bool> revealNow() => run(() => repo.revealRound(roomId, round!.key));
  Future<bool> playAgain() => run(() => repo.playAgain(roomId));
  Future<bool> voteTiebreak(bool accept) =>
      run(() => repo.tiebreakVote(roomId, accept));

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
        category: r.isKq ? 'King & Queen' : r.settings.category.name,
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
    _kqRoundSub?.cancel();
    _kqRoleSub?.cancel();
    _presenceSub?.cancel();
    _chatSub?.cancel();
    _connSub?.cancel();
    _heartbeat?.cancel();
    _ticker?.cancel();
    _messages.close();
    super.dispose();
  }
}
