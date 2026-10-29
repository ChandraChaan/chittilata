import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/chits.dart';
import '../widgets/circle_order.dart';
import '../widgets/paper_card.dart';

/// Plays the ceremony cue sounds/haptics shared by both picking screens.
void playCeremonyCue(RoomController ctrl, String cue) {
  switch (cue) {
    case 'fold':
      ctrl.feedback.play(Sfx.fold);
      ctrl.feedback.light();
    case 'shuffle':
      ctrl.feedback.play(Sfx.shuffle);
    case 'scatter':
      ctrl.feedback.medium();
  }
}

/// Everyone picks 4 folded movie chits from the shared table.
class PickingView extends StatelessWidget {
  const PickingView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final round = ctrl.round!;
    final playing = round.order.contains(ctrl.uid);
    final mine = ctrl.myChitCount;
    final counts = <String, int>{};
    for (final u in round.picks.values) {
      counts[u] = (counts[u] ?? 0) + 1;
    }
    final stillPicking = round.order.where((u) => (counts[u] ?? 0) < 4).length;
    final open = ctrl.chitsOpen;

    final String title;
    final String subtitle;
    if (!open) {
      title = 'Making the chits';
      subtitle = 'Writing names, folding and shuffling…';
    } else if (!playing) {
      title = 'The players are picking chits';
      subtitle = '$stillPicking still picking';
    } else if (mine < 4) {
      title = 'Pick ${4 - mine} more chit${4 - mine == 1 ? '' : 's'}';
      subtitle = 'Tap any folded chit on the mat';
    } else {
      title = 'Your 4 chits are ready';
      subtitle =
          'Waiting for $stillPicking more player'
          '${stillPicking == 1 ? '' : 's'}…';
    }

    final reveal = ctrl.revealQueue.isNotEmpty ? ctrl.revealQueue.first : null;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Leave game',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onLeave,
                  ),
                  Expanded(
                    child: Text(
                      round.tiebreak
                          ? 'TIE-BREAKER'
                          : 'ROUND ${room.currentRound} OF ${room.settings.rounds}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.muted,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: open
                        ? CountdownBadge(
                            seconds: ctrl.pickRemainingSeconds,
                            progress: (ctrl.pickRemainingSeconds / 25).clamp(
                              0.0,
                              1.0,
                            ),
                            size: 40,
                          )
                        : null,
                  ),
                  const SizedBox(width: Space.sm),
                ],
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  Text(title, style: context.text.titleLarge),
                  Text(subtitle, style: TextStyle(color: c.muted)),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                child: ChitTable(
                  key: ValueKey('movie-${round.key}'),
                  seed: round.key,
                  ids: round.chits,
                  picks: round.picks,
                  myUid: ctrl.uid,
                  players: {for (final u in round.order) u: room.nameOf(u)},
                  counts: counts,
                  pending: ctrl.pendingChits,
                  canPick: ctrl.canPickChit && reveal == null,
                  onPick: ctrl.pickChit,
                  ceremonyLabels: round.movieNames,
                  opensAt: round.pickOpensAt,
                  now: () => ctrl.now,
                  onCeremonyCue: (cue) => playCeremonyCue(ctrl, cue),
                ),
              ),
            ),
            if (playing) _Tray(cards: ctrl.hand?.cards ?? const []),
          ],
        ),
        if (reveal is GameCard)
          ChitRevealOverlay(
            key: ValueKey('reveal-${reveal.id}'),
            caption: 'You picked…',
            onTapSkip: ctrl.consumeReveal,
            child: (w) => PaperSlip(label: reveal.name, width: w),
            onOpenStart: () => ctrl.feedback.play(Sfx.unfold),
            onOpened: ctrl.feedback.heavy,
            onDone: ctrl.consumeReveal,
          ),
      ],
    );
  }
}

/// Dimmed backdrop with the big unfolding chit in the middle.
class ChitRevealOverlay extends StatelessWidget {
  const ChitRevealOverlay({
    super.key,
    required this.child,
    required this.caption,
    required this.onDone,
    required this.onTapSkip,
    this.onOpenStart,
    this.onOpened,
  });

  final Widget Function(double width) child;
  final String caption;
  final VoidCallback onDone;
  final VoidCallback onTapSkip;
  final VoidCallback? onOpenStart;
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = min(MediaQuery.sizeOf(context).width * 0.48, 200.0);
    return Positioned.fill(
      child: GestureDetector(
        onTap: onTapSkip,
        child: ColoredBox(
          color: c.bgBottom.withValues(alpha: 0.78),
          child: Center(
            child: UnfoldReveal(
              width: w,
              height: w * 1.42,
              caption: caption,
              onOpenStart: onOpenStart,
              onOpened: onOpened,
              onDone: onDone,
              child: child(w),
            ),
          ),
        ),
      ),
    );
  }
}

/// My picked slips, private, each unfolding as it arrives.
class _Tray extends StatelessWidget {
  const _Tray({required this.cards});
  final List<GameCard> cards;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = min(70.0, (MediaQuery.sizeOf(context).width - 80) / 4);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.lg,
      ),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: c.outline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 14, color: c.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Your chits · only you can see these',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${cards.length} / 4',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: i < cards.length
                      ? TweenAnimationBuilder<double>(
                          key: ValueKey(cards[i].id),
                          tween: Tween(begin: 0, end: 1),
                          duration: Motion.of(context, Motion.slow),
                          curve: Curves.easeOutCubic,
                          builder: (_, t, _) => FoldPaper(
                            progress: t,
                            width: w,
                            height: w * 1.42,
                            child: PaperSlip(label: cards[i].name, width: w),
                          ),
                        )
                      : Container(
                          width: w,
                          height: w * 1.42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: c.outline, width: 2),
                          ),
                          child: Icon(Icons.add_rounded, color: c.outline),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Non-winners pick a folded character chit after someone collects four.
class CharacterPickView extends StatelessWidget {
  const CharacterPickView({
    super.key,
    required this.ctrl,
    required this.onLeave,
    required this.winnerBanner,
    required this.characterIcon,
  });

  final RoomController ctrl;
  final VoidCallback onLeave;
  final Widget winnerBanner;
  final IconData Function(String name) characterIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final round = ctrl.round!;
    final winner = round.winner!;
    final eligible = round.order.where((u) => u != winner.uid).toList();
    final iWon = winner.uid == ctrl.uid;
    final spectating = !round.order.contains(ctrl.uid);
    final myChar = ctrl.hand?.character;
    final allPicked = round.revealAt != null;
    final open = ctrl.characterChitsOpen;
    final counts = {
      for (final u in eligible) u: round.charPicks.containsValue(u) ? 1 : 0,
    };
    final labels = room.settings.characters
        .take(eligible.length)
        .map((d) => '${d.name} ${d.points}')
        .toList();
    final reveal = ctrl.revealQueue.isNotEmpty ? ctrl.revealQueue.first : null;

    final String title;
    if (allPicked) {
      title = 'Revealing everyone in ${ctrl.revealRemainingSeconds}s';
    } else if (!open) {
      title = 'Folding the character chits…';
    } else if (iWon) {
      title = 'The others are picking characters';
    } else if (spectating) {
      title = 'Watching the character picks';
    } else if (myChar == null) {
      title = 'Pick one chit to find your character';
    } else {
      title = 'Waiting for the others to pick…';
    }

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Leave game',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onLeave,
                  ),
                  const Spacer(),
                  if (open && !allPicked)
                    CountdownBadge(
                      seconds: ctrl.pickRemainingSeconds,
                      progress: (ctrl.pickRemainingSeconds / 20).clamp(
                        0.0,
                        1.0,
                      ),
                      size: 40,
                    ),
                  const SizedBox(width: Space.md),
                ],
              ),
            ),
            winnerBanner,
            const SizedBox(height: Space.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: ChitTable(
                  key: ValueKey('chars-${round.key}'),
                  seed: '${round.key}-characters',
                  ids: round.charChits,
                  picks: round.charPicks,
                  myUid: ctrl.uid,
                  players: {for (final u in eligible) u: room.nameOf(u)},
                  counts: counts,
                  capacity: 1,
                  pending: ctrl.pendingChits,
                  canPick: ctrl.canPickCharacter && reveal == null,
                  onPick: ctrl.pickCharacter,
                  ceremonyLabels: labels,
                  opensAt: round.charPickOpensAt,
                  now: () => ctrl.now,
                  onCeremonyCue: (cue) => playCeremonyCue(ctrl, cue),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.lg,
              ),
              child: Column(
                children: [
                  if (myChar != null && reveal == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.lg,
                        vertical: Space.md,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceHigh,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: c.teal),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(characterIcon(myChar.name), color: c.marigold),
                          const SizedBox(width: Space.sm),
                          Flexible(
                            child: Text(
                              'You are the ${myChar.name} · +${myChar.points}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          Icon(Icons.lock_rounded, size: 14, color: c.muted),
                        ],
                      ),
                    ),
                  if (allPicked && ctrl.isHost)
                    TextButton(
                      onPressed: ctrl.busy ? null : ctrl.revealNow,
                      child: const Text('Reveal now'),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (reveal is CharacterDef)
          ChitRevealOverlay(
            key: ValueKey('char-${reveal.name}'),
            caption: 'Your secret character is…',
            onTapSkip: ctrl.consumeReveal,
            child: (w) => CharacterSlip(
              name: reveal.name,
              points: reveal.points,
              icon: characterIcon(reveal.name),
              width: w,
            ),
            onOpenStart: () => ctrl.feedback.play(Sfx.unfold),
            onOpened: () {
              ctrl.feedback.play(Sfx.reveal);
              ctrl.feedback.heavy();
            },
            onDone: ctrl.consumeReveal,
          ),
      ],
    );
  }
}
