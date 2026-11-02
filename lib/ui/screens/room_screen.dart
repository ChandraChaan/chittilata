import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app.dart';
import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';
import '../widgets/quick_chat.dart';
import 'charades_views.dart';
import 'final_view.dart';
import 'game_view.dart';
import 'lobby_view.dart';
import 'kq_views.dart';
import 'picking_view.dart';
import 'results_view.dart';
import 'spectator_view.dart';
import 'tiebreak_view.dart';

/// Hosts one room for its whole life: lobby → rounds → final ceremony.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId, this.controller});
  final String roomId;

  static const routeName = 'room';

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
    _feedback = s.feedback..setMusic(Music.game);
    s.push?.enable();
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _msgs?.cancel();
    _ctrl?.dispose();
    _feedback?.setMusic(Music.menu);
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
        p != Phase.removed &&
        p != Phase.spectating;
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
                Phase.spectating => SpectatorView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.lobby => LobbyView(ctrl: ctrl, onLeave: _confirmLeave),
                Phase.picking => PickingView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.characters => CharacterPickView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                  winnerBanner: WinnerBanner(ctrl: ctrl),
                  characterIcon: characterIcon,
                ),
                Phase.intro ||
                Phase.exchange => GameView(ctrl: ctrl, onLeave: _confirmLeave),
                Phase.kqPicking => KqPickingView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.kqGuessing => KqGuessView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.charades => CharadesView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.results || Phase.aborted when ctrl.room!.isCharades =>
                  CharadesResultsView(ctrl: ctrl, onLeave: _confirmLeave),
                Phase.results || Phase.aborted when ctrl.room!.isKq =>
                  KqResultsView(ctrl: ctrl, onLeave: _confirmLeave),
                Phase.results || Phase.aborted => ResultsView(
                  ctrl: ctrl,
                  onLeave: _confirmLeave,
                ),
                Phase.tiebreakVote => TiebreakView(
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
              final inRoom =
                  ctrl.room != null &&
                  phase != Phase.loading &&
                  phase != Phase.closed &&
                  phase != Phase.removed;
              return AvatarScope(
                avatars: {
                  for (final p in ctrl.room?.players.values ?? <PlayerInfo>[])
                    if (p.avatar != null) p.name: p.avatar!,
                },
                child: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedSwitcher(
                                duration: Motion.of(context, Motion.medium),
                                child: KeyedSubtree(
                                  key: ValueKey(_viewKey(phase, ctrl)),
                                  child: body,
                                ),
                              ),
                            ),
                            if (inRoom)
                              Positioned.fill(child: ChatLayer(ctrl: ctrl)),
                            // Banners float over the top of the game instead of
                            // taking space from it: resizing the screen when
                            // time ran out moved every chit away from the
                            // finger reaching for it.
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConnectionBanner(connected: ctrl.connected),
                                  if (inRoom && phase != Phase.spectating)
                                    LateBanner(ctrl: ctrl),
                                  if (inRoom) SeatClaimBanner(ctrl: ctrl),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (inRoom) QuickChatBar(ctrl: ctrl),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _viewKey(Phase p, RoomController c) => switch (p) {
    Phase.picking => 'picking-${c.round?.key}',
    Phase.kqPicking => 'kqpicking-${c.kqRound?.key}',
    Phase.kqGuessing => 'kqguess-${c.kqRound?.key}',
    Phase.characters => 'characters-${c.round?.key}',
    Phase.intro || Phase.exchange => 'game-${c.round?.key}',
    Phase.charades => 'charades-${c.charades?.key}',
    Phase.results || Phase.aborted =>
      'results-${c.room?.isCharades == true
          ? c.charades?.key
          : c.room?.isKq == true
          ? c.kqRound?.key
          : c.round?.key}',
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
