import 'package:chittilata/app.dart';
import 'package:chittilata/core/services/app_updater.dart';
import 'package:chittilata/core/services/feedback.dart';
import 'package:chittilata/core/services/preferences.dart';
import 'package:chittilata/data/app_config.dart';
import 'package:chittilata/data/charades.dart';
import 'package:chittilata/data/models.dart';
import 'package:chittilata/data/groups.dart';
import 'package:chittilata/ui/screens/groups_screen.dart';
import 'package:chittilata/ui/screens/history_screen.dart';
import 'package:chittilata/ui/screens/home_screen.dart';
import 'package:chittilata/ui/screens/onboarding_screen.dart';
import 'package:chittilata/ui/screens/profile_screen.dart';
import 'package:chittilata/ui/screens/room_screen.dart';
import 'package:chittilata/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';

/// Every screen, on every kind of phone: nothing may overflow or throw.
/// (Behaviour is covered by the other tests; this one is only about layout.)
const devices = {
  'small phone, 130% text': (Size(640, 1280), 2.0, 1.3),
  'phone, 160% text': (Size(1080, 2400), 2.6, 1.6),
  'phone, 200% text': (Size(1080, 2400), 2.6, 2.0),
  'compact 16:9 phone': (Size(720, 1280), 2.0, 1.0),
  'tablet': (Size(1600, 2560), 2.0, 1.0),
};

DateTime ago(int s) => DateTime.now().subtract(Duration(seconds: s));
DateTime later(int s) => DateTime.now().add(Duration(seconds: s));

const hand = Hand(
  roundKey: 'g1r01',
  cards: myCards,
  incomingCardId: null,
  character: null,
);

const standings = [
  Standing(
    uid: 'v',
    name: 'Vasavi',
    total: 6000,
    movieWins: 3,
    rank: 1,
    title: 'King',
    left: false,
  ),
  Standing(
    uid: 'me',
    name: 'Chandra',
    total: 4200,
    movieWins: 2,
    rank: 2,
    title: 'Queen',
    left: false,
  ),
  Standing(
    uid: 's',
    name: 'Swetha',
    total: 900,
    movieWins: 0,
    rank: 3,
    title: null,
    left: false,
  ),
];

/// Each scene sets up the fake server and returns the screen to show.
final scenes = <String, Widget Function(FakeGameRepository)>{
  'home': (_) => const HomeScreen(),
  'settings': (_) => const SettingsScreen(),
  'profile': (_) => const ProfileScreen(),
  'friend groups': (_) => const GroupsScreen(),
  'a group': (r) {
    r.groups.add(
      const Group(
        id: 'g1',
        name: 'Cousins of Rajahmundry',
        code: 'FAM123',
        ownerUid: 'me',
        memberUids: ['me', 'v'],
        members: {
          'me': GroupMember(name: 'Chandrasekhar'),
          'v': GroupMember(name: 'Vasavi'),
        },
      ),
    );
    r.seasons['g1/${Season.idFor(DateTime.now())}'] = const Season(
      id: '',
      points: {'me': 123456, 'v': 2500},
      games: {'me': 22, 'v': 2},
      kings: {'me': 11},
    );
    return const GroupScreen(groupId: 'g1');
  },
  'history': (_) => const HistoryScreen(),
  'how to play (movie)': (_) => const OnboardingScreen(),
  'how to play (King & Queen)': (_) =>
      const OnboardingScreen(mode: GameMode.kingQueen),
  'lobby (host)': (r) {
    r.emitRoom(makeRoom(ready: {'v': true}));
    return const RoomScreen(roomId: 'room1');
  },
  'quick match lobby': (r) {
    r.me = 'v';
    r.emitRoom(makeRoom(isPublic: true, createdAt: DateTime.now()));
    return const RoomScreen(roomId: 'room1');
  },
  'lobby (King & Queen guest)': (r) {
    r.emitRoom(makeRoom(mode: GameMode.kingQueen));
    return const RoomScreen(roomId: 'room1');
  },
  'picking slips': (r) {
    r.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    r.emitRound(
      makeRound(
        status: RoundStatus.picking,
        chits: List.generate(16, (i) => 'p$i'),
        pickOpensAt: ago(1),
        pickDeadline: later(20),
      ),
    );
    return const RoomScreen(roomId: 'room1');
  },
  'round intro': (r) {
    r.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    r.emitRound(makeRound(introEndsAt: later(4)));
    r.emitHand(hand);
    return const RoomScreen(roomId: 'room1');
  },
  'passing (my turn)': (r) {
    r.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    r.emitRound(makeRound());
    r.emitHand(hand);
    return const RoomScreen(roomId: 'room1');
  },
  'passing (someone is late)': (r) {
    r.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    r.emitRound(makeRound(current: 'v', next: 's', deadline: ago(60)));
    r.emitHand(hand);
    return const RoomScreen(roomId: 'room1');
  },
  'character chits': (r) {
    r.emitRoom(
      makeRoom(status: RoomStatus.playing, currentRound: 1, roundKey: 'g1r01'),
    );
    r.emitRound(
      makeRound(
        status: RoundStatus.characters,
        winner: const RoundWinner('v', 'RRR', 1000),
        charChits: const ['ca', 'cb', 'cc'],
        charPickOpensAt: ago(1),
        charPickDeadline: later(19),
      ),
    );
    r.emitHand(hand);
    return const RoomScreen(roomId: 'room1');
  },
  'round results': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        totals: const {'me': 800, 'v': 1000, 's': 100, 'k': 500},
      ),
    );
    r.emitRound(
      makeRound(
        status: RoundStatus.revealed,
        winner: const RoundWinner('v', 'RRR', 1000),
        revealed: {'me': myCards, 'v': myCards, 's': myCards, 'k': myCards},
        characters: const {
          'me': CharacterDef('Queen', 800),
          's': CharacterDef('Thief', 100),
          'k': CharacterDef('Police', 500),
        },
        scores: const {'me': 800, 'v': 1000, 's': 100, 'k': 500},
      ),
    );
    r.emitHand(hand);
    return const RoomScreen(roomId: 'room1');
  },
  'tie-breaker vote': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.tiebreakVote,
        currentRound: 7,
        tiebreak: TiebreakInfo(
          title: 'King',
          uids: const ['me', 'v'],
          votes: const {},
          deadline: later(30),
          stage: 'vote',
        ),
      ),
    );
    return const RoomScreen(roomId: 'room1');
  },
  'final ceremony': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.finished,
        currentRound: 7,
        standings: standings,
      ),
    );
    return const RoomScreen(roomId: 'room1');
  },
  'King & Queen guessing': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        mode: GameMode.kingQueen,
      ),
    );
    r.emitKqRound(makeKqRound());
    r.emitKqRole(
      const KqMyRole(roundKey: 'g1r01', index: 0, name: 'King', points: 1000),
    );
    return const RoomScreen(roomId: 'room1');
  },
  'King & Queen results': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        mode: GameMode.kingQueen,
      ),
    );
    r.emitKqRound(
      makeKqRound(
        status: KqStatus.revealed,
        guesser: null,
        revealedRoles: const {'me': 0, 'v': 1, 's': 2, 'k': 3},
        scores: const {'me': 1000, 'v': 800, 's': 500, 'k': 0},
      ),
    );
    return const RoomScreen(roomId: 'room1');
  },
  'watching a game': (r) {
    r.me = 'newphone';
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        spectators: const {
          'newphone': Spectator(uid: 'newphone', name: 'Sai', claims: 'k'),
        },
      ),
    );
    r.emitRound(makeRound(current: 'v', next: 's'));
    return const RoomScreen(roomId: 'room1');
  },
  'host asked for a seat': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        spectators: const {
          'newphone': Spectator(
            uid: 'newphone',
            name: 'Lakshmi Prasanna',
            claims: 'k',
          ),
        },
      ),
    );
    r.emitRound(makeRound());
    r.emitHand(hand);
    return const RoomScreen(roomId: 'room1');
  },
  'charades (acting)': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        mode: GameMode.charades,
      ),
    );
    r.emitCharades(_charades(actor: 'me'));
    r.emitCard(const CharadesCard('g1r01', 'Sankranthiki Vasthunnam'));
    return const RoomScreen(roomId: 'room1');
  },
  'charades (guessing)': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        mode: GameMode.charades,
      ),
    );
    r.emitCharades(_charades(actor: 'v'));
    return const RoomScreen(roomId: 'room1');
  },
  'charades (result)': (r) {
    r.emitRoom(
      makeRoom(
        status: RoomStatus.playing,
        currentRound: 1,
        roundKey: 'g1r01',
        mode: GameMode.charades,
      ),
    );
    r.emitCharades(_charades(actor: 'v', revealed: true));
    return const RoomScreen(roomId: 'room1');
  },
  'update required': (r) {
    r.config = const AppConfig(minBuild: 99, message: 'Please update.');
    return const HomeScreen();
  },
  'update available': (r) {
    r.config = const AppConfig(latestBuild: 99, message: 'New: sounds!');
    return const HomeScreen();
  },
};

CharadesRound _charades({required String actor, bool revealed = false}) =>
    CharadesRound(
      key: 'g1r01',
      gameNo: 1,
      roundNo: 1,
      revealed: revealed,
      actor: actor,
      options: const [
        'Sankranthiki Vasthunnam',
        'Seethamma Vakitlo Sirimalle Chettu',
        'Ala Vaikunthapurramuloo',
        'Pushpa 2',
        'RRR',
        'Jersey',
      ],
      startsAt: DateTime.now().subtract(const Duration(seconds: 3)),
      deadline: DateTime.now().add(const Duration(seconds: 60)),
      guesses: const {},
      solvedBy: revealed ? 's' : null,
      answer: revealed ? 1 : null,
      scores: revealed ? const {'s': 230, 'v': 75} : null,
    );

void main() {
  setUp(() {
    AppUpdater.currentBuild = () async => 6;
  });

  for (final d in devices.entries) {
    for (final s in scenes.entries) {
      testWidgets('${s.key} fits on a ${d.key}', (tester) async {
        SharedPreferences.setMockInitialValues({
          'onboarded': true,
          'sound': false,
          'music': false,
          'playerName': 'Chandrasekhar',
        });
        final prefs = await Preferences.load();
        final repo = FakeGameRepository();
        final (size, dpr, text) = d.value;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = dpr;
        tester.platformDispatcher.textScaleFactorTestValue = text;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        // Name the overflowing widget while it still exists (the default
        // report runs after the tree is gone).
        final report = FlutterError.onError;
        FlutterError.onError = (e) {
          final text = e.toString();
          final at = text.indexOf('The relevant error-causing widget was');
          if (at >= 0) {
            debugPrint(
              'LAYOUT ${e.exceptionAsString().split('\n').first} '
              '${text.substring(at, (at + 260).clamp(0, text.length)).replaceAll('\n', ' ')}',
            );
          }
          report?.call(e);
        };

        final home = s.value(repo);
        await tester.pumpWidget(
          ChittilataApp(
            services: AppServices(
              repo: repo,
              prefs: prefs,
              feedback: GameFeedback(prefs),
            ),
            home: home,
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
