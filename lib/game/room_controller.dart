import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/services/feedback.dart';
import '../core/services/preferences.dart';
import '../core/theme/festivals.dart';
import '../data/charades.dart';
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

  /// Joined after the start: watching, maybe waiting for their seat back.
  spectating,

  /// Dumb Charades: someone is acting, the others pick the movie.
  charades,
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
    _watchHand();
    _presenceSub = repo.watchPresence(roomId).listen((p) {
      presence = p;
      notifyListeners();
    }, onError: (_) {});
    _chatSub = repo.watchChat(roomId).listen(_onChat, onError: (_) {});
    _messagesSub = repo
        .watchMessages(roomId)
        .listen(_onMessages, onError: (_) {});
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

  void _watchHand() {
    _handSub?.cancel();
    _handSub = repo.watchHand(roomId).listen(_onHand, onError: (_) {});
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
  StreamSubscription<List<ChatMessage>>? _messagesSub;

  /// The room's chat history, oldest first.
  List<ChatMessage> chatHistory = const [];

  /// Messages that arrived while the chat panel was closed.
  int unreadChat = 0;
  bool chatOpen = false;
  final _seenMessages = <String>{};
  bool _messagesLoaded = false;
  String? _lateKey;
  int _lastBuzzSecond = -100;

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<Round?>? _roundSub;
  StreamSubscription<Hand?>? _handSub;
  StreamSubscription<KqRound?>? _kqRoundSub;
  StreamSubscription<KqMyRole?>? _kqRoleSub;
  StreamSubscription<CharadesRound?>? _charadesSub;
  StreamSubscription<CharadesCard?>? _cardSub;
  CharadesRound? charades;
  CharadesCard? _card;

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

  /// My slips in the order I arranged them (drag to reorder); new slips
  /// join at the end. Local only: the server never cares about the order.
  List<GameCard> get orderedHand {
    final h = hand;
    if (h == null) return const [];
    final byId = {for (final c in h.cards) c.id: c};
    final out = <GameCard>[
      for (final id in _handOrder)
        if (byId.containsKey(id)) byId.remove(id)!,
      ...byId.values,
    ];
    return out;
  }

  final _handOrder = <String>[];
  String? _handOrderRound;

  /// Moves slip [id] to position [index] in my hand.
  void reorderHand(String id, int index) {
    final cards = orderedHand.map((c) => c.id).toList();
    if (!cards.contains(id)) return;
    cards.remove(id);
    cards.insert(index.clamp(0, cards.length), id);
    _handOrder
      ..clear()
      ..addAll(cards);
    feedback.selection();
    notifyListeners();
  }

  /// Passes [cardId] straight away (a slip dropped on the circle).
  Future<void> passCard(String cardId) {
    if (!myTurn || busy) return Future.value();
    selectedCardId = cardId;
    return passSelected();
  }

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
    if (uid != null && !r.memberUids.contains(uid)) {
      return r.spectators.containsKey(uid) ? Phase.spectating : Phase.removed;
    }
    if (r.status == RoomStatus.lobby) return Phase.lobby;
    if (r.status == RoomStatus.finished) {
      // The last round's results come first; "See final results" moves on.
      // A game the host ended, or that ended for want of players, has no
      // finished round to show.
      return _finalRoundPending(r) ? Phase.results : Phase.finished;
    }
    if (r.status == RoomStatus.tiebreakVote) return Phase.tiebreakVote;
    if (r.isCharades) {
      final cr = charades;
      if (cr == null || cr.gameNo != r.gameNo) return Phase.loading;
      // Next round requested but not loaded yet: keep the last result up.
      if (cr.key != r.currentRoundKey || cr.revealed) return Phase.results;
      return Phase.charades;
    }
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

  /// The game just finished and this phone hasn't moved past the last
  /// round's results yet.
  bool _finalRoundPending(Room r) {
    if (_finalAckGame == r.gameNo || r.endedReason != null) return false;
    if (r.isCharades) return false;
    if (r.isKq) {
      final kr = kqRound;
      return kr != null &&
          kr.key == r.currentRoundKey &&
          kr.status == KqStatus.revealed;
    }
    final rd = round;
    return rd != null &&
        rd.key == r.currentRoundKey &&
        rd.status == RoundStatus.revealed;
  }

  int? _finalAckGame;

  /// True on the last round's results: the game is over behind them.
  bool get finalRoundShown =>
      room?.status == RoomStatus.finished && phase == Phase.results;

  /// Moves from the last round's results to the final standings.
  void acknowledgeFinal() {
    _finalAckGame = room?.gameNo;
    feedback.play(Sfx.fanfare);
    feedback.celebrate();
    notifyListeners();
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

  /// Still my turn after the deadline: nothing is guessed for me automatically.
  bool get kqMyTurn =>
      phase == Phase.kqGuessing &&
      kqRound?.guesser == uid &&
      !now.isBefore(kqRound!.guessOpensAt ?? now);

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
    // A role reveal still playing when picking ended (the last chit went
    // straight into guessing) would otherwise sit in the queue and block
    // the next round's chits.
    if (prev?.key != kr.key || kr.status != KqStatus.picking) {
      revealQueue.removeWhere((r) => r is KqRoleDef);
    }
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
        if (kr.revealedRoles?[uid] == 0) {
          _stat('kq:$roomId:${kr.key}', {'kingRounds': 1, 'xp': 20});
        }
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
      _fail(e.message);
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
    // Watching -> seated (seat handed over, or a new game): our private
    // hand and role streams were refused before, so start them again.
    final wasMember = room?.memberUids.contains(uid) ?? true;
    if (!wasMember && r.memberUids.contains(uid)) {
      _watchHand();
      _kqRoleSub?.cancel();
      _kqRoleSub = null;
      _cardSub?.cancel();
      _cardSub = null;
    }
    final previous = room;
    room = r;
    final key = r.currentRoundKey;
    if (r.isCharades) {
      _cardSub ??= repo.watchMyCard(roomId).listen((c) {
        _card = c;
        notifyListeners();
      }, onError: (_) {});
      if (key != null && key != _watchingRoundKey) {
        _watchingRoundKey = key;
        _charadesSub?.cancel();
        _charadesSub = repo
            .watchCharades(roomId, key)
            .listen(_onCharades, onError: (_) {});
      }
    } else if (r.isKq) {
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
    if (previous != null) _feedbackForRoomChange(previous, r);
    _noticeWarnings(previous, r);
    if (r.status == RoomStatus.tiebreakVote &&
        previous?.status != RoomStatus.tiebreakVote) {
      feedback.play(Sfx.reveal);
      feedback.medium();
    }
    if (r.status == RoomStatus.finished &&
        previous?.status != RoomStatus.finished) {
      feedback.play(Sfx.fanfare);
      feedback.celebrate();
      _saveHistory(r);
    }
    if (r.status == RoomStatus.closed || !r.memberUids.contains(uid)) {
      prefs.activeRoomId = null;
    }
    notifyListeners();
  }

  void _feedbackForRoomChange(Room previous, Room r) {
    if (previous.status == RoomStatus.lobby && r.status == RoomStatus.playing) {
      feedback.play(Sfx.start);
      feedback.start();
      return;
    }
    if (r.status != RoomStatus.lobby) return;
    final before = previous.activePlayers.map((p) => p.uid).toSet();
    final after = r.activePlayers.map((p) => p.uid).toSet();
    if (after.difference(before).any((u) => u != uid)) {
      feedback.play(Sfx.join);
      feedback.light();
    } else if (before.difference(after).any((u) => u != uid)) {
      feedback.play(Sfx.leave);
    }
  }

  void _onRound(Round? rd) {
    if (rd == null) return;
    final prev = round;
    round = rd;
    if (prev != null && prev.key == rd.key) _feedbackForOthersPicks(prev, rd);
    // Reveals belong to one picking phase. A slip still unfolding when the
    // fourth pick ended the picking (or a character reveal cut off by the
    // round ending) must not linger: a leftover reveal made the character
    // chits unresponsive for whoever picked last.
    if (prev?.key != rd.key || rd.status != RoundStatus.picking) {
      revealQueue.removeWhere((r) => r is GameCard);
    }
    if (prev?.key != rd.key || rd.status != RoundStatus.characters) {
      revealQueue.removeWhere((r) => r is CharacterDef);
    }
    if (rd.status == RoundStatus.characters &&
        prev?.status == RoundStatus.exchange &&
        rd.stalemate) {
      feedback.play(Sfx.shuffle);
      feedback.heavy();
      _messages.add('No winner this round! Everyone picks a character chit.');
    }
    if (prev?.turnId != rd.turnId) {
      _turnChangedAt = now;
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
        rd.winner?.uid == uid ? feedback.celebrate() : feedback.heavy();
      }
      if (rd.winner?.uid == uid && !rd.tiebreak) {
        _stat('win:$roomId:${rd.key}', {'roundWins': 1, 'xp': 30});
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
  bool _wasMyTurn = false;

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
    if (h != null && h.roundKey != _handOrderRound) {
      _handOrderRound = h.roundKey;
      _handOrder.clear();
    }
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

  /// A move the server refused: say why, with a soft "no" sound and buzz.
  void _fail(String message) {
    feedback.play(Sfx.error);
    feedback.error();
    _messages.add(message);
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
        feedback.play(s <= 3 ? Sfx.tickUrgent : Sfx.tick);
        s <= 3 ? feedback.medium() : feedback.selection();
      }
    }
    if (rd != null && p == Phase.characters) _maybeReveal(rd);
    if (p == Phase.tiebreakVote) _maybeCloseVote();
    final kr = kqRound;
    if (kr != null && p == Phase.kqGuessing && kqMyTurn && kr.timed) {
      final s = (kqTurnRemainingMs / 1000).ceil();
      if (s <= 5 && s > 0 && s != _lastWarnSecond) {
        _lastWarnSecond = s;
        feedback.play(s <= 3 ? Sfx.tickUrgent : Sfx.tick);
        s <= 3 ? feedback.medium() : feedback.selection();
      }
    }
    final mine = myTurn || kqMyTurn;
    if (mine && !_wasMyTurn) feedback.yourTurn();
    _wasMyTurn = mine;
    _buzzIfLate();
    _buzzIfWarned();
    _enforceWarningsIfDue();
    _driveBots();
    _autoPickIfDue();
    _warnPickEnding();
    _autoStartPublic();
    _revealCharadesIfDue();
    final pruned = _pruneChat();
    if (pruned ||
        p == Phase.picking ||
        p == Phase.kqPicking ||
        p == Phase.kqGuessing ||
        p == Phase.intro ||
        p == Phase.exchange ||
        p == Phase.characters ||
        p == Phase.tiebreakVote ||
        p == Phase.charades ||
        iAmWarned ||
        (room?.warnings.values.any((w) => w.deadline != null) ?? false) ||
        (p == Phase.lobby && (room?.isPublic ?? false))) {
      notifyListeners();
    }
  }

  // ---------- warnings ("are you still there?") ----------

  Warning? warningOf(String player) => room?.warnings[player];

  /// A warning still waiting for [player]'s answer.
  bool warningOpen(String player) {
    final d = warningOf(player)?.deadline;
    return d != null &&
        !now.isAfter(d.add(const Duration(milliseconds: _graceMs)));
  }

  /// Seconds [player] has left to answer (0 when none is open).
  int warningSecondsLeft(String player) {
    final d = warningOf(player)?.deadline;
    if (d == null) return 0;
    return max(0, (d.difference(now).inMilliseconds / 1000).ceil());
  }

  bool get iAmWarned => uid != null && warningOpen(uid!);

  /// Whether the host may remove [player] right now (the server checks too).
  bool canRemoveNow(String player) {
    if (!isHost || player == uid) return false;
    if (room?.status == RoomStatus.lobby || isBotUid(player)) return true;
    final w = warningOf(player);
    if (w == null) return false;
    final d = w.deadline;
    return w.count >= warningsBeforeKick ||
        (d != null &&
            now.isAfter(d.add(const Duration(milliseconds: _graceMs))));
  }

  /// Whether the host may warn [player] now.
  bool canWarn(String player) =>
      isHost &&
      player != uid &&
      !isBotUid(player) &&
      room?.status != RoomStatus.lobby &&
      !warningOpen(player);

  Future<bool> warn(String player) => run(() async {
    await repo.warnPlayer(roomId, player);
    _messages.add(
      '${room?.nameOf(player) ?? 'They'} has 60 seconds to respond.',
    );
  });

  Future<bool> respondToWarning() => run(() async {
    await repo.respondToWarning(roomId);
    feedback.play(Sfx.coin);
    feedback.light();
  });

  Future<bool> removePlayer(String player) =>
      run(() => repo.kickPlayer(roomId, player));

  Future<bool> endGame() => run(() => repo.endGame(roomId));

  String? _warnKey;
  int _lastWarnBuzz = -100;

  void _noticeWarnings(Room? previous, Room r) {
    final mine = r.warnings[uid];
    if (mine?.deadline == null) return;
    final before = previous?.warnings[uid]?.deadline;
    if (before == mine!.deadline) return;
    feedback.play(Sfx.timeout);
    feedback.buzz();
    _messages.add('⚠️ The host asks: are you still there? Tap "I\'m here!"');
  }

  /// A long buzz every 10 seconds while a warning waits for me.
  void _buzzIfWarned() {
    if (!iAmWarned) {
      _warnKey = null;
      return;
    }
    final d = warningOf(uid!)!.deadline!;
    final key = d.millisecondsSinceEpoch.toString();
    if (key != _warnKey) {
      _warnKey = key;
      _lastWarnBuzz = -100;
    }
    final left = warningSecondsLeft(uid!);
    if (_lastWarnBuzz - left >= 10 || _lastWarnBuzz == -100) {
      _lastWarnBuzz = left;
      if (_lastWarnBuzz != -100 && left < 60) feedback.buzz();
    }
  }

  DateTime _lastEnforce = DateTime(0);

  /// Removes players whose warning ran out. Every phone can ask (the
  /// server checks the clock); the first person in room order goes first,
  /// the others step in if that phone is slow.
  void _enforceWarningsIfDue() {
    final r = room;
    if (r == null || r.status == RoomStatus.closed) return;
    DateTime? due;
    for (final m in r.memberUids) {
      final d = r.warnings[m]?.deadline;
      if (d != null && (due == null || d.isBefore(due))) due = d;
    }
    if (due == null) return;
    final people = r.memberUids.where((u) => !isBotUid(u)).toList();
    final me = people.indexOf(uid ?? '');
    if (me < 0) return;
    final over = now.difference(due);
    if (over < Duration(milliseconds: 1500 + me * 2000)) return;
    if (DateTime.now().difference(_lastEnforce) < const Duration(seconds: 3)) {
      return;
    }
    _lastEnforce = DateTime.now();
    repo.enforceWarnings(roomId).catchError((_) {});
  }

  // ---------- stalemate ----------

  /// Movie Chits: after [stalemateLaps] full laps with no winner the host
  /// may end the exchange and send everyone to the character chits.
  bool get canEndExchange =>
      isHost &&
      phase == Phase.exchange &&
      (round?.laps ?? 0) >= stalemateLaps &&
      round?.tiebreak != true;

  /// Laps still to go before the host may end the exchange.
  int get lapsUntilStalemate => max(0, stalemateLaps - (round?.laps ?? 0));

  Future<bool> endExchange() {
    final rd = round;
    if (rd == null || !canEndExchange) return Future.value(false);
    return run(() => repo.endExchange(roomId, rd.key));
  }

  // ---------- joining a running game ----------

  /// A watcher may take a free seat and play from the next round.
  bool get canTakeSeat {
    final r = room;
    final me = mySpectator;
    return r != null &&
        me != null &&
        r.status == RoomStatus.playing &&
        r.hasFreeSeat &&
        me.claims == null &&
        me.approved == null;
  }

  Future<bool> takeSeat() => run(() async {
    await repo.takeSeat(roomId);
    feedback.play(Sfx.join);
    feedback.celebrate();
  });

  /// A member who joined mid-game: they sit out the round in progress.
  bool get joinsNextRound {
    final r = room;
    if (r == null || uid == null || !r.memberUids.contains(uid)) return false;
    if (r.status != RoomStatus.playing) return false;
    if (r.isKq) {
      final kr = kqRound;
      return kr != null &&
          kr.key == r.currentRoundKey &&
          !kr.players.contains(uid);
    }
    if (r.isCharades) return false;
    final rd = round;
    return rd != null &&
        rd.key == r.currentRoundKey &&
        !rd.tiebreak &&
        !rd.order.contains(uid);
  }

  // ---------- bots ----------

  bool _botCallInFlight = false;
  DateTime _lastBotCall = DateTime(0);
  DateTime _turnChangedAt = DateTime(0);

  bool get hasBots => room?.memberUids.any(isBotUid) ?? false;

  /// The move bots are waiting on right now: when it opened and the call
  /// that makes it. The server does the moving (and checks the timing).
  (DateTime, Future<void> Function())? _botMove() {
    final rd = round;
    final kr = kqRound;
    switch (phase) {
      case Phase.picking when rd != null && rd.pickOpensAt != null:
        final counts = <String, int>{};
        for (final u in rd.picks.values) {
          counts[u] = (counts[u] ?? 0) + 1;
        }
        if (!rd.order.any((u) => isBotUid(u) && (counts[u] ?? 0) < 4)) {
          return null;
        }
        return (rd.pickOpensAt!, () => repo.autoPickChits(roomId, rd.key));
      case Phase.exchange when rd != null && isBotUid(rd.currentUid):
        final opened = rd.introEndsAt.isAfter(_turnChangedAt)
            ? rd.introEndsAt
            : _turnChangedAt;
        return (opened, () => repo.claimTimeout(roomId, rd.key, rd.turnId));
      case Phase.characters
          when rd != null && rd.revealAt == null && rd.charPickOpensAt != null:
        final picked = rd.charPicks.values.toSet();
        if (!rd.order.any(
          (u) => isBotUid(u) && u != rd.winner?.uid && !picked.contains(u),
        )) {
          return null;
        }
        return (
          rd.charPickOpensAt!,
          () => repo.autoPickCharacters(roomId, rd.key),
        );
      case Phase.kqPicking when kr != null && kr.pickOpensAt != null:
        final picked = kr.picks.values.toSet();
        if (!kr.players.any((u) => isBotUid(u) && !picked.contains(u))) {
          return null;
        }
        return (kr.pickOpensAt!, () => repo.kqAutoPick(roomId, kr.key));
      case Phase.kqGuessing
          when kr != null && kr.guesser != null && isBotUid(kr.guesser!):
        return (
          kr.guessOpensAt ?? now,
          () => repo.kqClaimTimeout(roomId, kr.key, kr.turnId),
        );
      default:
        return null;
    }
  }

  /// Makes the bots' moves. Every person's phone can do it; the first one
  /// in the room's order goes first and the others only step in if it's
  /// slow (e.g. that phone is locked), so moves aren't sent many times.
  void _driveBots() {
    if (_botCallInFlight || !hasBots) return;
    final move = _botMove();
    if (move == null) return;
    final humans = room!.memberUids.where((u) => !isBotUid(u)).toList();
    final me = humans.indexOf(uid ?? '');
    if (me < 0) return;
    // Bots "think" 1.5–3 s, a little differently each turn.
    final think = 1500 + ((round?.turnId ?? kqRound?.turnId ?? 0) * 373) % 1500;
    final due = move.$1.add(Duration(milliseconds: think + me * 2500));
    if (now.isBefore(due)) return;
    if (DateTime.now().difference(_lastBotCall) < const Duration(seconds: 2)) {
      return;
    }
    _lastBotCall = DateTime.now();
    _botCallInFlight = true;
    // Losing a race with another phone or the server's timing is normal.
    move.$2().catchError((_) {}).whenComplete(() => _botCallInFlight = false);
  }

  // ---------- automatic picks ----------

  DateTime _lastAutoPick = DateTime(0);
  int _lastPickWarn = -1;

  /// The pick deadline of the current picking phase, and the call that
  /// picks at random for everyone still picking.
  (DateTime, Future<void> Function())? _openPicks() {
    final rd = round;
    final kr = kqRound;
    switch (phase) {
      case Phase.picking when rd != null && rd.pickDeadline != null:
        final counts = <String, int>{};
        for (final u in rd.picks.values) {
          counts[u] = (counts[u] ?? 0) + 1;
        }
        if (!rd.order.any((u) => (counts[u] ?? 0) < 4)) return null;
        return (rd.pickDeadline!, () => repo.autoPickChits(roomId, rd.key));
      case Phase.characters
          when rd != null && rd.revealAt == null && rd.charPickDeadline != null:
        final picked = rd.charPicks.values.toSet();
        if (!rd.order.any((u) => u != rd.winner?.uid && !picked.contains(u))) {
          return null;
        }
        return (
          rd.charPickDeadline!,
          () => repo.autoPickCharacters(roomId, rd.key),
        );
      case Phase.kqPicking when kr != null && kr.pickDeadline != null:
        final picked = kr.picks.values.toSet();
        if (!kr.players.any((u) => !picked.contains(u))) return null;
        return (kr.pickDeadline!, () => repo.kqAutoPick(roomId, kr.key));
      default:
        return null;
    }
  }

  /// When the pick timer runs out, the rest are picked at random. Every
  /// phone in the room can ask (the server checks the time); the first
  /// person in room order goes first, the others step in if it's slow.
  void _autoPickIfDue() {
    final open = _openPicks();
    if (open == null) return;
    final people = room!.memberUids.where((u) => !isBotUid(u)).toList();
    final me = people.indexOf(uid ?? '');
    if (me < 0) return;
    final over = now.difference(open.$1);
    if (over < Duration(milliseconds: 1500 + me * 2000)) return;
    if (DateTime.now().difference(_lastAutoPick) < const Duration(seconds: 3)) {
      return;
    }
    _lastAutoPick = DateTime.now();
    open.$2().catchError((_) {});
  }

  /// Ticks (and a buzz at the end) in the last 5 seconds while I still
  /// have chits to pick.
  void _warnPickEnding() {
    final mine = switch (phase) {
      Phase.picking => canPickChit,
      Phase.characters => canPickCharacter,
      Phase.kqPicking => canKqPick,
      _ => false,
    };
    if (!mine) return;
    final s = phase == Phase.kqPicking
        ? kqPickRemainingSeconds
        : pickRemainingSeconds;
    if (s <= 0 || s > 5 || s == _lastPickWarn) return;
    _lastPickWarn = s;
    feedback.play(s <= 3 ? Sfx.tickUrgent : Sfx.tick);
    s == 1 ? feedback.warning() : feedback.selection();
  }

  // ---------- dumb charades ----------

  bool get iAmActor => charades?.actor == uid;

  /// The movie I have to act out (only on the actor's phone).
  String? get myMovie {
    final c = _card;
    return c != null && c.roundKey == charades?.key ? c.movie : null;
  }

  int? get myGuess => charades?.guesses[uid];

  /// Seconds until acting starts (0 once it has).
  int get charadesReadySeconds {
    final cr = charades;
    if (cr == null) return 0;
    return max(0, (cr.startsAt.difference(now).inMilliseconds / 1000).ceil());
  }

  int get charadesSecondsLeft {
    final cr = charades;
    if (cr == null) return 0;
    return max(0, (cr.deadline.difference(now).inMilliseconds / 1000).ceil());
  }

  bool get canGuess =>
      phase == Phase.charades &&
      !iAmActor &&
      myGuess == null &&
      charadesReadySeconds == 0 &&
      !busy;

  Future<bool> guess(int option) {
    final cr = charades;
    if (cr == null || !canGuess) return Future.value(false);
    feedback.play(Sfx.select);
    feedback.medium();
    return run(() => repo.charadesGuess(roomId, cr.key, option));
  }

  void _onCharades(CharadesRound? cr) {
    if (cr == null) return;
    final prev = charades;
    charades = cr;
    if (prev?.key != cr.key && !cr.revealed) {
      if (cr.actor == uid) {
        feedback.play(Sfx.start);
        feedback.yourTurn();
      } else {
        feedback.play(Sfx.shuffle);
      }
    }
    if (prev != null && prev.key == cr.key) {
      final mine = cr.guesses[uid];
      if (mine != null && prev.guesses[uid] == null && !cr.revealed) {
        // Still acting after my guess: it wasn't the one.
        feedback.play(Sfx.error);
        feedback.error();
      }
      if (cr.revealed && !prev.revealed) {
        if (cr.solvedBy == uid) {
          feedback.play(Sfx.win);
          feedback.celebrate();
          _stat('charades:$roomId:${cr.key}', {'xp': 20});
        } else if (cr.solvedBy != null && cr.actor == uid) {
          feedback.play(Sfx.coin);
          feedback.celebrate();
        } else {
          feedback.play(cr.solvedBy == null ? Sfx.timeout : Sfx.roundEnd);
          feedback.heavy();
        }
      }
    }
    notifyListeners();
  }

  DateTime _lastCharadesReveal = DateTime(0);

  /// When time runs out, the first person in the room ends the round
  /// (others step in if that phone is slow). Nobody scores.
  void _revealCharadesIfDue() {
    final cr = charades;
    if (phase != Phase.charades || cr == null) return;
    final people = room!.memberUids.where((u) => !isBotUid(u)).toList();
    final me = people.indexOf(uid ?? '');
    if (me < 0) return;
    final over = now.difference(cr.deadline);
    if (over < Duration(milliseconds: 1500 + me * 2500)) return;
    if (DateTime.now().difference(_lastCharadesReveal) <
        const Duration(seconds: 3)) {
      return;
    }
    _lastCharadesReveal = DateTime.now();
    repo.charadesReveal(roomId, cr.key).catchError((_) {});
  }

  // ---------- quick match ----------

  DateTime _lastAutoStart = DateTime(0);

  /// Seconds until a quick-match table starts by itself (null: not public).
  int? get publicStartSeconds {
    final at = room?.publicStartsAt;
    if (at == null || phase != Phase.lobby) return null;
    return max(0, (at.difference(now).inMilliseconds / 1000).ceil());
  }

  /// Whether anyone at a public table may start it now.
  bool get canStartPublic {
    final r = room;
    if (r == null || !r.isPublic) return false;
    return (publicStartSeconds ?? 1) == 0 ||
        (r.memberUids.length >= 4 && r.everyoneReady());
  }

  /// When the countdown ends, the first person at the table starts it
  /// (others step in if that phone is slow); bots fill empty seats.
  void _autoStartPublic() {
    if (publicStartSeconds != 0 || busy) return;
    final humans = room!.memberUids.where((u) => !isBotUid(u)).toList();
    final me = humans.indexOf(uid ?? '');
    if (me < 0) return;
    final late = now.difference(room!.publicStartsAt!);
    if (late < Duration(seconds: 1 + me * 3)) return;
    if (DateTime.now().difference(_lastAutoStart) <
        const Duration(seconds: 4)) {
      return;
    }
    _lastAutoStart = DateTime.now();
    repo.startGame(roomId).catchError((_) {});
  }

  // ---------- late players ----------

  /// Who the table is waiting on past their deadline, if anyone.
  LateState? get late {
    final t = now;
    LateState? after(DateTime? deadline, Iterable<String> who) {
      if (deadline == null) return null;
      // Bots are moved for automatically (see _driveBots), never "late".
      final uids = who.where((u) => !isBotUid(u)).toList();
      if (uids.isEmpty) return null;
      if (!t.isAfter(deadline.add(const Duration(milliseconds: _graceMs)))) {
        return null;
      }
      return LateState(uids, deadline);
    }

    final rd = round;
    final kr = kqRound;
    switch (phase) {
      // Picking chits is never "late": when its timer runs out the rest
      // are picked at random (see _autoPickIfDue).
      case Phase.exchange when rd != null:
        return after(rd.turnDeadline, [rd.currentUid]);
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
        feedback.play(Sfx.nudge);
        feedback.buzz();
      } else if (e.uid != uid) {
        feedback.play(Sfx.pop);
        feedback.selection();
      }
    }
    if (chatFeed.length > 12) chatFeed.removeRange(0, chatFeed.length - 12);
    if (added) notifyListeners();
  }

  void _onMessages(List<ChatMessage> list) {
    final fresh = list.where((m) => _seenMessages.add(m.id)).toList();
    chatHistory = list;
    if (_messagesLoaded && !chatOpen) {
      unreadChat += fresh.where((m) => m.uid != uid).length;
    }
    _messagesLoaded = true;
    notifyListeners();
  }

  /// The chat panel opened or closed: unread counts only while it's closed.
  void setChatOpen(bool open) {
    chatOpen = open;
    if (open) unreadChat = 0;
    notifyListeners();
  }

  /// Free text is for rooms of friends; quick-match tables stay preset-only.
  bool get canSendText => room?.isPublic != true;

  /// Sends a short typed message; false if throttled, empty or not allowed.
  bool sendText(String raw) {
    final text = cleanChatText(raw);
    if (text == null || !canSendText) return false;
    final t = DateTime.now();
    if (t.difference(_lastSend) < const Duration(milliseconds: 1100)) {
      return false;
    }
    _lastSend = t;
    feedback.play(Sfx.pop);
    feedback.selection();
    _stat('chat:${t.microsecondsSinceEpoch}', {'chats': 1});
    repo
        .sendChat(
          roomId,
          id: _chatId(),
          kind: ChatKind.text,
          code: textCode,
          text: text,
        )
        .catchError((_) {});
    return true;
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
    feedback.play(Sfx.pop);
    feedback.selection();
    _stat('chat:${t.microsecondsSinceEpoch}', {'chats': 1});
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
    _stat('nudge:${t.microsecondsSinceEpoch}', {'nudges': 1});
    feedback.play(Sfx.nudge);
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
      _fail(e.message);
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
      _fail(e.message);
      return false;
    } catch (e) {
      _fail('Network problem. Check your connection and try again.');
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
  Future<bool> addBot() => run(() => repo.addBot(roomId));

  bool get isSpectator => room?.spectators.containsKey(uid) ?? false;
  Spectator? get mySpectator => room?.spectators[uid];

  /// Seat requests waiting for the host's answer.
  List<Spectator> get seatClaims => isHost
      ? room!.spectators.values.where((s) => s.claims != null).toList()
      : const [];

  Future<bool> claimSeat(String? seat) =>
      run(() => repo.claimSeat(roomId, seat));
  Future<bool> answerSeatClaim(String spectator, bool approve) =>
      run(() => repo.answerSeatClaim(roomId, spectator, approve));
  Future<bool> startGame() => run(() => repo.startGame(roomId));
  Future<bool> nextRound() => run(() => repo.nextRound(roomId));
  Future<bool> revealNow() => run(() => repo.revealRound(roomId, round!.key));
  Future<bool> playAgain() => run(() => repo.playAgain(roomId));
  Future<bool> voteTiebreak(bool accept) =>
      run(() => repo.tiebreakVote(roomId, accept));

  /// Leaves the room. Resolves within a few seconds even when the server
  /// is slow (a cold Cloud Function): leaving locally always succeeds, and
  /// the server expires stale seats on its own.
  Future<void> leave() async {
    prefs.activeRoomId = null;
    try {
      await repo.leaveRoom(roomId).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Already gone, offline, or slow: all fine for the player.
    }
  }

  /// Adds to my profile stats once per [key]; celebrates new badges.
  void _stat(String key, Map<String, int> add) {
    final unlocked = prefs.stats.record(key, add);
    for (final b in unlocked) {
      feedback.play(Sfx.coin);
      feedback.celebrate();
      _messages.add('🏅 New badge: ${b.emoji} ${b.title}!');
    }
  }

  /// Profile stats for a finished game: played, titles, special badges.
  void _statsForGame(Room r) {
    final mine = r.finalStandings?.where((s) => s.uid == uid).firstOrNull;
    if (mine == null) return;
    final king = mine.title == 'King';
    final queen = mine.title == 'Queen';
    final hour = DateTime.now().hour;
    _stat('game:${r.id}:${r.gameNo}', {
      'games': 1,
      'xp': 50 + (king ? 100 : 0) + (queen ? 60 : 0),
      if (king) 'kings': 1,
      if (queen) 'queens': 1,
      if (king && r.memberUids.any(isBotUid)) 'botWins': 1,
      if (r.memberUids.length >= 8) 'bigTables': 1,
      if (hour < 5) 'nightGames': 1,
      if (Festival.on(DateTime.now()) != null) 'festivalGames': 1,
      if (!r.isKq && mine.movieWins >= 3) 'hatTricks': 1,
    });
  }

  void _saveHistory(Room r) {
    _statsForGame(r);
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
    _charadesSub?.cancel();
    _cardSub?.cancel();
    _presenceSub?.cancel();
    _chatSub?.cancel();
    _messagesSub?.cancel();
    _connSub?.cancel();
    _heartbeat?.cancel();
    _ticker?.cancel();
    _messages.close();
    super.dispose();
  }
}
