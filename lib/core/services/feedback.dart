import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'preferences.dart';

enum Sfx { tap, select, receive, pass, tick, timeout, win, reveal, roundEnd, fanfare }

/// Sound effects, background music and haptics, each gated by the player's
/// preferences. Audio is never required to follow the game.
class GameFeedback {
  GameFeedback(this._prefs) {
    _prefs.addListener(_syncMusic);
  }

  final Preferences _prefs;
  final _pool = <Sfx, AudioPlayer>{};
  AudioPlayer? _music;
  bool _musicWanted = false;

  static const _files = {
    Sfx.tap: 'tap.wav',
    Sfx.select: 'select.wav',
    Sfx.receive: 'receive.wav',
    Sfx.pass: 'pass.wav',
    Sfx.tick: 'tick.wav',
    Sfx.timeout: 'timeout.wav',
    Sfx.win: 'win.wav',
    Sfx.reveal: 'reveal.wav',
    Sfx.roundEnd: 'round_end.wav',
    Sfx.fanfare: 'fanfare.wav',
  };

  Future<void> play(Sfx s) async {
    if (!_prefs.sound) return;
    try {
      final p = _pool.putIfAbsent(s, () {
        final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        player.audioCache.prefix = 'assets/sounds/';
        return player;
      });
      await p.stop();
      await p.play(AssetSource(_files[s]!), volume: 0.7);
    } catch (e) {
      debugPrint('sfx $s failed: $e');
    }
  }

  void selection() => _haptic(HapticFeedback.selectionClick);
  void light() => _haptic(HapticFeedback.lightImpact);
  void medium() => _haptic(HapticFeedback.mediumImpact);
  void heavy() => _haptic(HapticFeedback.heavyImpact);
  void warning() => _haptic(HapticFeedback.vibrate);

  void _haptic(Future<void> Function() f) {
    if (_prefs.haptics) f();
  }

  /// Music plays only on game screens and only if enabled.
  void setMusicWanted(bool wanted) {
    _musicWanted = wanted;
    _syncMusic();
  }

  Future<void> _syncMusic() async {
    final on = _musicWanted && _prefs.music;
    try {
      if (on) {
        _music ??= AudioPlayer()
          ..setReleaseMode(ReleaseMode.loop)
          ..audioCache.prefix = 'assets/sounds/';
        if (_music!.state != PlayerState.playing) {
          await _music!.play(AssetSource('music_loop.wav'), volume: 0.25);
        }
      } else {
        await _music?.pause();
      }
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }
}
