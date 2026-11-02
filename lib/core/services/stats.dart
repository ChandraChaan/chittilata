import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Profile avatars (same list as the server's AVATARS).
const avatarChoices = [
  '🦁', '🐯', '🐼', '🦊', '🐸', '🐵', '🦄', '🐲', '🐘', '🦚', '🐢', '🐙', //
  '🦋', '🐝', '🌻', '🪷', '🥭', '🌶️', '🍉', '🍿', '🎬', '👑', '⭐', '🔥',
  '🪁', '🎯', '🎲', '🎭', '🚀', '⚡', '🌙', '🏏',
];

/// A badge and the counter that unlocks it.
class Achievement {
  const Achievement(
    this.id,
    this.emoji,
    this.title,
    this.how,
    this.stat,
    this.goal,
  );
  final String id;
  final String emoji;
  final String title;
  final String how;
  final String stat;
  final int goal;
}

const achievements = [
  Achievement('first_game', '🎉', 'First game', 'Finish a game', 'games', 1),
  Achievement(
    'first_win',
    '🎬',
    'Four of a kind',
    'Win a round',
    'roundWins',
    1,
  ),
  Achievement(
    'king',
    '👑',
    'King of the table',
    'Finish a game as King',
    'kings',
    1,
  ),
  Achievement(
    'queen',
    '👸',
    'Queen bee',
    'Finish a game as Queen',
    'queens',
    1,
  ),
  Achievement(
    'hat_trick',
    '🎩',
    'Hat-trick',
    'Win 3 rounds in one game',
    'hatTricks',
    1,
  ),
  Achievement(
    'crowned',
    '🤴',
    'Royal blood',
    'End 5 King & Queen rounds as King',
    'kingRounds',
    5,
  ),
  Achievement('regular', '🔟', 'Regular', 'Play 10 games', 'games', 10),
  Achievement('legend', '🏆', 'Legend', 'Play 50 games', 'games', 50),
  Achievement(
    'bot_buster',
    '🤖',
    'Bot buster',
    'Win a game against bots',
    'botWins',
    1,
  ),
  Achievement(
    'big_table',
    '🎪',
    'Full house',
    'Play with 8 or more players',
    'bigTables',
    1,
  ),
  Achievement(
    'chatterbox',
    '💬',
    'Chatterbox',
    'Send 50 quick chats',
    'chats',
    50,
  ),
  Achievement(
    'nudger',
    '👋',
    'Hurry up!',
    'Nudge 10 slow players',
    'nudges',
    10,
  ),
  Achievement(
    'night_owl',
    '🦉',
    'Night owl',
    'Finish a game after midnight',
    'nightGames',
    1,
  ),
  Achievement(
    'festive',
    '🪔',
    'Festive spirit',
    'Play during a festival',
    'festivalGames',
    1,
  ),
];

/// Your games, wins, XP, level and badges. Kept only on this phone.
class PlayerStats {
  PlayerStats(this._p);
  final SharedPreferences _p;

  Map<String, int> get counters {
    try {
      final raw = jsonDecode(_p.getString('stats') ?? '{}') as Map;
      return raw.map((k, v) => MapEntry(k as String, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  List<String> get _seen => _p.getStringList('statsSeen') ?? const [];

  int get xp => counters['xp'] ?? 0;

  /// Level n needs 100·n·(n+1)/2 XP in total: 100, 300, 600, 1000…
  int get level {
    var n = 1;
    while (xp >= _total(n)) {
      n++;
    }
    return n;
  }

  static int _total(int n) => 100 * n * (n + 1) ~/ 2;

  /// Progress through the current level, 0–1.
  double get levelProgress {
    final n = level;
    final from = _total(n - 1);
    return ((xp - from) / (_total(n) - from)).clamp(0.0, 1.0);
  }

  int get xpToNext => _total(level) - xp;

  List<Achievement> get earned =>
      achievements.where((b) => (counters[b.stat] ?? 0) >= b.goal).toList();

  /// Adds [add] to the counters once per [key] (so a room shown twice
  /// counts once). Returns the badges this just unlocked.
  List<Achievement> record(String key, Map<String, int> add) {
    final seen = _seen;
    if (seen.contains(key)) return const [];
    final before = earned.map((b) => b.id).toSet();
    final c = counters;
    add.forEach((k, v) => c[k] = (c[k] ?? 0) + v);
    _p.setString('stats', jsonEncode(c));
    _p.setStringList('statsSeen', [
      ...seen.length > 300 ? seen.sublist(seen.length - 300) : seen,
      key,
    ]);
    return earned.where((b) => !before.contains(b.id)).toList();
  }
}
