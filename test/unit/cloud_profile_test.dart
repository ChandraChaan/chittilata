import 'package:chittilata/core/services/cloud_profile.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MatchRecord game(String key, int day) => MatchRecord(
  key: key,
  playedAt: DateTime.utc(2026, 11, day),
  rounds: 5,
  category: 'hollywood',
  standings: const [],
);

void main() {
  test('merging takes the larger counters and every badge, event and game', () {
    final phone = CloudProfile(
      counters: const {'games': 5, 'xp': 300, 'kings': 1},
      badges: const {'first_game', 'king'},
      seen: const ['a', 'b'],
      history: [game('r1-1', 3), game('r2-1', 5)],
    );
    final cloud = CloudProfile(
      counters: const {'games': 7, 'xp': 200, 'queens': 2},
      badges: const {'first_game', 'queen'},
      seen: const ['x', 'a'],
      history: [game('r3-1', 4), game('r1-1', 3)],
    );
    final m = phone.merge(cloud);
    expect(m.counters, {'games': 7, 'xp': 300, 'kings': 1, 'queens': 2});
    expect(m.badges, {'first_game', 'king', 'queen'});
    expect(m.seen, ['x', 'a', 'b']);
    expect(m.history.map((h) => h.key), ['r2-1', 'r3-1', 'r1-1']);
    // Merging is idempotent: syncing again changes nothing.
    expect(m.merge(cloud).sameAs(m), isTrue);
    expect(cloud.merge(m).sameAs(m), isTrue);
  });

  test('the cloud name wins unless this phone just changed it', () {
    const phone = CloudProfile(name: 'New', avatar: '🦁');
    const cloud = CloudProfile(name: 'Old', avatar: null);
    expect(phone.merge(cloud).name, 'Old');
    expect(phone.merge(cloud).avatar, isNull);
    expect(phone.merge(cloud, preferMine: true).name, 'New');
    expect(phone.merge(cloud, preferMine: true).avatar, '🦁');
    // A fresh cloud profile takes the phone's.
    expect(phone.merge(const CloudProfile()).name, 'New');
    expect(phone.merge(const CloudProfile()).avatar, '🦁');
  });

  test('the stored form keeps to what the security rules accept', () {
    final p = CloudProfile(
      name: 'A very long name over sixteen',
      counters: const {'games': 2, 'unknown': 9, 'xp': -5},
      badges: const {'king', 'made_up'},
      seen: List.generate(400, (i) => 'k$i'),
      history: List.generate(60, (i) => game('g$i', 1)),
    );
    final m = p.toMap();
    expect(m['name'], 'A very long name');
    expect(m['counters'], {'games': 2, 'xp': 0});
    expect(m['badges'], ['king']);
    expect((m['seen'] as List).length, 300);
    expect((m['seen'] as List).last, 'k399');
    expect((m['history'] as List).length, 50);
    final back = CloudProfile.fromMap(m);
    expect(back.counters['games'], 2);
    expect(back.history.length, 50);
  });

  test('a malformed stored profile is read as far as possible', () {
    final p = CloudProfile.fromMap({
      'counters': {'games': 3, 'xp': 'lots'},
      'badges': ['king', 7],
      'history': [
        {'bad': true},
        game('r1-1', 2).toJson(),
      ],
    });
    expect(p.counters, {'games': 3});
    expect(p.badges, {'king'});
    expect(p.history.single.key, 'r1-1');
    expect(p.name, isNull);
  });

  test('the phone profile round-trips through preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await Preferences.load();
    prefs.playerName = 'Chandra';
    prefs.stats.record('game:r1:1', {'games': 1, 'xp': 50});
    prefs.addHistory(game('r1-1', 2));
    final mine = CloudProfile.fromPrefs(prefs);
    expect(mine.counters, {'games': 1, 'xp': 50});
    expect(mine.badges, {'first_game'});
    final merged = mine.merge(
      const CloudProfile(
        counters: {'games': 9, 'kings': 1},
        badges: {'king', 'regular'},
      ),
    );
    prefs.applyProfile(
      name: merged.name,
      avatar: merged.avatar,
      counters: merged.counters,
      badges: merged.badges,
      seen: merged.seen,
      history: merged.history,
    );
    expect(prefs.stats.counters['games'], 9);
    // A badge kept from another phone shows even without its counter.
    expect(
      prefs.stats.earned.map((b) => b.id),
      containsAll(['first_game', 'king', 'regular']),
    );
    expect(prefs.history.single.key, 'r1-1');
    expect(prefs.playerName, 'Chandra');
    prefs.clearProfile();
    expect(prefs.stats.counters, isEmpty);
    expect(prefs.history, isEmpty);
    expect(prefs.playerName, 'Chandra');
    prefs.clearProfile(identity: true);
    expect(prefs.playerName, '');
  });
}
