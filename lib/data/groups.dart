import 'package:cloud_firestore/cloud_firestore.dart';

/// A saved circle of friends with a monthly leaderboard.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerUid,
    required this.memberUids,
    required this.members,
  });
  final String id;
  final String name;
  final String code;
  final String ownerUid;
  final List<String> memberUids;
  final Map<String, GroupMember> members;

  String nameOf(String uid) => members[uid]?.name ?? 'Player';

  factory Group.fromMap(String id, Map<String, dynamic> m) => Group(
    id: id,
    name: m['name'] as String? ?? 'Group',
    code: m['code'] as String? ?? '',
    ownerUid: m['ownerUid'] as String? ?? '',
    memberUids: List<String>.from(m['memberUids'] as List? ?? const []),
    members: {
      for (final e in (m['members'] as Map? ?? {}).entries)
        e.key as String: GroupMember(
          name: (e.value as Map)['name'] as String? ?? 'Player',
          avatar: (e.value as Map)['avatar'] as String?,
        ),
    },
  );

  factory Group.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) =>
      Group.fromMap(s.id, s.data()!);
}

class GroupMember {
  const GroupMember({required this.name, this.avatar});
  final String name;
  final String? avatar;
}

/// One month of a group's games.
class Season {
  const Season({
    required this.id,
    this.points = const {},
    this.games = const {},
    this.kings = const {},
    this.queens = const {},
  });
  final String id;
  final Map<String, int> points;
  final Map<String, int> games;
  final Map<String, int> kings;
  final Map<String, int> queens;

  /// Members who played, best first (points, then King titles).
  List<String> get ranking {
    final uids = games.keys.toList();
    uids.sort((a, b) {
      final p = (points[b] ?? 0).compareTo(points[a] ?? 0);
      return p != 0 ? p : (kings[b] ?? 0).compareTo(kings[a] ?? 0);
    });
    return uids;
  }

  static Map<String, int> _ints(Object? m) => {
    for (final e in (m as Map? ?? {}).entries)
      e.key as String: (e.value as num).toInt(),
  };

  factory Season.fromMap(String id, Map<String, dynamic>? m) => Season(
    id: id,
    points: _ints(m?['points']),
    games: _ints(m?['games']),
    kings: _ints(m?['kings']),
    queens: _ints(m?['queens']),
  );

  /// The season (calendar month in India) a time falls in, e.g. "2026-11".
  static String idFor(DateTime t) => t
      .toUtc()
      .add(const Duration(hours: 5, minutes: 30))
      .toIso8601String()
      .substring(0, 7);

  static String previous(String id) {
    final y = int.parse(id.substring(0, 4));
    final m = int.parse(id.substring(5, 7));
    return m == 1 ? '${y - 1}-12' : '$y-${(m - 1).toString().padLeft(2, '0')}';
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];

  static String label(String id) =>
      '${_months[int.parse(id.substring(5, 7)) - 1]} ${id.substring(0, 4)}';
}
