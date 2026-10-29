import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/circle_order.dart';
import '../widgets/common.dart';
import '../widgets/confetti.dart';
import '../widgets/paper_card.dart';

/// The live round: intro → passing → winner + secret characters.
class GameView extends StatelessWidget {
  const GameView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final room = ctrl.room!;
    final round = ctrl.round!;
    final phase = ctrl.phase;
    final width = MediaQuery.sizeOf(context).width;
    final circleSize = min(width - 2 * Space.lg, 300.0);

    final seats = [
      for (final u in round.order)
        CircleSeat(
          uid: u,
          name: room.nameOf(u),
          cards: phase == Phase.exchange ? round.handSizes[u] : null,
          online: ctrl.isOnline(u),
          isMe: u == ctrl.uid,
        ),
    ];

    return Stack(
      children: [
        Column(
          children: [
            _GameTopBar(ctrl: ctrl, onLeave: onLeave),
            _MovieStrip(names: round.movieNames),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: Space.sm),
                    CircleOrder(
                      seats: seats,
                      currentUid: phase == Phase.exchange
                          ? round.currentUid
                          : null,
                      nextUid: phase == Phase.exchange ? round.nextUid : null,
                      progress: round.timed ? ctrl.turnProgress : null,
                      size: circleSize,
                    ),
                    const SizedBox(height: Space.sm),
                    if (phase == Phase.exchange) _TurnBanner(ctrl: ctrl),
                  ],
                ),
              ),
            ),
            _HandArea(ctrl: ctrl),
          ],
        ),
        if (phase == Phase.intro) _IntroOverlay(ctrl: ctrl, seats: seats),
      ],
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
                Text(
                  '${room.totals[me] ?? 0} pts',
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

class _MovieStrip extends StatelessWidget {
  const _MovieStrip({required this.names});
  final List<String> names;

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
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: c.surfaceHigh,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            names[i],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final round = ctrl.round!;
    final mine = ctrl.myTurn;
    final ms = ctrl.turnRemainingMs;
    final secs = max(0, (ms / 1000).ceil());
    final expired = ms <= 0;
    final next = round.nextUid == ctrl.uid ? 'you' : room.nameOf(round.nextUid);
    final who = room.nameOf(round.currentUid);

    final title = expired
        ? "Time's up!"
        : mine
        ? 'Your turn'
        : '$who is choosing';
    final subtitle = expired
        ? 'Passing a slip automatically…'
        : mine
        ? 'Pick one slip to pass to $next'
        : round.nextUid == ctrl.uid
        ? 'Get ready, a slip is coming to you'
        : 'Then passes to $next';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.medium),
        padding: const EdgeInsets.all(Space.md),
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
            if (round.timed)
              CountdownBadge(
                seconds: secs,
                progress: ctrl.turnProgress,
                size: 56,
              )
            else
              Icon(Icons.hourglass_empty_rounded, color: c.muted, size: 40),
            const SizedBox(width: Space.md),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.titleLarge?.copyWith(
                        color: expired ? c.kumkum : (mine ? c.marigold : null),
                      ),
                    ),
                    Text(subtitle, style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
            ),
          ],
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
    final canAct = ctrl.myTurn && !ctrl.busy && ctrl.turnRemainingMs > 0;
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
              Icon(Icons.lock_rounded, size: 14, color: c.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Your slips · only you can see these',
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
          const SizedBox(height: Space.lg + 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final card in hand.cards)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
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
            ],
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            width: double.infinity,
            child: BigButton(
              label: !ctrl.myTurn
                  ? 'Wait for your turn'
                  : ctrl.selectedCardId == null
                  ? 'Tap a slip to choose it'
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
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              round.tiebreak ? 'TIE-BREAKER' : 'ROUND ${round.roundNo}',
              style: context.text.displaySmall?.copyWith(color: c.marigold),
            ),
            const SizedBox(height: Space.sm),
            Text(
              'This round\'s passing circle',
              style: TextStyle(color: c.muted),
            ),
            const SizedBox(height: Space.lg),
            CircleOrder(
              seats: seats,
              size: min(MediaQuery.sizeOf(context).width - 48, 300),
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
        ),
      ),
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
    final w = round.winner!;
    final iWon = w.uid == ctrl.uid;
    final width = MediaQuery.sizeOf(context).width;
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
