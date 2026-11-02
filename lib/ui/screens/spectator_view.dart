import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';

/// For someone who joined after the game started: the live table, and a
/// way to take back their own seat if this is a new phone.
class SpectatorView extends StatelessWidget {
  const SpectatorView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final me = ctrl.mySpectator;
    final turn = _whoseTurn();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Leave',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onLeave,
              ),
              Expanded(
                child: Text(
                  'Watching 👀',
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            children: [
              Panel(
                child: Column(
                  children: [
                    GoldText(
                      room.isKq ? '👑 King & Queen' : '🎬 Movie Chits',
                      textAlign: TextAlign.center,
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Round ${room.currentRound} of ${room.totalRounds} · '
                      '${_status()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      'This game started before you joined. Watch and cheer '
                      'with emojis — you get a seat when they play again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              Text('Players', style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  children: [
                    for (final p in room.activePlayers)
                      ListTile(
                        leading: PlayerAvatar(
                          name: p.name,
                          online: p.bot || ctrl.isOnline(p.uid),
                          ring: p.uid == turn ? c.marigold : null,
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          p.uid == turn
                              ? (room.isKq ? 'Guessing now' : 'Passing now')
                              : p.bot
                              ? 'Bot'
                              : ctrl.isOffline(p.uid)
                              ? 'Offline'
                              : 'Playing',
                          style: TextStyle(
                            color: p.uid == turn ? c.marigold : c.muted,
                          ),
                        ),
                        trailing: Text(
                          '${room.totals[p.uid] ?? 0}',
                          style: context.text.titleMedium?.copyWith(
                            color: c.leaf,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              _SeatBack(ctrl: ctrl, me: me),
            ],
          ),
        ),
      ],
    );
  }

  String? _whoseTurn() {
    final rd = ctrl.round;
    final kr = ctrl.kqRound;
    if (ctrl.room!.isKq) {
      return kr?.status == KqStatus.guessing ? kr?.guesser : null;
    }
    return rd?.status == RoundStatus.exchange ? rd?.currentUid : null;
  }

  String _status() {
    final room = ctrl.room!;
    if (room.status == RoomStatus.tiebreakVote) return 'tie-breaker vote';
    if (room.status == RoomStatus.finished) return 'game over';
    if (room.isKq) {
      return switch (ctrl.kqRound?.status) {
        KqStatus.picking => 'picking roles',
        KqStatus.guessing => 'guessing',
        KqStatus.revealed => 'round over',
        _ => 'starting',
      };
    }
    return switch (ctrl.round?.status) {
      RoundStatus.picking => 'picking chits',
      RoundStatus.exchange => 'passing chits',
      RoundStatus.characters => 'picking characters',
      RoundStatus.revealed => 'round over',
      _ => 'starting',
    };
  }
}

class _SeatBack extends StatelessWidget {
  const _SeatBack({required this.ctrl, required this.me});
  final RoomController ctrl;
  final Spectator? me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final approved = me?.approved;
    final claim = me?.claims;
    if (approved != null) {
      return Panel(
        color: c.leaf.withValues(alpha: 0.15),
        child: Text(
          '✅ The host gave you ${room.nameOf(approved)}\'s seat. You play '
          'from the next round, with its score.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35),
        ),
      );
    }
    if (claim != null) {
      return Panel(
        child: Column(
          children: [
            Text(
              'Asked the host for ${room.nameOf(claim)}\'s seat. Waiting for '
              'them to say yes…',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: ctrl.busy ? null : () => ctrl.claimSeat(null),
              child: const Text('Cancel request'),
            ),
          ],
        ),
      );
    }
    final seats = room.activePlayers
        .where((p) => !p.bot && ctrl.isOffline(p.uid))
        .toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reinstalled the app or changed phones?',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: Space.xs),
          Text(
            seats.isEmpty
                ? 'If one of these players is you, wait until that seat shows '
                      'as offline, then ask the host for it here.'
                : 'Tap your old seat. The host approves, and you continue '
                      'from the next round with your score.',
            style: TextStyle(color: c.muted, height: 1.35),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final p in seats)
                OutlinedButton.icon(
                  onPressed: ctrl.busy
                      ? null
                      : withClick(context, () => ctrl.claimSeat(p.uid)),
                  icon: const Icon(Icons.event_seat_rounded, size: 18),
                  label: Text('I am ${p.name}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Host only: a watcher asks for an offline player's seat.
class SeatClaimBanner extends StatelessWidget {
  const SeatClaimBanner({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final claims = ctrl.seatClaims;
    if (claims.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final s = claims.first;
    final seat = ctrl.room!.nameOf(s.claims!);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, 0),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.teal.withValues(alpha: 0.7)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${s.name} says they are $seat on a new phone.',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            'Give them $seat\'s seat and score from the next round?',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.sm,
            children: [
              TextButton(
                onPressed: ctrl.busy
                    ? null
                    : () => ctrl.answerSeatClaim(s.uid, false),
                child: const Text('No'),
              ),
              FilledButton(
                onPressed: ctrl.busy
                    ? null
                    : () => ctrl.answerSeatClaim(s.uid, true),
                child: const Text('Give seat'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
