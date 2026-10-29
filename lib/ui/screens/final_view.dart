import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';
import '../widgets/confetti.dart';

/// Final ceremony: King and Queen, leaderboard and round-by-round history.
class FinalView extends StatefulWidget {
  const FinalView({super.key, required this.ctrl, required this.onHome});
  final RoomController ctrl;
  final VoidCallback onHome;

  @override
  State<FinalView> createState() => _FinalViewState();
}

class _FinalViewState extends State<FinalView> {
  late final Future<List<Round>> _rounds = widget.ctrl.repo.loadRounds(
    widget.ctrl.roomId,
    widget.ctrl.room!.gameNo,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctrl = widget.ctrl;
    final room = ctrl.room!;
    final standings = room.finalStandings ?? const <Standing>[];
    final kings = standings.where((s) => s.title == 'King').toList();
    final queens = standings.where((s) => s.title == 'Queen').toList();

    return Stack(
      children: [
        const Positioned.fill(
          child: Confetti(pieces: 110, duration: Duration(seconds: 4)),
        ),
        ListView(
          padding: const EdgeInsets.all(Space.lg),
          children: [
            const SizedBox(height: Space.md),
            Text(
              'GAME OVER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.muted,
                letterSpacing: 3,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: Space.lg),
            if (kings.isNotEmpty)
              _Crowned(
                title: kings.length > 1 ? 'JOINT KINGS' : 'KING',
                names: kings.map((k) => k.name).join(' & '),
                points: kings.first.total,
                color: c.marigold,
                big: true,
              ),
            const SizedBox(height: Space.md),
            if (queens.isNotEmpty)
              _Crowned(
                title: queens.length > 1 ? 'JOINT QUEENS' : 'QUEEN',
                names: queens.map((q) => q.name).join(' & '),
                points: queens.first.total,
                color: c.kumkum,
                big: false,
              ),
            const SizedBox(height: Space.xl),
            Text('Final leaderboard', style: context.text.titleMedium),
            const SizedBox(height: Space.sm),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Column(
                children: [
                  for (final s in standings)
                    ListTile(
                      leading: PlayerAvatar(
                        name: s.name,
                        size: 36,
                        dimmed: s.left,
                      ),
                      title: Text(
                        '#${s.rank}  ${s.name}${s.uid == ctrl.uid ? ' (you)' : ''}'
                        '${s.left ? ' · left' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${s.movieWins} movie win${s.movieWins == 1 ? '' : 's'}',
                        style: TextStyle(color: c.muted),
                      ),
                      trailing: Text(
                        '${s.total}',
                        style: context.text.titleLarge,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xl),
            Text('Round by round', style: context.text.titleMedium),
            const SizedBox(height: Space.sm),
            FutureBuilder<List<Round>>(
              future: _rounds,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(Space.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _RoundTable(
                  room: room,
                  rounds: snap.data!,
                  standings: standings,
                );
              },
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Ties: most points, then most movie wins. Players still tied share the title.',
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
            const SizedBox(height: Space.xl),
            if (ctrl.isHost)
              BigButton(
                label: 'Play again',
                icon: Icons.replay_rounded,
                busy: ctrl.busy,
                onPressed: ctrl.playAgain,
              )
            else
              Text(
                'The host can start a new game with everyone here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            const SizedBox(height: Space.md),
            BigButton(
              label: 'Return to home',
              icon: Icons.home_rounded,
              secondary: true,
              onPressed: widget.onHome,
            ),
            const SizedBox(height: Space.xl),
          ],
        ),
      ],
    );
  }
}

class _Crowned extends StatelessWidget {
  const _Crowned({
    required this.title,
    required this.names,
    required this.points,
    required this.color,
    required this.big,
  });
  final String title;
  final String names;
  final int points;
  final Color color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Duration(milliseconds: big ? 900 : 1300)),
      curve: Curves.elasticOut,
      builder: (_, t, child) =>
          Transform.scale(scale: 0.6 + 0.4 * t, child: child),
      child: Semantics(
        liveRegion: big,
        label: '$title: $names with $points points',
        excludeSemantics: true,
        child: Container(
          padding: EdgeInsets.all(big ? Space.xl : Space.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.35), c.surface],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            children: [
              Transform.rotate(
                angle: big ? -0.08 : 0.08,
                child: Icon(
                  big ? Icons.workspace_premium_rounded : Icons.diamond_rounded,
                  color: color,
                  size: big ? 72 : 48,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w900,
                  fontSize: big ? 18 : 14,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                names,
                textAlign: TextAlign.center,
                style:
                    (big
                            ? context.text.displaySmall
                            : context.text.headlineSmall)
                        ?.copyWith(color: c.onSurface),
              ),
              Text(
                '$points points',
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundTable extends StatelessWidget {
  const _RoundTable({
    required this.room,
    required this.rounds,
    required this.standings,
  });
  final Room room;
  final List<Round> rounds;
  final List<Standing> standings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cell = TextStyle(color: c.onSurface, fontWeight: FontWeight.w600);
    return Panel(
      padding: const EdgeInsets.all(Space.sm),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: DataTable(
              columnSpacing: 18,
              headingRowHeight: 36,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              columns: [
                const DataColumn(label: Text('Player')),
                for (final r in rounds)
                  DataColumn(numeric: true, label: Text('R${r.roundNo}')),
                const DataColumn(numeric: true, label: Text('Total')),
              ],
              rows: [
                for (final s in standings)
                  DataRow(
                    cells: [
                      DataCell(Text(s.name, style: cell)),
                      for (final r in rounds)
                        DataCell(
                          Text(
                            r.status == RoundStatus.aborted
                                ? '—'
                                : '${r.scores?[s.uid] ?? 0}',
                            style: r.winner?.uid == s.uid
                                ? cell.copyWith(
                                    color: c.marigold,
                                    fontWeight: FontWeight.w900,
                                  )
                                : cell,
                          ),
                        ),
                      DataCell(
                        Text(
                          '${s.total}',
                          style: cell.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
