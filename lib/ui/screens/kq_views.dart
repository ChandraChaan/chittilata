import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/chits.dart';
import '../widgets/circle_order.dart';
import '../widgets/common.dart';
import 'game_view.dart';
import 'picking_view.dart';

/// Icon for a King & Queen role name.
IconData roleIcon(String name) => characterIcon(name);

class _KqTopBar extends StatelessWidget {
  const _KqTopBar({required this.ctrl, required this.onLeave, this.trailing});
  final RoomController ctrl;
  final VoidCallback onLeave;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Leave game',
            icon: const Icon(Icons.close_rounded),
            onPressed: onLeave,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'KING & QUEEN · ROUND ${room.currentRound} OF ${room.totalRounds}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.muted,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${room.totals[ctrl.uid] ?? 0} pts',
                  style: context.text.titleMedium?.copyWith(color: c.marigold),
                ),
              ],
            ),
          ),
          SizedBox(width: 48, child: trailing),
          const SizedBox(width: Space.sm),
        ],
      ),
    );
  }
}

/// Everyone picks one folded role chit and privately sees their role.
class KqPickingView extends StatelessWidget {
  const KqPickingView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final kr = ctrl.kqRound!;
    final open = ctrl.kqChitsOpen;
    final picked = kr.picks.containsValue(ctrl.uid);
    final waiting = kr.players.where((p) => !kr.picks.containsValue(p)).length;
    final reveal = ctrl.revealQueue.isNotEmpty ? ctrl.revealQueue.first : null;
    final myRole = ctrl.kqRole;

    final title = !open
        ? 'Writing the roles'
        : !picked
        ? 'Pick one folded chit'
        : 'Waiting for $waiting more player${waiting == 1 ? '' : 's'}…';
    final subtitle = !open
        ? 'Folding and shuffling ${kr.chain.join(', ')}…'
        : !picked
        ? 'Your role is inside. Keep it secret!'
        : 'Keep a straight face.';

    return Stack(
      children: [
        Column(
          children: [
            _KqTopBar(
              ctrl: ctrl,
              onLeave: onLeave,
              trailing: open
                  ? CountdownBadge(
                      seconds: ctrl.kqPickRemainingSeconds,
                      progress: (ctrl.kqPickRemainingSeconds / 20).clamp(
                        0.0,
                        1.0,
                      ),
                      size: 40,
                    )
                  : null,
            ),
            Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  Text(title, style: context.text.titleLarge),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: ChitTable(
                  key: ValueKey('kq-${kr.key}'),
                  seed: '${kr.key}-roles',
                  ids: kr.chits,
                  picks: kr.picks,
                  myUid: ctrl.uid,
                  players: {for (final p in kr.players) p: room.nameOf(p)},
                  counts: {
                    for (final p in kr.players)
                      p: kr.picks.containsValue(p) ? 1 : 0,
                  },
                  capacity: 1,
                  pending: ctrl.pendingChits,
                  canPick: ctrl.canKqPick && reveal == null,
                  onPick: ctrl.kqPick,
                  ceremonyLabels: kr.chain,
                  opensAt: kr.pickOpensAt,
                  now: () => ctrl.now,
                  onCeremonyCue: (cue) => playCeremonyCue(ctrl, cue),
                ),
              ),
            ),
            if (myRole != null && reveal == null)
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: _MyRoleCard(name: myRole.name!, points: myRole.points!),
              )
            else
              const SizedBox(height: Space.lg),
          ],
        ),
        if (reveal is KqRoleDef)
          ChitRevealOverlay(
            key: ValueKey('kqrole-${reveal.name}'),
            caption: 'Your secret role is…',
            onTapSkip: ctrl.consumeReveal,
            child: (w) => CharacterSlip(
              name: reveal.name,
              points: reveal.points,
              icon: roleIcon(reveal.name),
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

class _MyRoleCard extends StatelessWidget {
  const _MyRoleCard({required this.name, required this.points, this.public});
  final String name;
  final int points;

  /// True when everyone already knows this role (guesser or locked).
  final bool? public;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label:
          'Your role: $name, $points points${public == true ? '' : ', secret'}',
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.slow),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: Tween(begin: 0.5, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Container(
          key: ValueKey(name),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.marigold, width: 2),
            boxShadow: [
              BoxShadow(
                color: c.marigold.withValues(alpha: 0.3),
                blurRadius: 14,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(roleIcon(name), color: c.kumkum, size: 28),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(
                  'You are the $name · $points',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Icon(
                public == true ? Icons.visibility_rounded : Icons.lock_rounded,
                size: 16,
                color: c.ink.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The guessing table: who must find whom, candidates, exchanges, history.
class KqGuessView extends StatelessWidget {
  const KqGuessView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final kr = ctrl.kqRound!;
    final guesser = kr.guesser;
    final guesserName = guesser == ctrl.uid
        ? 'You'
        : room.nameOf(guesser ?? '');
    final announcing = ctrl.kqAnnounceRemainingSeconds > 0;
    final myTurn = ctrl.kqMyTurn;
    final candidates = kr.candidates.toSet();
    final selected = ctrl.kqSelectedTarget;
    final myRole = ctrl.kqRole;
    final myRolePublic = kr.publicRoleOf(ctrl.uid ?? '') != null;
    final secs = max(0, (ctrl.kqTurnRemainingMs / 1000).ceil());

    final String title;
    final String subtitle;
    if (announcing && kr.history.isEmpty) {
      title = guesser == ctrl.uid
          ? 'You are the King!'
          : '${room.nameOf(guesser ?? '')} is the King!';
      subtitle =
          'The King must find the ${kr.targetRole} in '
          '${ctrl.kqAnnounceRemainingSeconds}…';
    } else if (myTurn) {
      title = 'Find the ${kr.targetRole}!';
      subtitle = 'You are the ${kr.seekerRole}. Tap who you think it is.';
    } else {
      title = '$guesserName (${kr.seekerRole}) is finding the ${kr.targetRole}';
      subtitle = 'Wrong guesses swap roles. Watch closely!';
    }

    return Column(
      children: [
        _KqTopBar(
          ctrl: ctrl,
          onLeave: onLeave,
          trailing: !announcing && kr.timed
              ? CountdownBadge(
                  seconds: secs,
                  progress: ctrl.kqTurnProgress,
                  size: 40,
                )
              : null,
        ),
        _ChainProgress(round: kr),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.medium),
            width: double.infinity,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: myTurn
                  ? c.marigold.withValues(alpha: 0.16)
                  : c.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: myTurn ? c.marigold : c.outline,
                width: myTurn ? 2 : 1,
              ),
            ),
            child: Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  Icon(
                    roleIcon(kr.seekerRole),
                    color: c.marigold,
                    size: announcing ? 44 : 30,
                  ),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: context.text.titleLarge?.copyWith(
                      color: myTurn ? c.marigold : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Column(
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final p in kr.players)
                      _PlayerTile(
                        name: p == ctrl.uid ? 'You' : room.nameOf(p),
                        avatarName: room.nameOf(p),
                        publicRole: kr.publicRoleOf(p),
                        locked: kr.locked.containsKey(p),
                        isGuesser: p == guesser,
                        notTarget: kr.excluded.contains(p)
                            ? kr.targetRole
                            : null,
                        candidate: myTurn && candidates.contains(p),
                        selected: selected == p,
                        onTap: () => ctrl.kqSelect(p),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                _History(round: kr, room: room, me: ctrl.uid),
              ],
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
              if (myRole != null)
                _MyRoleCard(
                  name: myRole.name!,
                  points: myRole.points!,
                  public: myRolePublic,
                ),
              if (myTurn) ...[
                const SizedBox(height: Space.sm),
                SizedBox(
                  width: double.infinity,
                  child: BigButton(
                    label: selected == null
                        ? 'Tap a player to guess'
                        : 'Is ${room.nameOf(selected)} the ${kr.targetRole}?',
                    icon: selected == null ? null : Icons.search_rounded,
                    busy: ctrl.busy,
                    onPressed: selected == null ? null : ctrl.kqConfirmGuess,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChainProgress extends StatelessWidget {
  const _ChainProgress({required this.round});
  final KqRound round;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: round.chain.length,
        separatorBuilder: (_, _) =>
            Icon(Icons.chevron_right_rounded, size: 18, color: c.muted),
        itemBuilder: (_, i) {
          final found = i < round.step || (i == round.step);
          final current = i == round.step + 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: current
                  ? c.marigold
                  : found
                  ? c.leaf.withValues(alpha: 0.25)
                  : c.surfaceHigh,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              round.chain[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: current ? c.ink : c.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.name,
    required this.avatarName,
    required this.publicRole,
    required this.locked,
    required this.isGuesser,
    required this.notTarget,
    required this.candidate,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String avatarName;
  final String? publicRole;
  final bool locked;
  final bool isGuesser;
  final String? notTarget;
  final bool candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = min(150.0, (MediaQuery.sizeOf(context).width - 64) / 2);
    final border = selected
        ? c.marigold
        : isGuesser
        ? c.teal
        : candidate
        ? c.marigold.withValues(alpha: 0.5)
        : c.outline;
    return Semantics(
      button: candidate,
      selected: selected,
      label: [
        name,
        ?publicRole,
        if (locked) 'confirmed',
        if (notTarget != null) 'not the $notTarget',
        if (candidate) 'can be guessed',
      ].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: candidate ? onTap : null,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          width: w,
          padding: const EdgeInsets.all(Space.md),
          transform: Matrix4.translationValues(0, selected ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: selected
                ? c.marigold.withValues(alpha: 0.18)
                : c.surface.withValues(alpha: candidate || isGuesser ? 1 : 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: selected ? 3 : 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(
                name: avatarName,
                size: 40,
                dimmed: !candidate && !isGuesser && publicRole == null,
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              if (publicRole != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(roleIcon(publicRole!), size: 14, color: c.marigold),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        publicRole!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.marigold,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.verified_rounded, size: 14, color: c.leaf),
                    ],
                  ],
                )
              else if (notTarget != null)
                Text(
                  'not the $notTarget',
                  style: TextStyle(
                    color: c.kumkum,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  '? ? ?',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12,
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.round, required this.room, required this.me});
  final KqRound round;
  final Room room;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (round.history.isEmpty) return const SizedBox.shrink();
    String n(String u) => u == me ? 'You' : room.nameOf(u);
    final items = round.history.reversed.take(5).toList();
    return Panel(
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happened',
            style: TextStyle(color: c.muted, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Space.xs),
          for (final h in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    h.correct
                        ? Icons.check_circle_rounded
                        : Icons.swap_horiz_rounded,
                    size: 18,
                    color: h.correct ? c.leaf : c.kumkum,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(switch ((h.correct, h.kind)) {
                      (true, 'forced') =>
                        '${n(h.target)} must be the ${round.chain[h.step + 1]}: nobody else was left.',
                      (true, _) =>
                        '${n(h.guesser)} found the ${round.chain[h.step + 1]}: ${n(h.target)}!',
                      (false, 'timeout') =>
                        "Time's up for ${n(h.guesser)}. The game picked ${n(h.target)}: wrong, roles swapped.",
                      _ =>
                        '${n(h.guesser)} guessed ${n(h.target)} for ${round.chain[h.step + 1]}: wrong, roles swapped.',
                    }, style: const TextStyle(height: 1.3)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// End of a King & Queen round: every role revealed, points, leaderboard.
class KqResultsView extends StatelessWidget {
  const KqResultsView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final kr = ctrl.kqRound!;
    final aborted = kr.status == KqStatus.aborted;
    final byRole = [...kr.players]
      ..sort(
        (a, b) =>
            (kr.revealedRoles?[a] ?? 99).compareTo(kr.revealedRoles?[b] ?? 99),
      );
    final ranked = [...kr.players]
      ..sort((a, b) => (room.totals[b] ?? 0).compareTo(room.totals[a] ?? 0));
    final moreRounds = room.currentRound < room.totalRounds;
    final swaps = kr.history.where((h) => !h.correct).length;

    return Column(
      children: [
        _KqTopBar(ctrl: ctrl, onLeave: onLeave),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              if (aborted)
                Panel(
                  child: Column(
                    children: [
                      Icon(Icons.block_rounded, color: c.kumkum, size: 48),
                      Text('Round cancelled', style: context.text.titleLarge),
                      Text(
                        '${kr.abortedReason ?? 'A player left.'} No points this round.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                )
              else ...[
                Text(
                  'Roles revealed',
                  textAlign: TextAlign.center,
                  style: context.text.headlineSmall,
                ),
                Text(
                  '${kr.history.length} guesses · $swaps role swap${swaps == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
                const SizedBox(height: Space.lg),
                for (final (i, p) in byRole.indexed)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Motion.of(
                      context,
                      Duration(milliseconds: 400 + i * 160),
                    ),
                    curve: Curves.easeOutBack,
                    builder: (_, t, child) => Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - t) * 20),
                        child: child,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Panel(
                        color: kr.revealedRoles?[p] == 0
                            ? c.marigold.withValues(alpha: 0.16)
                            : null,
                        padding: const EdgeInsets.all(Space.md),
                        child: Row(
                          children: [
                            Icon(
                              roleIcon(kr.chain[kr.revealedRoles?[p] ?? 0]),
                              color: c.marigold,
                              size: 30,
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p == ctrl.uid
                                        ? '${room.nameOf(p)} (you)'
                                        : room.nameOf(p),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    kr.chain[kr.revealedRoles?[p] ?? 0],
                                    style: TextStyle(
                                      color: c.marigold,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '+${kr.scores?[p] ?? 0}',
                              style: context.text.titleLarge?.copyWith(
                                color: c.leaf,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: Space.lg),
              Text('Leaderboard', style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Column(
                  children: [
                    for (final (i, p) in ranked.indexed)
                      ListTile(
                        dense: true,
                        leading: Text(
                          '#${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: i == 0 ? c.marigold : c.muted,
                          ),
                        ),
                        title: Text(
                          p == ctrl.uid
                              ? '${room.nameOf(p)} (you)'
                              : room.nameOf(p),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: Text(
                          '${room.totals[p] ?? 0}',
                          style: context.text.titleMedium,
                        ),
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
                    label: moreRounds
                        ? 'Start round ${room.currentRound + 1}'
                        : 'See final results',
                    icon: Icons.arrow_forward_rounded,
                    busy: ctrl.busy,
                    onPressed: moreRounds ? ctrl.nextRound : null,
                  )
                : BigButton(
                    label:
                        'Waiting for ${room.nameOf(room.hostUid)} to start round ${room.currentRound + 1}',
                    secondary: true,
                    onPressed: null,
                  ),
          ),
        ),
      ],
    );
  }
}
