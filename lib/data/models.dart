import 'package:cloud_firestore/cloud_firestore.dart';

/// Client-side views of the Firestore documents written by Cloud Functions.
/// Clients never write these; see functions/src/game/model.ts.

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

DateTime? _time(Object? v) => switch (v) {
  Timestamp t => t.toDate(),
  int ms => DateTime.fromMillisecondsSinceEpoch(ms),
  _ => null,
};

Map<String, T> _map<T>(Object? v, T Function(Object? e) f) =>
    (v as Map?)?.map((k, e) => MapEntry(k as String, f(e))) ?? {};

class GameCard {
  const GameCard({required this.id, required this.name});
  final String id;
  final String name;

  factory GameCard.fromMap(Object? m) {
    final map = m as Map;
    return GameCard(id: map['id'] as String, name: map['name'] as String);
  }

  @override
  bool operator ==(Object other) => other is GameCard && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class CharacterDef {
  const CharacterDef(this.name, this.points);
  final String name;
  final int points;

  factory CharacterDef.fromMap(Object? m) {
    final map = m as Map;
    return CharacterDef(map['name'] as String, _int(map['points']));
  }

  Map<String, Object> toMap() => {'name': name, 'points': points};
}

enum Category { telugu, indian, hollywood, custom, mixed }

enum Difficulty { easy, normal, challenging }

enum TimeoutPolicy { passIncoming, passRandom }

class GameSettings {
  const GameSettings({
    required this.category,
    required this.customNames,
    required this.rounds,
    required this.turnSeconds,
    required this.difficulty,
    required this.timeoutPolicy,
    required this.winPoints,
    required this.characters,
  });

  final Category category;
  final List<String> customNames;
  final int rounds;
  final int turnSeconds;
  final Difficulty difficulty;
  final TimeoutPolicy timeoutPolicy;
  final int winPoints;
  final List<CharacterDef> characters;

  static const turnOptions = [10, 15, 20, 30, 45, 60, 0];
  static const roundOptions = [7, 10, 15, 20];
  static const difficultyTurnSeconds = {
    Difficulty.easy: 30,
    Difficulty.normal: 20,
    Difficulty.challenging: 10,
  };

  factory GameSettings.fromMap(Map m) => GameSettings(
    category: Category.values.byName(m['category'] as String? ?? 'telugu'),
    customNames: List<String>.from(m['customNames'] as List? ?? const []),
    rounds: _int(m['rounds'], 7),
    turnSeconds: _int(m['turnSeconds'], 20),
    difficulty: Difficulty.values.byName(
      m['difficulty'] as String? ?? 'normal',
    ),
    timeoutPolicy: TimeoutPolicy.values.byName(
      m['timeoutPolicy'] as String? ?? 'passIncoming',
    ),
    winPoints: _int(m['winPoints'], 1000),
    characters: (m['characters'] as List? ?? const [])
        .map(CharacterDef.fromMap)
        .toList(),
  );
}

class PlayerInfo {
  const PlayerInfo({
    required this.uid,
    required this.name,
    required this.ready,
    required this.left,
    required this.joinedAt,
  });
  final String uid;
  final String name;
  final bool ready;
  final bool left;
  final int joinedAt;
}

class Standing {
  const Standing({
    required this.uid,
    required this.name,
    required this.total,
    required this.movieWins,
    required this.rank,
    required this.title,
    required this.left,
    this.tiebreak,
  });
  final String uid;
  final String name;
  final int total;
  final int movieWins;
  final int rank;
  final String? title;
  final bool left;

  /// Points from a tie-breaker round, for players who played one.
  final int? tiebreak;

  factory Standing.fromMap(Object? o) {
    final m = o as Map;
    return Standing(
      uid: m['uid'] as String,
      name: m['name'] as String,
      total: _int(m['total']),
      movieWins: _int(m['movieWins']),
      rank: _int(m['rank'], 1),
      title: m['title'] as String?,
      left: m['left'] == true,
      tiebreak: (m['tiebreak'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toJson() => {
    'uid': uid,
    'name': name,
    'total': total,
    'movieWins': movieWins,
    'rank': rank,
    'title': title,
    'left': left,
    'tiebreak': tiebreak,
  };
}

enum RoomStatus { lobby, playing, tiebreakVote, finished, closed }

/// A tie for King or Queen after the last round, and the tied players' vote.
class TiebreakInfo {
  const TiebreakInfo({
    required this.title,
    required this.uids,
    required this.votes,
    required this.deadline,
    required this.stage,
  });
  final String title;
  final List<String> uids;
  final Map<String, bool> votes;
  final DateTime deadline;

  /// vote | playing | declined | done | cancelled
  final String stage;

  factory TiebreakInfo.fromMap(Map m) => TiebreakInfo(
    title: m['title'] as String? ?? 'King',
    uids: List<String>.from(m['uids'] as List? ?? const []),
    votes: _map(m['votes'], (v) => v == true),
    deadline: _time(m['deadline']) ?? DateTime.now(),
    stage: m['stage'] as String? ?? 'vote',
  );
}

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostUid,
    required this.status,
    required this.memberUids,
    required this.players,
    required this.settings,
    required this.gameNo,
    required this.currentRound,
    required this.currentRoundKey,
    required this.totals,
    required this.movieWins,
    required this.finalStandings,
    this.tiebreak,
    this.tiebreakScores,
    this.mode = GameMode.movie,
    this.kqSettings,
    this.kingWins = const {},
  });

  final String id;
  final String code;
  final String hostUid;
  final RoomStatus status;
  final List<String> memberUids;
  final Map<String, PlayerInfo> players;
  final GameSettings settings;
  final int gameNo;
  final int currentRound;
  final String? currentRoundKey;
  final Map<String, int> totals;
  final Map<String, int> movieWins;
  final List<Standing>? finalStandings;
  final TiebreakInfo? tiebreak;
  final Map<String, int>? tiebreakScores;
  final GameMode mode;
  final KqSettings? kqSettings;
  final Map<String, int> kingWins;

  bool get isKq => mode == GameMode.kingQueen;

  /// Rounds in the game, for either mode.
  int get totalRounds => isKq ? (kqSettings?.rounds ?? 7) : settings.rounds;

  String nameOf(String uid) => players[uid]?.name ?? 'Player';

  List<PlayerInfo> get activePlayers =>
      memberUids.map((u) => players[u]).whereType<PlayerInfo>().toList();

  bool everyoneReady() =>
      activePlayers.every((p) => p.ready || p.uid == hostUid);

  factory Room.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) =>
      Room.fromMap(s.id, s.data()!);

  factory Room.fromMap(String id, Map<String, dynamic> m) {
    final players = <String, PlayerInfo>{};
    (m['players'] as Map? ?? {}).forEach((k, v) {
      final p = v as Map;
      players[k as String] = PlayerInfo(
        uid: k,
        name: p['name'] as String? ?? 'Player',
        ready: p['ready'] == true,
        left: p['left'] == true,
        joinedAt: _int(p['joinedAt']),
      );
    });
    return Room(
      id: id,
      code: m['code'] as String,
      hostUid: m['hostUid'] as String,
      status: RoomStatus.values.byName(m['status'] as String),
      memberUids: List<String>.from(m['memberUids'] as List),
      players: players,
      settings: GameSettings.fromMap(m['settings'] as Map),
      gameNo: _int(m['gameNo'], 1),
      currentRound: _int(m['currentRound']),
      currentRoundKey: m['currentRoundKey'] as String?,
      totals: _map(m['totals'], _int),
      movieWins: _map(m['movieWins'], _int),
      finalStandings: (m['final'] as List?)?.map(Standing.fromMap).toList(),
      tiebreak: m['tiebreak'] == null
          ? null
          : TiebreakInfo.fromMap(m['tiebreak'] as Map),
      tiebreakScores: m['tiebreakScores'] == null
          ? null
          : _map(m['tiebreakScores'], _int),
      mode: m['mode'] == 'kingQueen' ? GameMode.kingQueen : GameMode.movie,
      kqSettings: m['kqSettings'] == null
          ? null
          : KqSettings.fromMap(m['kqSettings'] as Map),
      kingWins: _map(m['kingWins'], _int),
    );
  }
}

enum RoundStatus { picking, exchange, characters, revealed, aborted }

class LastAction {
  const LastAction(this.type, this.fromUid, this.toUid, this.turnId);
  final String type;
  final String fromUid;
  final String toUid;
  final int turnId;
  bool get isTimeout => type == 'timeout';
}

class RoundWinner {
  const RoundWinner(this.uid, this.movie, this.points);
  final String uid;
  final String movie;
  final int points;
}

class Round {
  const Round({
    required this.key,
    required this.gameNo,
    required this.roundNo,
    this.tiebreak = false,
    required this.status,
    required this.order,
    required this.turnId,
    required this.currentUid,
    required this.nextUid,
    required this.timed,
    required this.turnSeconds,
    this.chits = const [],
    this.picks = const {},
    this.pickOpensAt,
    this.pickDeadline,
    this.charChits = const [],
    this.charPicks = const {},
    this.charPickOpensAt,
    this.charPickDeadline,
    required this.introEndsAt,
    required this.turnDeadline,
    required this.movieNames,
    required this.handSizes,
    required this.lastAction,
    required this.winner,
    required this.revealAt,
    required this.revealedHands,
    required this.characters,
    required this.scores,
    required this.abortedReason,
  });

  final String key;
  final int gameNo;
  final int roundNo;

  /// An extra round among tied players; its points never reach totals.
  final bool tiebreak;
  final RoundStatus status;
  final List<String> order;
  final int turnId;
  final String currentUid;
  final String nextUid;
  final bool timed;
  final int turnSeconds;

  /// Folded movie chits on the table (opaque ids) and who picked each.
  final List<String> chits;
  final Map<String, String> picks;
  final DateTime? pickOpensAt;
  final DateTime? pickDeadline;

  /// Folded character chits (opaque ids) and who picked each.
  final List<String> charChits;
  final Map<String, String> charPicks;
  final DateTime? charPickOpensAt;
  final DateTime? charPickDeadline;
  final DateTime introEndsAt;
  final DateTime turnDeadline;
  final List<String> movieNames;
  final Map<String, int> handSizes;
  final LastAction? lastAction;
  final RoundWinner? winner;
  final DateTime? revealAt;
  final Map<String, List<GameCard>>? revealedHands;
  final Map<String, CharacterDef>? characters;
  final Map<String, int>? scores;
  final String? abortedReason;

  factory Round.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) =>
      Round.fromMap(s.id, s.data()!);

  factory Round.fromMap(String id, Map<String, dynamic> m) {
    final la = m['lastAction'] as Map?;
    final w = m['winner'] as Map?;
    return Round(
      key: id,
      gameNo: _int(m['gameNo'], 1),
      roundNo: _int(m['roundNo'], 1),
      tiebreak: m['tiebreak'] == true,
      status: RoundStatus.values.byName(m['status'] as String),
      order: List<String>.from(m['order'] as List),
      turnId: _int(m['turnId']),
      currentUid: m['currentUid'] as String,
      nextUid: m['nextUid'] as String,
      timed: m['timed'] != false,
      turnSeconds: _int(m['turnSeconds'], 20),
      chits: List<String>.from(m['chits'] as List? ?? const []),
      picks: _map(m['picks'], (v) => v as String),
      pickOpensAt: _time(m['pickOpensAt']),
      pickDeadline: _time(m['pickDeadline']),
      charChits: List<String>.from(m['charChits'] as List? ?? const []),
      charPicks: _map(m['charPicks'], (v) => v as String),
      charPickOpensAt: _time(m['charPickOpensAt']),
      charPickDeadline: _time(m['charPickDeadline']),
      introEndsAt: _time(m['introEndsAt']) ?? DateTime.now(),
      turnDeadline: _time(m['turnDeadline']) ?? DateTime.now(),
      movieNames: List<String>.from(m['movieNames'] as List? ?? const []),
      handSizes: _map(m['handSizes'], _int),
      lastAction: la == null
          ? null
          : LastAction(
              la['type'] as String,
              la['fromUid'] as String,
              la['toUid'] as String,
              _int(la['turnId']),
            ),
      winner: w == null
          ? null
          : RoundWinner(
              w['uid'] as String,
              w['movie'] as String,
              _int(w['points']),
            ),
      revealAt: _time(m['revealAt']),
      revealedHands: m['revealedHands'] == null
          ? null
          : _map(
              m['revealedHands'],
              (v) => (v as List).map(GameCard.fromMap).toList(),
            ),
      characters: m['characters'] == null
          ? null
          : _map(m['characters'], CharacterDef.fromMap),
      scores: m['scores'] == null ? null : _map(m['scores'], _int),
      abortedReason: m['abortedReason'] as String?,
    );
  }
}

class Hand {
  const Hand({
    required this.roundKey,
    required this.cards,
    required this.incomingCardId,
    required this.character,
  });
  final String roundKey;
  final List<GameCard> cards;
  final String? incomingCardId;
  final CharacterDef? character;

  factory Hand.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) {
    final m = s.data()!;
    return Hand(
      roundKey: m['roundKey'] as String,
      cards: (m['cards'] as List).map(GameCard.fromMap).toList(),
      incomingCardId: m['incomingCardId'] as String?,
      character: m['character'] == null
          ? null
          : CharacterDef.fromMap(m['character']),
    );
  }
}

/// Name of the movie a hand holds four of, if any (pure, used by UI hints).
String? matchingName(List<GameCard> cards, {int need = 4}) {
  final counts = <String, int>{};
  for (final c in cards) {
    counts[c.name] = (counts[c.name] ?? 0) + 1;
  }
  for (final e in counts.entries) {
    if (e.value >= need) return e.key;
  }
  return null;
}

// ---------------------------------------------------------------------------
// King & Queen (docs/KING_QUEEN_RULES.md)
// ---------------------------------------------------------------------------

enum GameMode { movie, kingQueen }

class KqRoleDef {
  const KqRoleDef({
    required this.key,
    required this.name,
    required this.points,
    required this.core,
  });
  final String key;
  final String name;
  final int points;
  final bool core;

  factory KqRoleDef.fromMap(Object? o) {
    final m = o as Map;
    return KqRoleDef(
      key: m['key'] as String,
      name: m['name'] as String,
      points: _int(m['points']),
      core: m['core'] == true,
    );
  }

  Map<String, Object> toMap() => {'key': key, 'name': name, 'points': points};
}

class KqSettings {
  const KqSettings({
    required this.rounds,
    required this.turnSeconds,
    required this.roles,
  });
  final int rounds;
  final int turnSeconds;
  final List<KqRoleDef> roles;

  static const roundOptions = [5, 7, 10, 15];

  /// Optional roles join in this order as players increase (rules §1).
  static const optionalOrder = [
    'minister',
    'commander',
    'merchant',
    'poet',
    'farmer',
    'jester',
  ];

  /// The role chain for [players] players, in catalogue order.
  List<KqRoleDef> chainFor(int players) {
    final wanted = {
      ...roles.where((r) => r.core).map((r) => r.key),
      ...optionalOrder.take((players - 4).clamp(0, 6)),
    };
    return roles.where((r) => wanted.contains(r.key)).toList();
  }

  factory KqSettings.fromMap(Map? m) => KqSettings(
    rounds: _int(m?['rounds'], 7),
    turnSeconds: _int(m?['turnSeconds'], 20),
    roles: (m?['roles'] as List? ?? const []).map(KqRoleDef.fromMap).toList(),
  );
}

enum KqStatus { picking, guessing, revealed, aborted }

class KqGuessRecord {
  const KqGuessRecord({
    required this.step,
    required this.guesser,
    required this.target,
    required this.correct,
    required this.kind,
  });
  final int step;
  final String guesser;
  final String target;
  final bool correct;

  /// guess | forced | timeout
  final String kind;

  factory KqGuessRecord.fromMap(Object? o) {
    final m = o as Map;
    return KqGuessRecord(
      step: _int(m['step']),
      guesser: m['guesser'] as String,
      target: m['target'] as String,
      correct: m['correct'] == true,
      kind: m['kind'] as String? ?? 'guess',
    );
  }
}

/// Public King & Queen round state. Hidden roles never appear here until
/// [revealedRoles] is written at the end of the round.
class KqRound {
  const KqRound({
    required this.key,
    required this.gameNo,
    required this.roundNo,
    required this.status,
    required this.players,
    required this.chain,
    required this.chainPoints,
    required this.chits,
    required this.picks,
    required this.pickOpensAt,
    required this.pickDeadline,
    required this.step,
    required this.guesser,
    required this.locked,
    required this.excluded,
    required this.turnId,
    required this.timed,
    required this.turnSeconds,
    required this.guessOpensAt,
    required this.turnDeadline,
    required this.history,
    required this.revealedRoles,
    required this.scores,
    required this.abortedReason,
  });

  final String key;
  final int gameNo;
  final int roundNo;
  final KqStatus status;
  final List<String> players;
  final List<String> chain;
  final List<int> chainPoints;
  final List<String> chits;
  final Map<String, String> picks;
  final DateTime? pickOpensAt;
  final DateTime? pickDeadline;
  final int step;
  final String? guesser;
  final Map<String, int> locked;
  final List<String> excluded;
  final int turnId;
  final bool timed;
  final int turnSeconds;
  final DateTime? guessOpensAt;
  final DateTime? turnDeadline;
  final List<KqGuessRecord> history;
  final Map<String, int>? revealedRoles;
  final Map<String, int>? scores;
  final String? abortedReason;

  /// The role the guesser holds and the one they are looking for.
  String get seekerRole => chain[step.clamp(0, chain.length - 1)];
  String get targetRole => chain[(step + 1).clamp(0, chain.length - 1)];

  /// Players the guesser may pick right now.
  List<String> get candidates {
    if (status != KqStatus.guessing || guesser == null) return const [];
    final out = {...locked.keys, guesser!, ...excluded};
    return players.where((p) => !out.contains(p)).toList();
  }

  /// A player's publicly known role, if any (locked or current guesser).
  String? publicRoleOf(String uid) {
    final l = locked[uid];
    if (l != null) return chain[l];
    if (uid == guesser && status == KqStatus.guessing) return seekerRole;
    final r = revealedRoles?[uid];
    return r == null ? null : chain[r];
  }

  factory KqRound.fromMap(String id, Map<String, dynamic> m) => KqRound(
    key: id,
    gameNo: _int(m['gameNo'], 1),
    roundNo: _int(m['roundNo'], 1),
    status: KqStatus.values.byName(m['status'] as String),
    players: List<String>.from(m['players'] as List? ?? const []),
    chain: List<String>.from(m['chain'] as List? ?? const []),
    chainPoints: (m['chainPoints'] as List? ?? const [])
        .map((e) => _int(e))
        .toList(),
    chits: List<String>.from(m['chits'] as List? ?? const []),
    picks: _map(m['picks'], (v) => v as String),
    pickOpensAt: _time(m['pickOpensAt']),
    pickDeadline: _time(m['pickDeadline']),
    step: _int(m['step']),
    guesser: m['guesser'] as String?,
    locked: _map(m['locked'], _int),
    excluded: List<String>.from(m['excluded'] as List? ?? const []),
    turnId: _int(m['turnId']),
    timed: m['timed'] != false,
    turnSeconds: _int(m['turnSeconds'], 20),
    guessOpensAt: _time(m['guessOpensAt']),
    turnDeadline: _time(m['turnDeadline']),
    history: (m['history'] as List? ?? const [])
        .map(KqGuessRecord.fromMap)
        .toList(),
    revealedRoles: m['revealedRoles'] == null
        ? null
        : _map(m['revealedRoles'], _int),
    scores: m['scores'] == null ? null : _map(m['scores'], _int),
    abortedReason: m['abortedReason'] as String?,
  );
}

/// My own secret King & Queen role (owner-only document).
class KqMyRole {
  const KqMyRole({
    required this.roundKey,
    required this.index,
    required this.name,
    required this.points,
  });
  final String roundKey;
  final int? index;
  final String? name;
  final int? points;

  factory KqMyRole.fromMap(Map<String, dynamic> m) => KqMyRole(
    roundKey: m['roundKey'] as String? ?? '',
    index: (m['index'] as num?)?.toInt(),
    name: m['name'] as String?,
    points: (m['points'] as num?)?.toInt(),
  );
}
