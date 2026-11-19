import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

import 'preferences.dart';
import 'stats.dart';

/// A signed-in player's profile as stored in Firestore `users/{uid}`: the
/// name and avatar, stat counters, badges, the events already counted and
/// recent match history. firestore.rules checks the same shape.
class CloudProfile {
  const CloudProfile({
    this.name,
    this.avatar,
    this.counters = const {},
    this.badges = const {},
    this.seen = const [],
    this.history = const [],
  });

  final String? name;
  final String? avatar;
  final Map<String, int> counters;
  final Set<String> badges;

  /// Events already counted, oldest first (so a game counts once).
  final List<String> seen;

  /// Newest first.
  final List<MatchRecord> history;

  static const maxName = 16;

  /// What this phone has now.
  factory CloudProfile.fromPrefs(Preferences prefs) => CloudProfile(
    name: prefs.playerName.isEmpty ? null : prefs.playerName,
    avatar: prefs.avatar,
    counters: prefs.stats.counters,
    badges: prefs.stats.earned.map((b) => b.id).toSet(),
    seen: prefs.stats.seen,
    history: prefs.history,
  );

  /// Reads a stored profile, skipping anything malformed.
  factory CloudProfile.fromMap(Map<String, dynamic> m) {
    final counters = <String, int>{};
    final c = m['counters'];
    if (c is Map) {
      c.forEach((k, v) {
        if (k is String && v is num) counters[k] = v.toInt();
      });
    }
    List<T> listOf<T>(Object? v) =>
        v is List ? v.whereType<T>().toList() : <T>[];
    final history = <MatchRecord>[];
    for (final h in listOf<Map>(m['history'])) {
      try {
        history.add(MatchRecord.fromJson(Map<String, dynamic>.from(h)));
      } catch (_) {}
    }
    final name = m['name'];
    final avatar = m['avatar'];
    return CloudProfile(
      name: name is String && name.isNotEmpty ? name : null,
      avatar: avatar is String ? avatar : null,
      counters: counters,
      badges: listOf<String>(m['badges']).toSet(),
      seen: listOf<String>(m['seen']),
      history: history,
    );
  }

  /// The stored form: only known counters and badges, within the limits
  /// the security rules enforce.
  Map<String, dynamic> toMap() {
    final keys = counters.keys.where(counterKeys.contains).toList()..sort();
    final badgeIds = achievements.map((a) => a.id).toSet();
    return {
      'name': _clip(name),
      'avatar': avatar,
      'counters': {for (final k in keys) k: counters[k]!.clamp(0, 1000000000)},
      'badges': badges.where(badgeIds.contains).toList()..sort(),
      'seen': seen.length > maxSeenKeys
          ? seen.sublist(seen.length - maxSeenKeys)
          : seen,
      'history': history.take(maxHistory).map((h) => h.toJson()).toList(),
    };
  }

  static String? _clip(String? s) =>
      s == null || s.isEmpty ? null : s.characters.take(maxName).toString();

  /// Combines two copies of a profile (this phone's and the cloud's): the
  /// larger of each counter, every badge, every counted event and every
  /// game in either history. The name and avatar come from [other] when it
  /// has a name, unless [preferMine] (this phone just changed them).
  CloudProfile merge(CloudProfile other, {bool preferMine = false}) {
    final counters = {...other.counters};
    this.counters.forEach((k, v) {
      final o = counters[k];
      counters[k] = o == null || v > o ? v : o;
    });
    // The other copy's order, then this phone's newer events at the end.
    final theirs = other.seen.toSet();
    final seen = [
      ...other.seen,
      ...this.seen.where((k) => !theirs.contains(k)),
    ];
    final byKey = <String, MatchRecord>{
      for (final h in other.history) h.key: h,
      for (final h in history) h.key: h,
    };
    final merged = byKey.values.toList()
      ..sort((a, b) {
        final t = b.playedAt.compareTo(a.playedAt);
        return t != 0 ? t : a.key.compareTo(b.key);
      });
    // The name and avatar go together, from one side.
    final (first, second) = preferMine ? (this, other) : (other, this);
    final id = first.name != null ? first : second;
    return CloudProfile(
      name: id.name,
      avatar: id.avatar,
      counters: counters,
      badges: {...badges, ...other.badges},
      seen: seen,
      history: merged,
    );
  }

  /// Whether both store the same thing (no write needed).
  bool sameAs(CloudProfile other) =>
      jsonEncode(toMap()) == jsonEncode(other.toMap());
}
