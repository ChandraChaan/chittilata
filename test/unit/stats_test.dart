import 'package:chittilata/core/services/stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PlayerStats stats;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stats = PlayerStats(await SharedPreferences.getInstance());
  });

  test('levels need 100, 300, 600… XP in total', () {
    expect(stats.level, 1);
    stats.record('a', {'xp': 99});
    expect(stats.level, 1);
    expect(stats.xpToNext, 1);
    stats.record('b', {'xp': 1});
    expect(stats.level, 2);
    stats.record('c', {'xp': 200});
    expect(stats.level, 3);
    expect(stats.levelProgress, 0);
  });

  test('the same event counts once; badges unlock once', () {
    final first = stats.record('game:r1:1', {'games': 1, 'kings': 1});
    expect(first.map((b) => b.id), containsAll(['first_game', 'king']));
    expect(stats.record('game:r1:1', {'games': 1}), isEmpty);
    expect(stats.counters['games'], 1);
    final second = stats.record('game:r1:2', {'games': 1});
    expect(second, isEmpty);
    expect(stats.counters['games'], 2);
  });

  test('progress badges need their full count', () {
    for (var i = 0; i < 9; i++) {
      stats.record('n$i', {'nudges': 1});
    }
    expect(stats.earned.map((b) => b.id), isNot(contains('nudger')));
    expect(stats.record('n9', {'nudges': 1}).single.id, 'nudger');
  });

  test('every badge counter name is one the app records', () {
    const recorded = {
      'games', 'roundWins', 'kings', 'queens', 'hatTricks', 'kingRounds', //
      'botWins', 'bigTables', 'chats', 'nudges', 'nightGames',
      'festivalGames',
    };
    for (final b in achievements) {
      expect(recorded, contains(b.stat), reason: b.id);
    }
  });
}
