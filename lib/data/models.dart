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
        difficulty:
            Difficulty.values.byName(m['difficulty'] as String? ?? 'normal'),
        timeoutPolicy: TimeoutPolicy.values
            .byName(m['timeoutPolicy'] as String? ?? 'passIncoming'),
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
  });
  final String uid;
  final String name;
  final int total;
  final int movieWins;
  final int rank;
  final String? title;
  final bool left;

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
      };
}

enum RoomStatus { lobby, playing, finished, closed }

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
    );
  }
}

enum RoundStatus { exchange, characters, revealed, aborted }

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
    required this.status,
    required this.order,
    required this.turnId,
    required this.currentUid,
    required this.nextUid,
    required this.timed,
    required this.turnSeconds,
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
  final RoundStatus status;
  final List<String> order;
  final int turnId;
  final String currentUid;
  final String nextUid;
  final bool timed;
  final int turnSeconds;
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
      status: RoundStatus.values.byName(m['status'] as String),
      order: List<String>.from(m['order'] as List),
      turnId: _int(m['turnId']),
      currentUid: m['currentUid'] as String,
      nextUid: m['nextUid'] as String,
      timed: m['timed'] != false,
      turnSeconds: _int(m['turnSeconds'], 20),
      introEndsAt: _time(m['introEndsAt']) ?? DateTime.now(),
      turnDeadline: _time(m['turnDeadline']) ?? DateTime.now(),
      movieNames: List<String>.from(m['movieNames'] as List? ?? const []),
      handSizes: _map(m['handSizes'], _int),
      lastAction: la == null
          ? null
          : LastAction(la['type'] as String, la['fromUid'] as String,
              la['toUid'] as String, _int(la['turnId'])),
      winner: w == null
          ? null
          : RoundWinner(
              w['uid'] as String, w['movie'] as String, _int(w['points'])),
      revealAt: _time(m['revealAt']),
      revealedHands: m['revealedHands'] == null
          ? null
          : _map(m['revealedHands'],
              (v) => (v as List).map(GameCard.fromMap).toList()),
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
      character:
          m['character'] == null ? null : CharacterDef.fromMap(m['character']),
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
