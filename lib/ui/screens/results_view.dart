import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';
import '../widgets/paper_card.dart';
import 'game_view.dart';

/// Completed-round reveal: every hand, characters, round points, leaderboard.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final round = ctrl.round!;
    final aborted = round.status == RoundStatus.aborted;
    final players = [...round.order]
      ..sort((a, b) => (room.totals[b] ?? 0).compareTo(room.totals[a] ?? 0));
    final moreRounds = room.currentRound < room.settings.rounds;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Row(
            children: [
              IconButton(
                  tooltip: 'Leave game',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onLeave),
              Expanded(
                child: Text('ROUND ${round.roundNo} OF ${room.settings.rounds}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: c.muted, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              if (aborted)
                Panel(
                  child: Column(
                    children: [
                      Icon(Icons.block_rounded, color: c.kumkum, size: 48),
                      const SizedBox(height: Space.sm),
                      Text('Round cancelled', style: context.text.titleLarge),
                      const SizedBox(height: Space.xs),
                      Text('${round.abortedReason ?? 'A player left.'} No points this round.',
                          textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
                    ],
                  ),
                )
              else ...[
                Text('Round results',
                    textAlign: TextAlign.center, style: context.text.headlineSmall),
                const SizedBox(height: Space.xs),
                Text(
                  '${room.nameOf(round.winner!.uid)} collected four × ${round.winner!.movie}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.marigold, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: Space.lg),
                for (final uid in round.order)
                  _RevealRow(ctrl: ctrl, round: round, uid: uid),
              ],
              const SizedBox(height: Space.lg),
              Text('Leaderboard', style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Column(
                  children: [
                    for (var i = 0; i < players.length; i++)
                      _LeaderRow(
                        rank: i + 1,
                        name: room.nameOf(players[i]),
                        isMe: players[i] == ctrl.uid,
                        total: room.totals[players[i]] ?? 0,
                        gained: round.scores?[players[i]],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: SizedBox(
            width: double.infinity,
            child: ctrl.isHost
                ? BigButton(
                    label: moreRounds ? 'Start round ${room.currentRound + 1}' : 'See final results',
                    icon: Icons.arrow_forward_rounded,
                    busy: ctrl.busy,
                    onPressed: moreRounds ? ctrl.nextRound : null,
                  )
                : BigButton(
                    label: 'Waiting for ${room.nameOf(room.hostUid)} to start round ${room.currentRound + 1}',
                    secondary: true,
                    onPressed: null,
                  ),
          ),
        ),
      ],
    );
  }
}

class _RevealRow extends StatelessWidget {
  const _RevealRow({required this.ctrl, required this.round, required this.uid});
  final RoomController ctrl;
  final Round round;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final isWinner = round.winner?.uid == uid;
    final char = round.characters?[uid];
    final cards = round.revealedHands?[uid] ?? const <GameCard>[];
    final pts = round.scores?[uid] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Panel(
        color: isWinner ? c.marigold.withValues(alpha: 0.14) : null,
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PlayerAvatar(name: room.nameOf(uid), size: 36),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(uid == ctrl.uid ? '${room.nameOf(uid)} (you)' : room.nameOf(uid),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Row(
                        children: [
                          Icon(
                              isWinner
                                  ? Icons.emoji_events_rounded
                                  : characterIcon(char?.name ?? ''),
                              size: 16,
                              color: isWinner ? c.marigold : c.teal),
                          const SizedBox(width: 4),
                          Text(isWinner ? 'Movie winner' : (char?.name ?? '—'),
                              style: TextStyle(
                                  color: isWinner ? c.marigold : c.teal,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                ),
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: pts),
                  duration: Motion.of(context, const Duration(milliseconds: 900)),
                  builder: (_, v, _) => Text('+$v',
                      style: context.text.titleLarge?.copyWith(color: c.leaf)),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final card in cards)
                  PaperSlip(
                    label: card.name,
                    width: 56,
                    state: isWinner && card.name == round.winner!.movie
                        ? SlipState.winning
                        : SlipState.normal,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.rank,
    required this.name,
    required this.isMe,
    required this.total,
    this.gained,
  });
  final int rank;
  final String name;
  final bool isMe;
  final int total;
  final int? gained;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: Text('#$rank',
            style: TextStyle(
                fontWeight: FontWeight.w900, color: rank == 1 ? c.marigold : c.muted)),
      ),
      title: Text(isMe ? '$name (you)' : name,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (gained != null)
            Text('+$gained  ', style: TextStyle(color: c.leaf, fontWeight: FontWeight.w700)),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: total - (gained ?? 0), end: total),
            duration: Motion.of(context, const Duration(milliseconds: 900)),
            builder: (_, v, _) =>
                Text('$v', style: context.text.titleMedium),
          ),
        ],
      ),
    );
  }
}
