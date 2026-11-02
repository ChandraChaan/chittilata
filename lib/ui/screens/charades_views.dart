import 'package:flutter/material.dart';

import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';
import '../widgets/paper_card.dart';

/// Dumb Charades while a round is on: the actor sees their movie, everyone
/// else picks the right title from six.
class CharadesView extends StatelessWidget {
  const CharadesView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final cr = ctrl.charades!;
    final actor = room.nameOf(cr.actor);
    final ready = ctrl.charadesReadySeconds;
    final left = ctrl.charadesSecondsLeft;
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
                tooltip: 'Leave room',
                icon: const Icon(Icons.close_rounded),
                onPressed: onLeave,
              ),
              Expanded(
                child: Text(
                  '🎭 Round ${cr.roundNo} of ${room.totalRounds}',
                  textAlign: TextAlign.center,
                  style: context.text.titleMedium,
                ),
              ),
              _Timer(seconds: ready > 0 ? ready : left, ready: ready > 0),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.lg,
            ),
            children: ctrl.iAmActor
                ? _actor(context, c, ready)
                : _guesser(context, c, actor, ready),
          ),
        ),
      ],
    );
  }

  List<Widget> _actor(BuildContext context, GameColors c, int ready) {
    final movie = ctrl.myMovie;
    final room = ctrl.room!;
    final cr = ctrl.charades!;
    final wrong = cr.guesses.keys.map(room.nameOf).toList();
    return [
      GoldText(
        ready > 0 ? 'Get ready to act!' : 'Act it out!',
        textAlign: TextAlign.center,
        style: context.text.headlineSmall,
      ),
      const SizedBox(height: Space.md),
      Center(
        child: PaperSlip(
          label: movie ?? '…',
          width: 220,
          state: SlipState.winning,
        ),
      ),
      const SizedBox(height: Space.lg),
      Panel(
        child: Text(
          'No talking, no lip-syncing, no pointing at things with letters. '
          'Show the number of words with fingers, then act each word — or '
          'the whole story!',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, height: 1.4),
        ),
      ),
      if (wrong.isNotEmpty) ...[
        const SizedBox(height: Space.md),
        Text(
          'Wrong guesses so far: ${wrong.join(', ')}',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.kumkum, fontWeight: FontWeight.w700),
        ),
      ],
    ];
  }

  List<Widget> _guesser(
    BuildContext context,
    GameColors c,
    String actor,
    int ready,
  ) {
    final cr = ctrl.charades!;
    final mine = ctrl.myGuess;
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PlayerAvatar(name: actor, size: 44, ring: c.marigold),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              ready > 0 ? '$actor is getting ready…' : 'Watch $actor!',
              style: context.text.titleLarge,
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.xs),
      Text(
        mine == null
            ? 'Which movie is it? You get one guess — the fastest right '
                  'answer scores most.'
            : '❌ Not "${cr.options[mine]}". Wait for the others…',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: mine == null ? c.muted : c.kumkum,
          fontWeight: mine == null ? FontWeight.w500 : FontWeight.w800,
        ),
      ),
      const SizedBox(height: Space.lg),
      for (final (i, title) in cr.options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Opacity(
            opacity: mine != null && mine != i ? 0.5 : 1,
            child: BigButton(
              label: title,
              secondary: true,
              sound: Sfx.select,
              onPressed: ctrl.canGuess ? () => ctrl.guess(i) : null,
            ),
          ),
        ),
    ];
  }
}

class _Timer extends StatelessWidget {
  const _Timer({required this.seconds, required this.ready});
  final int seconds;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final urgent = !ready && seconds <= 10;
    return Container(
      constraints: const BoxConstraints(minWidth: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (urgent ? c.kumkum : c.surfaceHigh).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'in $seconds' : '⏱ $seconds',
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: urgent ? Colors.white : c.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// After a charades round: the answer, who got it, points, the table.
class CharadesResultsView extends StatelessWidget {
  const CharadesResultsView({
    super.key,
    required this.ctrl,
    required this.onLeave,
  });
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final cr = ctrl.charades!;
    final answer = cr.answer == null ? null : cr.options[cr.answer!];
    final scores = cr.scores ?? const <String, int>{};
    final ranking = [...room.activePlayers]
      ..sort((a, b) => (room.totals[b.uid] ?? 0) - (room.totals[a.uid] ?? 0));
    final more = room.currentRound < room.totalRounds;
    // People take turns acting, in room order (bots never act).
    final people = room.memberUids.where((u) => !isBotUid(u)).toList();
    final nextActor = more && people.isNotEmpty
        ? room.nameOf(people[room.currentRound % people.length])
        : null;
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
                tooltip: 'Leave room',
                icon: const Icon(Icons.close_rounded),
                onPressed: onLeave,
              ),
              Expanded(
                child: Text(
                  'Round ${cr.roundNo} of ${room.totalRounds}',
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
            padding: const EdgeInsets.all(Space.lg),
            children: [
              Text(
                cr.solvedBy != null
                    ? '🎉 ${room.nameOf(cr.solvedBy!)} got it!'
                    : (cr.endedReason ?? 'Nobody guessed it.'),
                textAlign: TextAlign.center,
                style: context.text.headlineSmall?.copyWith(
                  color: cr.solvedBy != null ? c.marigold : c.muted,
                ),
              ),
              const SizedBox(height: Space.md),
              if (answer != null)
                Center(
                  child: PaperSlip(
                    label: answer,
                    width: 200,
                    state: SlipState.winning,
                  ),
                ),
              const SizedBox(height: Space.sm),
              Text(
                '${room.nameOf(cr.actor)} acted it out',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: Space.lg),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  children: [
                    for (final p in ranking)
                      ListTile(
                        leading: PlayerAvatar(name: p.name, size: 36),
                        title: Text(
                          p.uid == ctrl.uid ? '${p.name} (you)' : p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: scores[p.uid] == null
                            ? null
                            : Text(
                                '+${scores[p.uid]} this round',
                                style: TextStyle(
                                  color: c.leaf,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                        trailing: Text(
                          '${room.totals[p.uid] ?? 0}',
                          style: context.text.titleLarge,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: ctrl.isHost
              ? BigButton(
                  label: nextActor == null
                      ? 'See final results'
                      : 'Next: $nextActor acts',
                  icon: Icons.play_arrow_rounded,
                  busy: ctrl.busy,
                  onPressed: more ? ctrl.nextRound : null,
                )
              : Text(
                  nextActor == null
                      ? 'That was the last round!'
                      : 'Next up: $nextActor acts. Waiting for the host…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted),
                ),
        ),
      ],
    );
  }
}
