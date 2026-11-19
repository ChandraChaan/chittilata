import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stats.dart';

/// Device-local preferences and history. Nothing here is game-authoritative.
class Preferences extends ChangeNotifier {
  Preferences(this._p);
  final SharedPreferences _p;

  static Future<Preferences> load() async =>
      Preferences(await SharedPreferences.getInstance());

  /// Called when the profile (name, avatar, stats or history) changes, so a
  /// signed-in player's cloud profile can sync. [identity] is true for a
  /// name or avatar change, which then wins over the cloud copy.
  void Function({bool identity})? onProfileChanged;

  String get playerName => _p.getString('playerName') ?? '';
  set playerName(String v) {
    final changed = v != playerName;
    _p.setString('playerName', v);
    notifyListeners();
    if (changed) onProfileChanged?.call(identity: true);
  }

  /// Profile emoji shown to other players (null: initials).
  String? get avatar => _p.getString('avatar');
  set avatar(String? v) {
    final changed = v != avatar;
    v == null ? _p.remove('avatar') : _p.setString('avatar', v);
    notifyListeners();
    if (changed) onProfileChanged?.call(identity: true);
  }

  /// Games, wins, XP and badges (synced when signed in with Google).
  late final stats = PlayerStats(_p, onChange: () => onProfileChanged?.call());

  /// Takes a merged cloud profile without triggering another sync.
  void applyProfile({
    required String? name,
    required String? avatar,
    required Map<String, int> counters,
    required Set<String> badges,
    required List<String> seen,
    required List<MatchRecord> history,
  }) {
    if (name != null && name.isNotEmpty) {
      _p.setString('playerName', name);
      avatar == null ? _p.remove('avatar') : _p.setString('avatar', avatar);
    }
    stats.replace(counters: counters, badges: badges, seen: seen);
    _saveHistory(history);
    notifyListeners();
  }

  /// Forgets this phone's profile: stats, badges, history and the room to
  /// resume, plus the name and avatar when [identity] is true. Settings such
  /// as sound and theme stay.
  void clearProfile({bool identity = false}) {
    stats.clear();
    _p.remove('history');
    _p.remove('activeRoomId');
    if (identity) {
      _p.remove('playerName');
      _p.remove('avatar');
    }
    notifyListeners();
  }

  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _p.setBool('onboarded', v);

  bool get sound => _p.getBool('sound') ?? true;
  set sound(bool v) => _set('sound', v);

  bool get music => _p.getBool('music') ?? true;
  set music(bool v) => _set('music', v);

  bool get notifications => _p.getBool('notifications') ?? true;
  set notifications(bool v) => _set('notifications', v);

  bool get haptics => _p.getBool('haptics') ?? true;
  set haptics(bool v) => _set('haptics', v);

  /// The movie list new rooms start with: 'hollywood' (English titles, the
  /// default), 'telugu', 'indian' or 'mixed'. The host can still change it in
  /// the lobby.
  String get movieList {
    final v = _p.getString('movieList');
    return const ['hollywood', 'telugu', 'indian', 'mixed'].contains(v)
        ? v!
        : 'hollywood';
  }

  set movieList(String v) {
    _p.setString('movieList', v);
    _p.setBool('movieListChosen', true);
    notifyListeners();
  }

  /// Whether the player has picked a movie list yet (asked once).
  bool get movieListChosen => _p.getBool('movieListChosen') ?? false;

  /// Show messages other players type (emojis and preset lines always show).
  bool get typedChat => _p.getBool('typedChat') ?? true;
  set typedChat(bool v) => _set('typedChat', v);

  /// Players whose chat this phone hides (their anonymous ids).
  Set<String> get mutedPlayers =>
      (_p.getStringList('mutedPlayers') ?? const []).toSet();

  bool isMuted(String uid) => mutedPlayers.contains(uid);

  void setMuted(String uid, bool muted) {
    final s = mutedPlayers;
    muted ? s.add(uid) : s.remove(uid);
    // Keep the newest 200: enough for anyone, bounded on disk.
    final list = s.toList();
    _p.setStringList(
      'mutedPlayers',
      list.length > 200 ? list.sublist(list.length - 200) : list,
    );
    notifyListeners();
  }

  /// 'system' | 'dark' | 'light'
  String get themeMode => _p.getString('themeMode') ?? 'dark';
  set themeMode(String v) {
    _p.setString('themeMode', v);
    notifyListeners();
  }

  /// The newest build whose optional-update prompt was dismissed.
  int get dismissedUpdate => _p.getInt('dismissedUpdate') ?? 0;
  set dismissedUpdate(int v) {
    _p.setInt('dismissedUpdate', v);
    notifyListeners();
  }

  /// Festival look: 'auto' (around each festival), 'off', or a festival.
  String get festival => _p.getString('festival') ?? 'auto';
  set festival(String v) {
    _p.setString('festival', v);
    notifyListeners();
  }

  /// The room this device was last in, used to resume after a restart.
  String? get activeRoomId => _p.getString('activeRoomId');
  set activeRoomId(String? v) =>
      v == null ? _p.remove('activeRoomId') : _p.setString('activeRoomId', v);

  void _set(String key, bool v) {
    _p.setBool(key, v);
    notifyListeners();
  }

  List<MatchRecord> get history {
    final raw = _p.getStringList('history') ?? const [];
    return raw
        .map((s) {
          try {
            return MatchRecord.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<MatchRecord>()
        .toList();
  }

  /// Saves a finished game once (keyed by room + game number).
  void addHistory(MatchRecord r) {
    final list = history.where((h) => h.key != r.key).toList()..insert(0, r);
    _saveHistory(list);
    notifyListeners();
    onProfileChanged?.call();
  }

  void _saveHistory(List<MatchRecord> list) => _p.setStringList(
    'history',
    list.take(maxHistory).map((h) => jsonEncode(h.toJson())).toList(),
  );
}

/// How many finished games the history keeps.
const maxHistory = 50;

class MatchRecord {
  MatchRecord({
    required this.key,
    required this.playedAt,
    required this.rounds,
    required this.category,
    required this.standings,
  });

  final String key;
  final DateTime playedAt;
  final int rounds;
  final String category;
  final List<Map<String, dynamic>> standings;

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
    key: j['key'] as String,
    playedAt: DateTime.parse(j['playedAt'] as String),
    rounds: j['rounds'] as int,
    category: j['category'] as String,
    standings: List<Map<String, dynamic>>.from(j['standings'] as List),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'playedAt': playedAt.toIso8601String(),
    'rounds': rounds,
    'category': category,
    'standings': standings,
  };
}
