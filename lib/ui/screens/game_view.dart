import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/circle_order.dart';
import '../widgets/common.dart';
import '../widgets/confetti.dart';
import '../widgets/paper_card.dart';
import '../widgets/polish.dart';

/// The live round: intro → passing → winner + secret characters.
///
/// Everything fits on one screen with no scrolling: the circle takes the
/// room left after the status panel and the hand, so the timer, the lap
/// count and the host's End-round control are always in view.
class GameView extends StatelessWidget {
  const GameView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final room = ctrl.room!;
    final round = ctrl.round!;
    final phase = ctrl.phase;

    final seats = [
      for (final u in round.order)
        CircleSeat(
          uid: u,
          name: room.nameOf(u),
          cards: phase == Phase.exchange ? round.handSizes[u] : null,
          online: ctrl.isOnline(u),
          isMe: u == ctrl.uid,
          points: round.tiebreak ? null : room.totals[u] ?? 0,
        ),
    ];
    final la = round.lastAction;
    final flight = la == null
        ? null
        : PassFlight(
            from: la.fromUid,
            to: la.toUid,
            key: '${round.key}:${la.turnId}',
          );
    final counts = <String, int>{};
    for (final card in ctrl.hand?.cards ?? const <GameCard>[]) {
      counts[card.name] = (counts[card.name] ?? 0) + 1;
    }

    return Stack(
      children: [
        Column(
          children: [
            _GameTopBar(ctrl: ctrl, onLeave: onLeave),
            _MovieStrip(names: round.movieNames, counts: counts),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = min(
                    300.0,
                    min(box.maxWidth - 2 * Space.lg, box.maxHeight - 12),
                  ).clamp(120.0, 300.0);
                  return _PassTarget(
                    ctrl: ctrl,
                    child: Center(
                      child: CircleOrder(
                        seats: seats,
                        currentUid: phase == Phase.exchange
                            ? round.currentUid
                            : null,
                        nextUid: phase == Phase.exchange ? round.nextUid : null,
                        progress: round.timed ? ctrl.turnProgress : null,
                        size: size,
                        flight: flight,
                        center: phase == Phase.exchange
                            ? _CircleCentre(ctrl: ctrl, size: size)
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (phase == Phase.exchange) _StatusPanel(ctrl: ctrl),
            _HandArea(ctrl: ctrl),
          ],
        ),
        if (phase == Phase.intro) _IntroOverlay(ctrl: ctrl, seats: seats),
      ],
    );
  }
}

/// The circle doubles as the drop zone: on your turn, drag a slip onto it
/// to pass. Lights up while a slip hovers over it.
class _PassTarget extends StatelessWidget {
  const _PassTarget({required this.ctrl, required this.child});
  final RoomController ctrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final round = ctrl.round!;
    final next = round.nextUid == ctrl.uid
        ? 'yourself'
        : room.nameOf(round.nextUid);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => ctrl.myTurn && !ctrl.busy,
      onAcceptWithDetails: (d) => ctrl.passCard(d.data),
      builder: (context, candidates, _) {
        final hot = candidates.isNotEmpty;
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            IgnorePointer(
              child: AnimatedOpacity(
                duration: Motion.of(context, Motion.fast),
                opacity: hot ? 1 : 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                    decoration: BoxDecoration(
                      color: c.marigold,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: c.marigold.withValues(alpha: 0.6),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                    child: Text(
                      'Drop to pass to $next',
                      style: TextStyle(
                        color: c.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GameTopBar extends StatelessWidget {
  const _GameTopBar({required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final me = ctrl.uid;
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
                  ctrl.round?.tiebreak == true
                      ? 'TIE-BREAKER'
                      : 'ROUND ${room.currentRound} OF ${room.settings.rounds}',
                  style: TextStyle(
                    color: c.muted,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                AnimatedPoints(
                  value: room.totals[me] ?? 0,
                  style: context.text.titleMedium?.copyWith(color: c.marigold),
                ),
              ],
            ),
          ),
          Tooltip(
            message: ctrl.connected ? 'Connected' : 'Reconnecting',
            child: Icon(
              ctrl.connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: ctrl.connected ? c.leaf : c.kumkum,
            ),
          ),
          const SizedBox(width: Space.md),
        ],
      ),
    );
  }
}

/// The movies in play, each with how many of its slips you hold, so you
/// can see at a glance which set you are closest to.
class _MovieStrip extends StatelessWidget {
  const _MovieStrip({required this.names, this.counts = const {}});
  final List<String> names;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: names.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final n = counts[names[i]] ?? 0;
          final hot = n >= 3;
          return AnimatedContainer(
            duration: Motion.of(context, Motion.medium),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: hot ? c.leaf.withValues(alpha: 0.22) : c.surfaceHigh,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: hot ? c.leaf : (n > 0 ? c.outline : Colors.transparent),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  names[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.onSurface,
                  ),
                ),
                if (n > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '×$n',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: hot ? c.leaf : c.marigold,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The middle of the circle during passing: the countdown (big, where
/// every eye already is) and the lap count.
class _CircleCentre extends StatelessWidget {
  const _CircleCentre({required this.ctrl, required this.size});
  final RoomController ctrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final round = ctrl.round!;
    final secs = max(0, (ctrl.turnRemainingMs / 1000).ceil());
    final badge = (size * 0.24).clamp(40.0, 72.0);
    final stalemateNow = !round.tiebreak && ctrl.lapsUntilStalemate == 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (round.timed)
          CountdownBadge(
            seconds: secs,
            progress: ctrl.turnProgress,
            size: badge,
          )
        else
          Icon(
            Icons.hourglass_empty_rounded,
            color: c.muted,
            size: badge * 0.7,
          ),
        if (size >= 200 && !round.tiebreak) ...[
          const SizedBox(height: 4),
          InfoChip(
            label: 'LAP ${round.laps + 1}',
            color: stalemateNow ? c.kumkum : c.muted,
          ),
        ],
      ],
    );
  }
}

/// Whose turn it is, the countdown, and how many laps the slips have gone
/// round. After a few laps with no winner the host gets a compact
/// "End round" control here (a stalemate: everyone picks a character chit).
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final round = ctrl.round!;
    final mine = ctrl.myTurn;
    final ms = ctrl.turnRemainingMs;
    final expired = ms <= 0;
    final next = round.nextUid == ctrl.uid ? 'you' : room.nameOf(round.nextUid);
    final who = room.nameOf(round.currentUid);
    final laps = round.laps;
    final stalemateNow = !round.tiebreak && ctrl.lapsUntilStalemate == 0;

    final title = expired
        ? "Time's up!"
        : mine
        ? 'Your turn'
        : '$who is choosing';
    final subtitle = ctrl.canEndExchange
        ? 'No winner after $laps laps. You can end the round: everyone '
              'picks a character chit, King included.'
        : stalemateNow && !ctrl.isHost
        ? '${room.nameOf(room.hostUid)} can end this round now (no winner '
              'after $laps laps).'
        : expired
        ? (mine
              ? 'Still your turn: pass one slip to $next'
              : 'Waiting for $who to pass')
        : mine
        ? 'Drag a slip onto the circle, or tap it and press Pass'
        : round.nextUid == ctrl.uid
        ? 'Get ready, a slip is coming to you'
        : 'Then passes to $next';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xs,
        Space.lg,
        Space.xs,
      ),
      child: PulseGlow(
        on: mine && !expired,
        color: c.marigold,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          padding: const EdgeInsets.fromLTRB(
            Space.md,
            Space.sm,
            Space.md,
            Space.sm,
          ),
          decoration: BoxDecoration(
            color: mine
                ? c.marigold.withValues(alpha: 0.16)
                : c.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: mine ? c.marigold : c.outline,
              width: mine ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                expired
                    ? Icons.alarm_rounded
                    : mine
                    ? Icons.touch_app_rounded
                    : Icons.hourglass_top_rounded,
                color: expired ? c.kumkum : (mine ? c.marigold : c.muted),
                size: 28,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: expired
                              ? c.kumkum
                              : (mine ? c.marigold : null),
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              if (ctrl.canEndExchange)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.kumkum,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: ctrl.busy ? null : ctrl.endExchange,
                  icon: const Icon(Icons.flag_rounded, size: 18),
                  label: const Text(
                    'End round',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandArea extends StatefulWidget {
  const _HandArea({required this.ctrl});
  final RoomController ctrl;

  @override
  State<_HandArea> createState() => _HandAreaState();
}

class _HandAreaState extends State<_HandArea> {
  String? _flyingId;

  Future<void> _pass() async {
    final ctrl = widget.ctrl;
    setState(() => _flyingId = ctrl.selectedCardId);
    await ctrl.passSelected();
    if (mounted) setState(() => _flyingId = null);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final c = context.colors;
    final hand = ctrl.hand;
    final round = ctrl.round!;
    final room = ctrl.room!;
    if (ctrl.joinsNextRound) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: c.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_seat_rounded, color: c.leaf, size: 32),
            const SizedBox(height: Space.sm),
            Text("You're in!", style: context.text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'This round started before you sat down. You get your chits '
              'from the next round. Cheer along meanwhile!',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.35),
            ),
          ],
        ),
      );
    }
    if (ctrl.spectating) {
      final names = round.order.map(room.nameOf).join(' and ');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.xl),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: c.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_rounded, color: c.teal, size: 32),
            const SizedBox(height: Space.sm),
            Text(
              'You are watching the tie-breaker',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(
              '$names are playing for the ${room.tiebreak?.title ?? 'title'}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
          ],
        ),
      );
    }
    if (hand == null) {
      return const Padding(
        padding: EdgeInsets.all(Space.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final counts = <String, int>{};
    for (final card in hand.cards) {
      counts[card.name] = (counts[card.name] ?? 0) + 1;
    }
    final four = matchingName(hand.cards);
    // The set you are closest to completing.
    final best = counts.entries.fold<MapEntry<String, int>?>(
      null,
      (a, e) => a == null || e.value > a.value ? e : a,
    );
    final collecting = best != null && best.value >= 2 && four == null;
    // A late player can still pass: nothing is passed for them automatically.
    final canAct = ctrl.myTurn && !ctrl.busy;
    final width = MediaQuery.sizeOf(context).width;
    final slipWidth = min(
      84.0,
      (width - 2 * Space.lg - 4 * 8) / max(4, hand.cards.length),
    );
    final nextName = round.nextUid == ctrl.uid
        ? 'you'
        : room.nameOf(round.nextUid);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
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
              Icon(
                collecting ? Icons.auto_awesome_rounded : Icons.lock_rounded,
                size: 14,
                color: collecting ? c.leaf : c.muted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  collecting
                      ? 'Collecting ${best.key} · ${best.value} of 4'
                      : 'Your slips · only you can see these',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: collecting ? c.leaf : c.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${hand.cards.length} slips',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
          if (four != null && hand.cards.length == 5 && ctrl.myTurn)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Four $four! Pass the odd slip to win.',
                style: TextStyle(color: c.leaf, fontWeight: FontWeight.w900),
              ),
            ),
          const SizedBox(height: Space.md + 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, card) in ctrl.orderedHand.indexed)
                // Drop another slip here to put it in this spot.
                DragTarget<String>(
                  onWillAcceptWithDetails: (d) => d.data != card.id,
                  onAcceptWithDetails: (d) => ctrl.reorderHand(d.data, i),
                  builder: (context, candidates, _) => Padding(
                    padding: EdgeInsets.only(
                      left: candidates.isNotEmpty ? 14 : 4,
                      right: 4,
                    ),
                    child: _DraggableSlip(
                      card: card,
                      width: slipWidth,
                      child: _AnimatedSlip(
                        key: ValueKey(card.id),
                        card: card,
                        width: slipWidth,
                        flying: card.id == _flyingId,
                        isNew: card.id == hand.incomingCardId,
                        state: card.id == ctrl.selectedCardId
                            ? SlipState.selected
                            : card.id == hand.incomingCardId
                            ? SlipState.incoming
                            : (counts[card.name] ?? 0) >= 3
                            ? SlipState.matching
                            : SlipState.normal,
                        onTap: canAct ? () => ctrl.select(card.id) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          SizedBox(
            width: double.infinity,
            child: BigButton(
              label: !ctrl.myTurn
                  ? 'Wait for your turn · drag to rearrange'
                  : ctrl.selectedCardId == null
                  ? 'Tap a slip, or drag it to the circle'
                  : 'Pass to $nextName',
              icon: ctrl.myTurn && ctrl.selectedCardId != null
                  ? Icons.send_rounded
                  : null,
              busy: ctrl.busy,
              secondary: !ctrl.myTurn,
              onPressed: canAct && ctrl.selectedCardId != null ? _pass : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A slip you can pick up: drop it on another slip to rearrange your hand,
/// or (on your turn) on the circle to pass it. Taps still select it.
class _DraggableSlip extends StatelessWidget {
  const _DraggableSlip({
    required this.card,
    required this.width,
    required this.child,
  });
  final GameCard card;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: card.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: Offset(-width * 0.6, -width * 1.1),
        child: Transform.rotate(
          angle: -0.06,
          child: PaperSlip(
            label: card.name,
            width: width * 1.2,
            state: SlipState.selected,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: child),
      child: child,
    );
  }
}

/// A slip that drops in when received and flies up when passed.
class _AnimatedSlip extends StatelessWidget {
  const _AnimatedSlip({
    super.key,
    required this.card,
    required this.width,
    required this.state,
    required this.flying,
    required this.isNew,
    this.onTap,
  });

  final GameCard card;
  final double width;
  final SlipState state;
  final bool flying;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.slow);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: isNew ? 0 : 1, end: 1),
      duration: d,
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Transform.translate(
        offset: Offset(0, (1 - t) * -120),
        child: Opacity(opacity: t.clamp(0, 1), child: child),
      ),
      child: AnimatedSlide(
        duration: Motion.of(context, Motion.medium),
        offset: flying ? const Offset(0, -2.5) : Offset.zero,
        curve: Curves.easeInCubic,
        child: AnimatedOpacity(
          duration: Motion.of(context, Motion.medium),
          opacity: flying ? 0 : 1,
          child: PaperSlip(
            label: card.name,
            width: width,
            state: state,
            onTap: onTap,
            semanticsHint: onTap == null
                ? null
                : 'Double tap to choose this slip',
          ),
        ),
      ),
    );
  }
}

class _IntroOverlay extends StatelessWidget {
  const _IntroOverlay({required this.ctrl, required this.seats});
  final RoomController ctrl;
  final List<CircleSeat> seats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final round = ctrl.round!;
    final room = ctrl.room!;
    final first = room.nameOf(round.order.first);
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.bgTop, c.bgBottom],
          ),
        ),
        // Scrolls rather than overflowing on short screens or large text.
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 48),
              child: _introColumn(context, c, round, room, first, box),
            ),
          ),
        ),
      ),
    );
  }

  Widget _introColumn(
    BuildContext context,
    GameColors c,
    Round round,
    Room room,
    String first,
    BoxConstraints box,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          round.tiebreak ? 'TIE-BREAKER' : 'ROUND ${round.roundNo}',
          style: context.text.displaySmall?.copyWith(color: c.marigold),
        ),
        const SizedBox(height: Space.sm),
        Text('This round\'s passing circle', style: TextStyle(color: c.muted)),
        const SizedBox(height: Space.lg),
        CircleOrder(
          seats: seats,
          size: min(min(box.maxWidth - 48, box.maxHeight * 0.42), 300),
        ),
        const SizedBox(height: Space.lg),
        Text(
          '${round.order.map((u) => u == ctrl.uid ? 'You' : room.nameOf(u)).join(' → ')} → '
          '${round.order.first == ctrl.uid ? 'You' : first}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Space.xl),
        Text(
          round.order.first == ctrl.uid
              ? 'You pass first!'
              : '$first passes first',
          style: context.text.titleMedium,
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Starting in ${ctrl.introRemainingSeconds}…',
          style: context.text.headlineSmall?.copyWith(color: c.teal),
        ),
      ],
    );
  }
}

/// Compact winner announcement shown above the character chits.
class WinnerBanner extends StatelessWidget {
  const WinnerBanner({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final round = ctrl.round!;
    final room = ctrl.room!;
    final w = round.winner;
    final width = MediaQuery.sizeOf(context).width;
    if (w == null) {
      // A stalemate: the host ended a long exchange with no winner.
      return Column(
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              'NO WINNER THIS ROUND',
              textAlign: TextAlign.center,
              style: context.text.headlineSmall?.copyWith(color: c.kumkum),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${round.laps} laps and nobody collected four. Everyone picks a '
            'character chit: the King chit is worth ${room.settings.winPoints}!',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
          ),
        ],
      );
    }
    final iWon = w.uid == ctrl.uid;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        const SizedBox(height: 150, width: double.infinity, child: Confetti()),
        Column(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                iWon ? 'YOU WIN!' : '${room.nameOf(w.uid).toUpperCase()} WINS!',
                textAlign: TextAlign.center,
                style: context.text.headlineMedium?.copyWith(color: c.marigold),
              ),
            ),
            const SizedBox(height: Space.xs),
            _FourOfAKind(name: w.movie, width: min(52, (width - 80) / 6)),
            const SizedBox(height: Space.xs),
            Text(
              round.tiebreak
                  ? 'Wins the tie-breaker'
                  : 'Four matching slips · +${w.points} points',
              style: TextStyle(color: c.leaf, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ],
    );
  }
}

class _FourOfAKind extends StatelessWidget {
  const _FourOfAKind({required this.name, required this.width});
  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 900)),
      curve: Curves.easeOutBack,
      builder: (_, t, _) => SizedBox(
        height: width * 1.6,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Transform.translate(
                offset: Offset((1.5 - i) * width * (1 - t), 0),
                child: Transform.rotate(
                  angle: (i - 1.5) * 0.08 * t,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3 * t),
                    child: PaperSlip(
                      label: name,
                      width: width,
                      state: SlipState.winning,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character});
  final CharacterDef character;

  static IconData iconFor(String name) => switch (name.toLowerCase()) {
    'king' => Icons.workspace_premium_rounded,
    'queen' => Icons.diamond_rounded,
    'police' => Icons.local_police_rounded,
    'thief' => Icons.directions_run_rounded,
    'minister' => Icons.account_balance_rounded,
    'commander' => Icons.shield_rounded,
    'merchant' => Icons.storefront_rounded,
    'poet' => Icons.history_edu_rounded,
    'farmer' => Icons.agriculture_rounded,
    'jester' => Icons.theater_comedy_rounded,
    _ => Icons.star_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Flip-in reveal of the private character.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, const Duration(milliseconds: 800)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY((1 - t) * pi / 2),
        child: child,
      ),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.surfaceHigh, c.surface]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.teal, width: 2),
        ),
        child: Column(
          children: [
            Text(
              'YOUR SECRET CHARACTER',
              style: TextStyle(
                color: c.teal,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: Space.md),
            Icon(iconFor(character.name), size: 56, color: c.marigold),
            const SizedBox(height: Space.sm),
            Text(character.name, style: context.text.headlineMedium),
            Text(
              '+${character.points} points',
              style: context.text.titleMedium?.copyWith(color: c.leaf),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exposed for the results screen.
IconData characterIcon(String name) => _CharacterCard.iconFor(name);
