import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'preferences.dart';

enum Sfx {
  // UI
  button,
  tap,
  back,
  toggle,
  open,
  close,
  pop,
  error,
  coin,
  join,
  leave,
  nudge,
  // Game
  select,
  receive,
  pass,
  tick,
  tickUrgent,
  timeout,
  start,
  win,
  reveal,
  roundEnd,
  fanfare,
  fold,
  shuffle,
  pick,
  unfold,
}

/// Which background music is playing.
enum Music { none, menu, game }

/// Sound effects, background music and haptics, each gated by the player's
/// preferences. Audio is never required to follow the game.
class GameFeedback with WidgetsBindingObserver {
  GameFeedback(this._prefs) {
    _prefs.addListener(_syncMusic);
    WidgetsBinding.instance.addObserver(this);
  }

  final Preferences _prefs;
  final _players = <Sfx, List<AudioPlayer>>{};
  final _next = <Sfx, int>{};
  AudioPlayer? _music;
  Music _scene = Music.none;
  Music _playing = Music.none;
  bool _foreground = true;
  bool _contextSet = false;
  Timer? _fade;

  static const _files = {
    Sfx.button: 'button.wav',
    Sfx.tap: 'tap.wav',
    Sfx.back: 'back.wav',
    Sfx.toggle: 'toggle.wav',
    Sfx.open: 'open.wav',
    Sfx.close: 'close.wav',
    Sfx.pop: 'pop.wav',
    Sfx.error: 'error.wav',
    Sfx.coin: 'coin.wav',
    Sfx.join: 'join.wav',
    Sfx.leave: 'leave.wav',
    Sfx.nudge: 'nudge.wav',
    Sfx.select: 'select.wav',
    Sfx.receive: 'receive.wav',
    Sfx.pass: 'pass.wav',
    Sfx.tick: 'tick.wav',
    Sfx.tickUrgent: 'tick_urgent.wav',
    Sfx.timeout: 'timeout.wav',
    Sfx.start: 'start.wav',
    Sfx.win: 'win.wav',
    Sfx.reveal: 'reveal.wav',
    Sfx.roundEnd: 'round_end.wav',
    Sfx.fanfare: 'fanfare.wav',
    Sfx.fold: 'fold.wav',
    Sfx.shuffle: 'shuffle.wav',
    Sfx.pick: 'pick.wav',
    Sfx.unfold: 'unfold.wav',
  };

  /// Clicks sit under the game sounds so rapid tapping never gets tiring.
  static const _volume = {
    Sfx.button: 0.65,
    Sfx.tap: 0.5,
    Sfx.back: 0.5,
    Sfx.toggle: 0.5,
    Sfx.open: 0.4,
    Sfx.close: 0.35,
    Sfx.tick: 0.55,
  };

  /// Sounds that can overlap themselves (fast taps, ticking clocks).
  static const _polyphonic = {Sfx.button, Sfx.tap, Sfx.pick, Sfx.pop};

  static const _musicFiles = {
    Music.menu: 'music_menu.wav',
    Music.game: 'music_game.wav',
  };
  static const _musicVolume = 0.3;

  DateTime _lastUi = DateTime(0);

  /// A UI click: skipped when another click played a moment ago, so a
  /// button that also opens a screen or a dialog sounds once, not twice.
  void ui(Sfx s, {bool haptic = true}) {
    final now = DateTime.now();
    if (now.difference(_lastUi) < const Duration(milliseconds: 220)) return;
    _lastUi = now;
    play(s);
    if (haptic) selection();
  }

  /// Plays clicks for screens, dialogs and sheets opening and closing.
  late final NavigatorObserver navigatorObserver = _RouteSounds(this);

  Future<void> play(Sfx s) async {
    if (!_prefs.sound) return;
    try {
      await _setContext();
      final pool = _players.putIfAbsent(s, () => []);
      final size = _polyphonic.contains(s) ? 3 : 1;
      final i = (_next[s] ?? 0) % size;
      _next[s] = i + 1;
      if (pool.length <= i) pool.add(await _load(s));
      final p = pool[i];
      await p.stop();
      await p.resume();
    } catch (e) {
      debugPrint('sfx $s failed: $e');
    }
  }

  /// Loads the most common UI sounds ahead of the first tap, so the very
  /// first press already clicks without delay.
  Future<void> warmUp() async {
    if (!_prefs.sound) return;
    for (final s in const [Sfx.button, Sfx.tap, Sfx.back, Sfx.open]) {
      try {
        await _setContext();
        final pool = _players.putIfAbsent(s, () => []);
        if (pool.isEmpty) pool.add(await _load(s));
      } catch (e) {
        debugPrint('warm-up $s failed: $e');
      }
    }
  }

  Future<AudioPlayer> _load(Sfx s) async {
    final p = AudioPlayer();
    p.audioCache.prefix = 'assets/sounds/';
    // SoundPool: plays short clips with almost no delay.
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(_volume[s] ?? 0.75);
    await p.setSource(AssetSource(_files[s]!));
    return p;
  }

  /// Game audio mixes with whatever else is playing (a podcast, a call's
  /// ringtone) instead of stopping it on every click.
  Future<void> _setContext() async {
    if (_contextSet) return;
    _contextSet = true;
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
  }

  // ------------------------------------------------------------------ haptics

  /// The lightest tick: scrolling choices, chips, toggles.
  void selection() => _haptic(HapticFeedback.selectionClick);
  void light() => _haptic(HapticFeedback.lightImpact);
  void medium() => _haptic(HapticFeedback.mediumImpact);
  void heavy() => _haptic(HapticFeedback.heavyImpact);
  void warning() => _haptic(HapticFeedback.vibrate);

  /// Something you tried isn't allowed.
  void error() => _pattern(const [
    (0, HapticFeedback.heavyImpact),
    (110, HapticFeedback.heavyImpact),
  ]);

  /// Game or round starting: a deep double thump.
  void start() => _pattern(const [
    (0, HapticFeedback.mediumImpact),
    (450, HapticFeedback.heavyImpact),
    (560, HapticFeedback.heavyImpact),
  ]);

  /// Winning: a rising, celebratory roll.
  void celebrate() => _pattern(const [
    (0, HapticFeedback.heavyImpact),
    (90, HapticFeedback.lightImpact),
    (180, HapticFeedback.mediumImpact),
    (270, HapticFeedback.heavyImpact),
    (420, HapticFeedback.heavyImpact),
  ]);

  /// It's your turn now.
  void yourTurn() => _pattern(const [
    (0, HapticFeedback.mediumImpact),
    (120, HapticFeedback.lightImpact),
  ]);

  /// A long, unmistakable buzz-buzz-buzz: your turn is over time, or
  /// someone nudged you.
  void buzz() =>
      _pattern([for (var i = 0; i < 4; i++) (i * 160, HapticFeedback.vibrate)]);

  void _haptic(Future<void> Function() f) {
    if (_prefs.haptics) f();
  }

  void _pattern(List<(int, Future<void> Function())> steps) {
    if (!_prefs.haptics) return;
    for (final (ms, f) in steps) {
      ms == 0 ? f() : Future<void>.delayed(Duration(milliseconds: ms), f);
    }
  }

  // -------------------------------------------------------------------- music

  /// Menus play the festive theme, rooms the lighter in-game groove.
  void setMusic(Music scene) {
    _scene = scene;
    _syncMusic();
  }

  Music get scene => _scene;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMusic();
  }

  Future<void> _syncMusic() async {
    final want = _prefs.music && _foreground ? _scene : Music.none;
    if (want == _playing) return;
    _playing = want;
    try {
      await _setContext();
      final m = _music ??= AudioPlayer()..audioCache.prefix = 'assets/sounds/';
      if (m.state == PlayerState.playing) await _fadeTo(m, 0, 350);
      if (_playing != want) return; // changed again during the fade
      if (want == Music.none) {
        await m.pause();
        return;
      }
      await m.setReleaseMode(ReleaseMode.loop);
      await m.setVolume(0);
      await m.play(AssetSource(_musicFiles[want]!), volume: 0);
      await _fadeTo(m, _musicVolume, 900);
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }

  Future<void> _fadeTo(AudioPlayer p, double target, int ms) {
    _fade?.cancel();
    final done = Completer<void>();
    final from = p.volume;
    const step = 50;
    final steps = (ms / step).ceil();
    var i = 0;
    _fade = Timer.periodic(const Duration(milliseconds: step), (t) {
      i++;
      final v = from + (target - from) * (i / steps);
      p.setVolume(v.clamp(0, 1)).catchError((_) {});
      if (i >= steps) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    // A cancelled fade (a newer one took over) must not leave callers waiting.
    Future<void>.delayed(Duration(milliseconds: ms + 100), () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }
}

class _RouteSounds extends NavigatorObserver {
  _RouteSounds(this.fx);
  final GameFeedback fx;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return; // the first screen
    fx.ui(route is PopupRoute ? Sfx.open : Sfx.tap, haptic: false);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    fx.ui(route is PopupRoute ? Sfx.close : Sfx.back, haptic: false);
  }
}
