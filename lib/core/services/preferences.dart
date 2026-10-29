import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local preferences and history. Nothing here is game-authoritative.
class Preferences extends ChangeNotifier {
  Preferences(this._p);
  final SharedPreferences _p;

  static Future<Preferences> load() async =>
      Preferences(await SharedPreferences.getInstance());

  String get playerName => _p.getString('playerName') ?? '';
  set playerName(String v) {
    _p.setString('playerName', v);
    notifyListeners();
  }

  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _p.setBool('onboarded', v);

  bool get sound => _p.getBool('sound') ?? true;
  set sound(bool v) => _set('sound', v);

  bool get music => _p.getBool('music') ?? false;
  set music(bool v) => _set('music', v);

  bool get haptics => _p.getBool('haptics') ?? true;
  set haptics(bool v) => _set('haptics', v);

  /// 'system' | 'dark' | 'light'
  String get themeMode => _p.getString('themeMode') ?? 'dark';
  set themeMode(String v) {
    _p.setString('themeMode', v);
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
    _p.setStringList(
      'history',
      list.take(50).map((h) => jsonEncode(h.toJson())).toList(),
    );
    notifyListeners();
  }
}

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
