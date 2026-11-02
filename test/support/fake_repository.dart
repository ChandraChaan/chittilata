import 'dart:async';

import 'package:chittilata/data/app_config.dart';
import 'package:chittilata/data/chat.dart';
import 'package:chittilata/data/game_repository.dart';
import 'package:chittilata/data/groups.dart';
import 'package:chittilata/data/models.dart';

/// In-memory backend for widget tests. Tests push server state with the
/// `emit*` helpers and inspect `calls` to see what the UI asked for.
class FakeGameRepository implements GameRepository {
  FakeGameRepository({this.me = 'me'});

  String me;
  final calls = <String>[];
  final _room = StreamController<Room?>.broadcast();
  final _round = StreamController<Round?>.broadcast();
  final _hand = StreamController<Hand?>.broadcast();
  Room? room;
  Round? round;
  Hand? hand;
  GameException? failNext;

  void emitRoom(Room r) {
    room = r;
    _room.add(r);
  }

  void emitRound(Round r) {
    round = r;
    _round.add(r);
  }

  void emitHand(Hand h) {
    hand = h;
    _hand.add(h);
  }

  Future<void> _record(String call) async {
    calls.add(call);
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  @override
  String? get uid => me;
  @override
  Duration get clockOffset => Duration.zero;
  @override
  Future<String> signIn() async => me;

  Stream<T> _seeded<T>(Stream<T> s, T? current) async* {
    if (current != null) yield current;
    yield* s;
  }

  @override
  Stream<Room?> watchRoom(String roomId) => _seeded(_room.stream, room);
  @override
  Stream<Round?> watchRound(String roomId, String roundKey) =>
      _seeded(_round.stream, round);
  @override
  Stream<Hand?> watchHand(String roomId) => _seeded(_hand.stream, hand);

  /// Presence the UI sees; empty means nobody has a heartbeat (offline).
  Map<String, Presence> presence = {};
  @override
  Stream<Map<String, Presence>> watchPresence(String roomId) =>
      Stream.value(presence);

  final _chat = StreamController<List<ChatEvent>>.broadcast();
  final chat = <String, ChatEvent>{};

  /// Pushes a quick-chat message as if [ChatEvent.uid] had sent it.
  void emitChat(ChatEvent e) {
    chat[e.uid] = e;
    _chat.add(chat.values.toList());
  }

  @override
  Stream<List<ChatEvent>> watchChat(String roomId) =>
      _seeded(_chat.stream, chat.isEmpty ? null : chat.values.toList());

  @override
  Future<void> sendChat(
    String roomId, {
    required String id,
    required ChatKind kind,
    required String code,
    String? to,
  }) async {
    await _record('chat:${kind.name}:$code${to == null ? '' : ':$to'}');
    emitChat(
      ChatEvent(
        id: id,
        uid: me,
        kind: kind,
        code: code,
        to: to,
        at: DateTime.now(),
      ),
    );
  }

  final groups = <Group>[];
  final seasons = <String, Season>{};
  @override
  Stream<List<Group>> watchMyGroups() => Stream.value(groups);
  @override
  Stream<Group?> watchGroup(String groupId) =>
      Stream.value(groups.where((g) => g.id == groupId).firstOrNull);
  @override
  Stream<Season> watchSeason(String groupId, String season) =>
      Stream.value(seasons['$groupId/$season'] ?? Season(id: season));
  @override
  Future<String> createGroup(String name, String playerName, String? a) async {
    await _record('createGroup:$name');
    return 'g1';
  }

  @override
  Future<String> joinGroup(String code, String playerName, String? a) async {
    await _record('joinGroup:$code');
    return 'g1';
  }

  @override
  Future<void> leaveGroup(String groupId) => _record('leaveGroup:$groupId');

  String? pushToken;
  @override
  Future<void> savePushToken(String token) async => pushToken = token;
  @override
  Future<void> deletePushToken() async => pushToken = null;

  final appConfig = StreamController<AppConfig>.broadcast();
  AppConfig config = AppConfig.none;
  @override
  Stream<AppConfig> watchAppConfig() => _seeded(appConfig.stream, config);

  @override
  Stream<bool> watchConnected(String roomId) => Stream.value(true);
  @override
  Future<List<Round>> loadRounds(String roomId, int gameNo) async =>
      round == null ? [] : [round!];
  @override
  Future<void> heartbeat(String roomId, {required bool foreground}) async {}

  final _kqRound = StreamController<KqRound?>.broadcast();
  final _kqRole = StreamController<KqMyRole?>.broadcast();
  KqRound? kqRound;
  KqMyRole? kqRole;
  KqRoleDef nextKqRole = const KqRoleDef(
    key: '0',
    name: 'King',
    points: 1000,
    core: true,
  );

  void emitKqRound(KqRound r) {
    kqRound = r;
    _kqRound.add(r);
  }

  void emitKqRole(KqMyRole r) {
    kqRole = r;
    _kqRole.add(r);
  }

  @override
  Future<void> updateKqSettings(String roomId, Map<String, Object?> patch) =>
      _record('updateKqSettings');
  @override
  Stream<KqRound?> watchKqRound(String roomId, String roundKey) =>
      _seeded(_kqRound.stream, kqRound);
  @override
  Stream<KqMyRole?> watchMyKqRole(String roomId) =>
      _seeded(_kqRole.stream, kqRole);
  @override
  Future<List<KqRound>> loadKqRounds(String roomId, int gameNo) async =>
      kqRound == null ? [] : [kqRound!];
  @override
  Future<KqRoleDef> kqPickChit(
    String roomId,
    String roundKey,
    String chitId,
  ) async {
    await _record('kqPick:$chitId');
    return nextKqRole;
  }

  @override
  Future<void> kqAutoPick(String roomId, String roundKey) =>
      _record('kqAutoPick');
  @override
  Future<void> kqGuess(
    String roomId,
    String roundKey,
    int turnId,
    String targetUid,
    String requestId,
  ) => _record('kqGuess:$turnId:$targetUid');
  @override
  Future<void> kqClaimTimeout(String roomId, String roundKey, int turnId) =>
      _record('kqTimeout:$turnId');

  @override
  Future<({String roomId, String code})> createRoom(
    String name, {
    GameMode mode = GameMode.movie,
    String? avatar,
    String? groupId,
  }) async {
    await _record(
      mode == GameMode.movie
          ? 'createRoom:$name'
          : 'createRoom:$name:${mode.name}',
    );
    return (roomId: 'room1', code: 'ABC234');
  }

  @override
  Future<({String roomId, String code})> joinRoom(
    String code,
    String name, {
    String? avatar,
  }) async {
    await _record('joinRoom:$code:$name');
    return (roomId: 'room1', code: code);
  }

  @override
  Future<void> setReady(String roomId, bool ready) =>
      _record('setReady:$ready');
  @override
  Future<void> updateSettings(String roomId, Map<String, Object?> patch) =>
      _record('updateSettings');
  @override
  Future<void> kickPlayer(String roomId, String uid) => _record('kick:$uid');
  @override
  Future<void> addBot(String roomId) => _record('addBot');
  @override
  Future<void> claimSeat(String roomId, String? seat) =>
      _record('claimSeat:$seat');
  @override
  Future<void> answerSeatClaim(String roomId, String spectator, bool approve) =>
      _record('answerSeat:$spectator:$approve');
  @override
  Future<void> leaveRoom(String roomId) => _record('leave');
  @override
  Future<void> startGame(String roomId) => _record('startGame');
  @override
  Future<void> nextRound(String roomId) => _record('nextRound');
  @override
  Future<void> passCard(
    String roomId,
    String roundKey,
    int turnId,
    String cardId,
    String requestId,
  ) => _record('pass:$turnId:$cardId');
  @override
  Future<void> claimTimeout(String roomId, String roundKey, int turnId) =>
      _record('timeout:$turnId');

  /// What the next pickChit / pickCharacter returns.
  GameCard nextPickCard = const GameCard(id: 'p1', name: 'RRR');
  CharacterDef nextCharacter = const CharacterDef('Queen', 800);

  @override
  Future<GameCard> pickChit(
    String roomId,
    String roundKey,
    String chitId,
  ) async {
    await _record('pick:$chitId');
    return nextPickCard;
  }

  @override
  Future<void> autoPickChits(String roomId, String roundKey) =>
      _record('autoPick');

  @override
  Future<CharacterDef> pickCharacter(
    String roomId,
    String roundKey,
    String chitId,
  ) async {
    await _record('pickCharacter:$chitId');
    return nextCharacter;
  }

  @override
  Future<void> autoPickCharacters(String roomId, String roundKey) =>
      _record('autoPickCharacters');

  @override
  Future<void> revealRound(String roomId, String roundKey) => _record('reveal');
  @override
  Future<void> playAgain(String roomId) => _record('playAgain');
  @override
  Future<void> tiebreakVote(String roomId, bool accept) =>
      _record('tiebreakVote:$accept');
  @override
  Future<void> resolveTiebreakVote(String roomId) => _record('resolveTiebreak');
}

const defaultSettings = GameSettings(
  category: Category.telugu,
  customNames: [],
  rounds: 7,
  turnSeconds: 20,
  difficulty: Difficulty.normal,
  timeoutPolicy: TimeoutPolicy.passIncoming,
  winPoints: 1000,
  characters: [
    CharacterDef('Queen', 800),
    CharacterDef('Thief', 100),
    CharacterDef('Police', 500),
  ],
);

const names = {'me': 'Chandra', 'v': 'Vasavi', 's': 'Swetha', 'k': 'Sai'};

Room makeRoom({
  RoomStatus status = RoomStatus.lobby,
  String host = 'me',
  Map<String, bool> ready = const {},
  int currentRound = 0,
  String? roundKey,
  Map<String, int> totals = const {},
  List<Standing>? standings,
  TiebreakInfo? tiebreak,
  GameMode mode = GameMode.movie,
  Map<String, int> kingWins = const {},
  Map<String, String> members = names,
  Map<String, Spectator> spectators = const {},
}) => Room(
  id: 'room1',
  code: 'ABC234',
  hostUid: host,
  status: status,
  memberUids: members.keys.toList(),
  players: {
    for (final e in members.entries)
      e.key: PlayerInfo(
        uid: e.key,
        name: e.value,
        ready: ready[e.key] ?? false,
        left: false,
        joinedAt: 0,
      ),
  },
  settings: defaultSettings,
  gameNo: 1,
  currentRound: currentRound,
  currentRoundKey: roundKey,
  totals: totals,
  movieWins: const {},
  finalStandings: standings,
  tiebreak: tiebreak,
  mode: mode,
  kqSettings: kqDefaultSettings,
  kingWins: kingWins,
  spectators: spectators,
);

const kqDefaultSettings = KqSettings(
  rounds: 5,
  turnSeconds: 20,
  roles: [
    KqRoleDef(key: 'king', name: 'King', points: 1000, core: true),
    KqRoleDef(key: 'queen', name: 'Queen', points: 800, core: true),
    KqRoleDef(key: 'minister', name: 'Minister', points: 700, core: false),
    KqRoleDef(key: 'commander', name: 'Commander', points: 600, core: false),
    KqRoleDef(key: 'police', name: 'Police', points: 500, core: true),
    KqRoleDef(key: 'merchant', name: 'Merchant', points: 400, core: false),
    KqRoleDef(key: 'poet', name: 'Poet', points: 300, core: false),
    KqRoleDef(key: 'farmer', name: 'Farmer', points: 200, core: false),
    KqRoleDef(key: 'jester', name: 'Jester', points: 150, core: false),
    KqRoleDef(key: 'thief', name: 'Thief', points: 100, core: true),
  ],
);

KqRound makeKqRound({
  KqStatus status = KqStatus.guessing,
  int step = 0,
  String? guesser = 'me',
  Map<String, int> locked = const {},
  List<String> excluded = const [],
  int turnId = 0,
  List<String> chits = const [],
  Map<String, String> picks = const {},
  DateTime? pickOpensAt,
  DateTime? pickDeadline,
  DateTime? guessOpensAt,
  DateTime? turnDeadline,
  List<KqGuessRecord> history = const [],
  Map<String, int>? revealedRoles,
  Map<String, int>? scores,
}) => KqRound(
  key: 'g1r01',
  gameNo: 1,
  roundNo: 1,
  status: status,
  players: const ['me', 'v', 's', 'k'],
  chain: const ['King', 'Queen', 'Police', 'Thief'],
  chainPoints: const [1000, 800, 500, 100],
  chits: chits,
  picks: picks,
  pickOpensAt: pickOpensAt,
  pickDeadline: pickDeadline,
  step: step,
  guesser: guesser,
  locked: locked,
  excluded: excluded,
  turnId: turnId,
  timed: true,
  turnSeconds: 20,
  guessOpensAt:
      guessOpensAt ?? DateTime.now().subtract(const Duration(seconds: 1)),
  turnDeadline: turnDeadline ?? DateTime.now().add(const Duration(seconds: 20)),
  history: history,
  revealedRoles: revealedRoles,
  scores: scores,
  abortedReason: null,
);

Round makeRound({
  RoundStatus status = RoundStatus.exchange,
  List<String> chits = const [],
  Map<String, String> picks = const {},
  DateTime? pickOpensAt,
  DateTime? pickDeadline,
  List<String> charChits = const [],
  Map<String, String> charPicks = const {},
  DateTime? charPickOpensAt,
  DateTime? charPickDeadline,
  List<String> order = const ['me', 'v', 's', 'k'],
  bool tiebreak = false,
  String current = 'me',
  String next = 'v',
  int turnId = 0,
  DateTime? introEndsAt,
  DateTime? deadline,
  RoundWinner? winner,
  DateTime? revealAt,
  Map<String, List<GameCard>>? revealed,
  Map<String, CharacterDef>? characters,
  Map<String, int>? scores,
}) => Round(
  key: 'g1r01',
  gameNo: 1,
  roundNo: 1,
  tiebreak: tiebreak,
  status: status,
  order: order,
  chits: chits,
  picks: picks,
  pickOpensAt: pickOpensAt,
  pickDeadline: pickDeadline,
  charChits: charChits,
  charPicks: charPicks,
  charPickOpensAt: charPickOpensAt,
  charPickDeadline: charPickDeadline,
  turnId: turnId,
  currentUid: current,
  nextUid: next,
  timed: true,
  turnSeconds: 20,
  introEndsAt:
      introEndsAt ?? DateTime.now().subtract(const Duration(seconds: 1)),
  turnDeadline: deadline ?? DateTime.now().add(const Duration(seconds: 20)),
  movieNames: const ['RRR', 'Devara', 'Salaar', 'Pushpa 2'],
  handSizes: const {'me': 4, 'v': 4, 's': 4, 'k': 4},
  lastAction: null,
  winner: winner,
  revealAt: revealAt,
  revealedHands: revealed,
  characters: characters,
  scores: scores,
  abortedReason: null,
);

const myCards = [
  GameCard(id: 'c1', name: 'RRR'),
  GameCard(id: 'c2', name: 'Devara'),
  GameCard(id: 'c3', name: 'Salaar'),
  GameCard(id: 'c4', name: 'Pushpa 2'),
];
