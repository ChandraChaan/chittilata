import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app.dart';
import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';
import 'final_view.dart';
import 'game_view.dart';
import 'lobby_view.dart';
import 'results_view.dart';

/// Hosts one room for its whole life: lobby → rounds → final ceremony.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId, this.controller});
  final String roomId;

  /// Injected in tests.
  final RoomController? controller;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  RoomController? _ctrl;
  StreamSubscription<String>? _msgs;
  GameFeedback? _feedback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrl != null) return;
    final s = Services.of(context);
    _ctrl =
        widget.controller ??
        RoomController(
          repo: s.repo,
          roomId: widget.roomId,
          prefs: s.prefs,
          feedback: s.feedback,
        );
    _msgs = _ctrl!.messages.listen((m) {
      if (mounted) showGameSnack(context, m);
    });
    _feedback = s.feedback..setMusicWanted(true);
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _msgs?.cancel();
    _ctrl?.dispose();
    _feedback?.setMusicWanted(false);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final ctrl = _ctrl!;
    final p = ctrl.phase;
    final midGame =
        p != Phase.lobby &&
        p != Phase.finished &&
        p != Phase.closed &&
        p != Phase.removed;
    final ok = p == Phase.closed || p == Phase.removed
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Leave the room?'),
              content: Text(
                midGame
                    ? 'The game is in progress. If you leave during passing, the '
                          'round is cancelled for everyone, and you cannot rejoin '
                          'this game.'
                    : 'You can join again later with the room code.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Stay'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Leave'),
                ),
              ],
            ),
          );
    if (ok != true || !mounted) return;
    if (p != Phase.closed && p != Phase.removed) await ctrl.leave();
    if (mounted) Navigator.of(context).pop();
  }

  void _home() {
    _ctrl?.prefs.activeRoomId = null;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: GameBackground(
          child: ListenableBuilder(
            listenable: ctrl,
            builder: (context, _) {
              final phase = ctrl.phase;
              final Widget body = switch (phase) {
                Phase.loading => const _Centered(
                  icon: null,
                  title: 'Loading room…',
                  body: null,
                ),
                Phase.closed => _Centered(
                  icon: Icons.door_back_door_rounded,
                  title: 'This room has closed',
                  body:
                      'Rooms close when everyone leaves or after 24 hours '
                      'without play.',
                  action: BigButton(label: 'Back to home', onPressed: _home),
                ),
                Phase.removed => _Centered(
                  icon: Icons.person_off_rounded,
                  title: "You're no longer in this room",
                  body: 'You left, or the host removed you.',
                  action: BigButton(label: 'Back to home', onPressed: _home),
                ),
                Phase.lobby => LobbyView(ctrl: ctrl, onLeave: _confirmLeave),
                Phase.intro || Phase.exchange || Phase.characters => GameView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.results || Phase.aborted => ResultsView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.finished => FinalView(
                  ctrl: ctrl,
                  onHome: () async {
                    await ctrl.leave();
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              };
              return SafeArea(
                child: Column(
                  children: [
                    ConnectionBanner(connected: ctrl.connected),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, Motion.medium),
                        child: KeyedSubtree(
                          key: ValueKey(_viewKey(phase, ctrl)),
                          child: body,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _viewKey(Phase p, RoomController c) => switch (p) {
    Phase.intro || Phase.exchange || Phase.characters => 'game-${c.round?.key}',
    Phase.results || Phase.aborted => 'results-${c.round?.key}',
    _ => p.name,
  };
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });
  final IconData? icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon == null)
              CircularProgressIndicator(color: c.marigold)
            else
              Icon(icon, size: 64, color: c.muted),
            const SizedBox(height: Space.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleLarge,
            ),
            if (body != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Space.xl), action!],
          ],
        ),
      ),
    );
  }
}
