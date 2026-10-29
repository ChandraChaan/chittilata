import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';

/// After the last round, players tied for King or Queen choose between a
/// tie-breaker round and sharing the title. Everyone else waits.
class TiebreakView extends StatelessWidget {
  const TiebreakView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final tb = room.tiebreak!;
    final names = tb.uids
        .map((u) => u == ctrl.uid ? 'You' : room.nameOf(u))
        .join(' & ');
    final standings = room.finalStandings ?? const [];
    final myVote = tb.votes[ctrl.uid];
    final isKing = tb.title == 'King';
    final accent = isKing ? c.marigold : c.kumkum;
    final seconds = ctrl.tiebreakVoteRemainingSeconds;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Leave room',
                icon: const Icon(Icons.close_rounded),
                onPressed: onLeave,
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              Icon(
                isKing
                    ? Icons.workspace_premium_rounded
                    : Icons.diamond_rounded,
                size: 72,
                color: accent,
              ),
              const SizedBox(height: Space.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  "It's a tie for ${tb.title}!",
                  textAlign: TextAlign.center,
                  style: context.text.headlineMedium?.copyWith(color: accent),
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                '$names have the same points and movie wins.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: Space.lg),
              Panel(
                child: Column(
                  children: [
                    Text(
                      ctrl.isTiedPlayer
                          ? 'Play one extra round between the tied players to '
                                'decide the ${tb.title}? Its points only break '
                                'the tie; totals stay the same.'
                          : 'The tied players are deciding whether to play a '
                                'tie-breaker round. You can watch it if they do.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: Space.md),
                    for (final u in tb.uids)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            PlayerAvatar(name: room.nameOf(u), size: 32),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                u == ctrl.uid ? 'You' : room.nameOf(u),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              tb.votes[u] == true
                                  ? 'Wants a tie-breaker'
                                  : 'Deciding…',
                              style: TextStyle(
                                color: tb.votes[u] == true ? c.leaf : c.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.md),
                    Text(
                      'Decide within ${seconds}s. No answer keeps the shared title.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              Text('Standings so far', style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Column(
                  children: [
                    for (final s in standings)
                      ListTile(
                        dense: true,
                        leading: PlayerAvatar(name: s.name, size: 32),
                        title: Text(
                          '#${s.rank}  ${s.name}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          s.title == null
                              ? ' '
                              : standings
                                        .where((o) => o.title == s.title)
                                        .length >
                                    1
                              ? 'Joint ${s.title}'
                              : s.title!,
                          style: TextStyle(color: c.muted),
                        ),
                        trailing: Text(
                          '${s.total}',
                          style: context.text.titleMedium,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (ctrl.isTiedPlayer)
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: myVote == true
                ? Text(
                    'Waiting for the others to decide…',
                    style: TextStyle(color: c.muted),
                  )
                : Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: BigButton(
                          label: 'Play tie-breaker',
                          icon: Icons.sports_score_rounded,
                          busy: ctrl.busy,
                          onPressed: () => ctrl.voteTiebreak(true),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        width: double.infinity,
                        child: BigButton(
                          label: 'Share the title',
                          icon: Icons.handshake_rounded,
                          secondary: true,
                          onPressed: ctrl.busy
                              ? null
                              : () => ctrl.voteTiebreak(false),
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
