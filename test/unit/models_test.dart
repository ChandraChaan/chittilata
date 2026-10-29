import 'package:chittilata/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a room document written by the server', () {
    final room = Room.fromMap('r1', {
      'code': 'ABC234',
      'hostUid': 'a',
      'status': 'playing',
      'memberUids': ['a', 'b'],
      'players': {
        'a': {'name': 'Chandra', 'ready': true, 'left': false, 'joinedAt': 1},
        'b': {'name': 'Vasavi', 'ready': false, 'left': false, 'joinedAt': 2},
      },
      'settings': {
        'category': 'hollywood',
        'customNames': [],
        'rounds': 10,
        'turnSeconds': 15,
        'difficulty': 'challenging',
        'timeoutPolicy': 'passRandom',
        'winPoints': 1200,
        'characters': [
          {'name': 'Queen', 'points': 800},
          {'name': 'Thief', 'points': 100},
        ],
      },
      'gameNo': 2,
      'currentRound': 3,
      'currentRoundKey': 'g2r03',
      'totals': {'a': 1800},
      'movieWins': {'a': 1},
      'final': null,
    });
    expect(room.status, RoomStatus.playing);
    expect(room.settings.category, Category.hollywood);
    expect(room.settings.timeoutPolicy, TimeoutPolicy.passRandom);
    expect(room.settings.characters.first.name, 'Queen');
    expect(room.nameOf('b'), 'Vasavi');
    expect(room.everyoneReady(), isFalse);
    expect(room.totals['a'], 1800);
  });

  test('parses a revealed round and keeps secrets null before reveal', () {
    final active = Round.fromMap('g1r01', {
      'status': 'exchange',
      'order': ['a', 'b', 'c'],
      'turnId': 4,
      'currentUid': 'b',
      'nextUid': 'c',
      'turnSeconds': 20,
      'introEndsAt': 1000,
      'turnDeadline': 21000,
      'movieNames': ['RRR', 'Devara', 'Salaar'],
      'handSizes': {'a': 4, 'b': 5, 'c': 3},
      'revealedHands': null,
      'characters': null,
      'scores': null,
    });
    expect(active.revealedHands, isNull);
    expect(active.characters, isNull);
    expect(active.handSizes['b'], 5);
    expect(active.turnDeadline.millisecondsSinceEpoch, 21000);

    final done = Round.fromMap('g1r01', {
      'status': 'revealed',
      'order': ['a', 'b', 'c'],
      'currentUid': 'a',
      'nextUid': 'b',
      'winner': {'uid': 'a', 'movie': 'RRR', 'points': 1000},
      'revealedHands': {
        'a': [
          {'id': '1', 'name': 'RRR'},
        ],
      },
      'characters': {
        'b': {'name': 'Queen', 'points': 800},
      },
      'scores': {'a': 1000, 'b': 800, 'c': 100},
    });
    expect(done.winner!.movie, 'RRR');
    expect(done.revealedHands!['a']!.single.name, 'RRR');
    expect(done.characters!['b']!.points, 800);
  });

  test('matchingName finds four of a kind only', () {
    const a = GameCard(id: '1', name: 'A');
    expect(matchingName([a, a, a, const GameCard(id: '2', name: 'B')]), isNull);
    expect(
      matchingName(const [
        GameCard(id: '1', name: 'A'),
        GameCard(id: '2', name: 'A'),
        GameCard(id: '3', name: 'A'),
        GameCard(id: '4', name: 'A'),
        GameCard(id: '5', name: 'B'),
      ]),
      'A',
    );
  });
}
