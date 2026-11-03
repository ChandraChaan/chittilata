import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../screens/onboarding_screen.dart';
import 'common.dart';

/// The room menu (⋮): who is here, host controls to warn, remove or end the
/// game for everyone, and a way out for anyone, at any time.
Future<void> showRoomMenu(
  BuildContext context,
  RoomController ctrl, {
  required VoidCallback onLeave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: ctrl,
      builder: (ctx, _) => RoomMenu(
        ctrl: ctrl,
        onLeave: () {
          Navigator.pop(ctx);
          onLeave();
        },
      ),
    ),
  );
}

class RoomMenu extends StatelessWidget {
  const RoomMenu({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room;
    if (room == null) return const SizedBox.shrink();
    final lobby = room.status == RoomStatus.lobby;
    final finished = room.status == RoomStatus.finished;
    final players = room.activePlayers;
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    switch (room.mode) {
                      GameMode.kingQueen => '👑 King & Queen',
                      GameMode.charades => '🎭 Dumb Charades',
                      GameMode.movie => '🎬 Movie Chits',
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  'Room ${room.code}',
                  style: TextStyle(
                    color: c.marigold,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Text(
              'Players · ${players.length}/10',
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Space.xs),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(
                children: [
                  for (final p in players) _PlayerRow(ctrl: ctrl, p: p),
                ],
              ),
            ),
            if (ctrl.isHost && !lobby && !finished)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Warn a quiet player (they get a minute to respond). '
                  'After $warningsBeforeKick warnings you can remove them at once.',
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.35),
                ),
              ),
            const SizedBox(height: Space.lg),
            if (ctrl.canTakeSeat)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: BigButton(
                  label: 'Join the game (from next round)',
                  icon: Icons.event_seat_rounded,
                  busy: ctrl.busy,
                  onPressed: ctrl.takeSeat,
                ),
              ),
            if (ctrl.isHost && !finished)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: BigButton(
                  label: lobby
                      ? 'Close room for everyone'
                      : 'End game for everyone',
                  icon: lobby
                      ? Icons.door_front_door_rounded
                      : Icons.flag_rounded,
                  secondary: true,
                  busy: ctrl.busy,
                  onPressed: () => _confirmEnd(context, lobby),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      gameRoute(OnboardingScreen(mode: room.mode)),
                    ),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('How to play'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: c.kumkum),
                    onPressed: onLeave,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(
                      lobby || finished ? 'Leave room' : 'Leave game',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, bool lobby) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lobby ? 'Close the room?' : 'End the game for everyone?'),
        content: Text(
          lobby
              ? 'Everyone here goes back to the home screen and the code '
                    'stops working.'
              : 'The current round is cancelled and the game finishes with '
                    'the points so far. Everyone sees the final standings '
                    'and you can play again from there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(lobby ? 'Close room' : 'End game'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final done = await ctrl.endGame();
      if (done && context.mounted) Navigator.pop(context);
    }
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.ctrl, required this.p});
  final RoomController ctrl;
  final PlayerInfo p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final me = p.uid == ctrl.uid;
    final w = ctrl.warningOf(p.uid);
    final open = ctrl.warningOpen(p.uid);
    final status = p.uid == room.hostUid
        ? 'Host'
        : p.bot
        ? 'Bot'
        : open
        ? '⚠️ ${ctrl.warningSecondsLeft(p.uid)}s to respond'
        : ctrl.isOffline(p.uid)
        ? 'Offline'
        : ctrl.isAway(p.uid)
        ? 'App in background'
        : 'Online';
    final warned = (w?.count ?? 0) > 0 && !open ? ' · warned ${w!.count}×' : '';
    return ListTile(
      dense: true,
      leading: PlayerAvatar(
        name: p.name,
        size: 36,
        online: p.bot || ctrl.isOnline(p.uid),
      ),
      title: Text(
        me ? '${p.name} (you)' : p.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '$status$warned · ${room.totals[p.uid] ?? 0} pts',
        style: TextStyle(color: open ? c.kumkum : c.muted, fontSize: 12),
      ),
      trailing: !ctrl.isHost || me
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ctrl.canWarn(p.uid))
                  IconButton(
                    tooltip: 'Warn ${p.name}',
                    icon: Icon(
                      Icons.notifications_active_rounded,
                      color: c.marigold,
                    ),
                    onPressed: ctrl.busy ? null : () => ctrl.warn(p.uid),
                  ),
                if (ctrl.canRemoveNow(p.uid))
                  IconButton(
                    tooltip: 'Remove ${p.name}',
                    icon: Icon(Icons.person_remove_rounded, color: c.kumkum),
                    onPressed: ctrl.busy
                        ? null
                        : () => _confirmRemove(context, p),
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, PlayerInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: Text(
          p.bot
              ? 'The bot leaves the table.'
              : ctrl.room!.status == RoomStatus.lobby
              ? 'They will not be able to rejoin this room.'
              : 'The current round is cancelled and they cannot rejoin '
                    'this room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) ctrl.removePlayer(p.uid);
  }
}
