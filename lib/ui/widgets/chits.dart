import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'common.dart';
import 'paper_card.dart';

/// Where a chit lies on the table, as fractions of the table size, so every
/// phone shows the same layout regardless of screen size.
class ChitSpot {
  const ChitSpot(this.x, this.y, this.angle);
  final double x;
  final double y;
  final double angle;
}

int _seedOf(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// A jittered grid, shuffled by a seed shared by every device in the room.
Map<String, ChitSpot> chitLayout(String seed, List<String> ids, double aspect) {
  final n = ids.length;
  if (n == 0) return const {};
  final cols = max(1, (sqrt(n * aspect)).ceil());
  final rows = (n / cols).ceil();
  final r = Random(_seedOf(seed));
  final cells = List.generate(cols * rows, (i) => i)..shuffle(r);
  final out = <String, ChitSpot>{};
  for (var i = 0; i < n; i++) {
    final cell = cells[i];
    final c = cell % cols;
    final row = cell ~/ cols;
    final jx = (r.nextDouble() - 0.5) * 0.45 / cols;
    final jy = (r.nextDouble() - 0.5) * 0.4 / rows;
    out[ids[i]] = ChitSpot(
      (c + 0.5) / cols + jx,
      (row + 0.5) / rows + jy,
      (r.nextDouble() - 0.5) * 1.1,
    );
  }
  return out;
}

/// A small folded paper chit: cream paper, a folded-over flap, a crease and
/// a hint of ink showing through (never readable).
class FoldedChit extends StatelessWidget {
  const FoldedChit({
    super.key,
    required this.width,
    this.lifted = false,
    this.glow,
    this.seed = 0,
  });

  final double width;
  final bool lifted;
  final Color? glow;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedScale(
      scale: lifted ? 1.18 : 1,
      duration: Motion.of(context, Motion.fast),
      curve: Curves.easeOutBack,
      child: SizedBox(
        width: width,
        height: width * 0.72,
        child: CustomPaint(
          painter: _FoldedChitPainter(
            paper: c.paper,
            edge: c.paperEdge,
            ink: c.ink,
            glow: glow,
            lifted: lifted,
            seed: seed,
          ),
        ),
      ),
    );
  }
}

class _FoldedChitPainter extends CustomPainter {
  _FoldedChitPainter({
    required this.paper,
    required this.edge,
    required this.ink,
    required this.glow,
    required this.lifted,
    required this.seed,
  });

  final Color paper;
  final Color edge;
  final Color ink;
  final Color? glow;
  final bool lifted;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(w * 0.08),
    );
    // Shadow.
    canvas.drawRRect(
      rect.shift(Offset(0, lifted ? 7 : 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: lifted ? 0.35 : 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lifted ? 9 : 4),
    );
    if (glow != null) {
      canvas.drawRRect(
        rect.inflate(3),
        Paint()
          ..color = glow!.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    // Paper body with a gentle gradient.
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [paper, Color.lerp(paper, edge, 0.55)!],
        ).createShader(Offset.zero & size),
    );
    // Ink bleeding through: a few soft strokes, deliberately unreadable.
    final r = Random(seed);
    final inkPaint = Paint()
      ..color = ink.withValues(alpha: 0.07)
      ..strokeWidth = h * 0.07
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.05);
    for (var i = 0; i < 3; i++) {
      final y = h * (0.36 + i * 0.16);
      final x0 = w * (0.18 + r.nextDouble() * 0.1);
      final x1 = w * (0.62 + r.nextDouble() * 0.2);
      canvas.drawLine(Offset(x0, y), Offset(x1, y), inkPaint);
    }
    // Horizontal crease with a highlight and shadow.
    final creaseY = h * 0.5;
    canvas.drawLine(
      Offset(w * 0.04, creaseY),
      Offset(w * 0.96, creaseY),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..strokeWidth = 1.4,
    );
    canvas.drawLine(
      Offset(w * 0.04, creaseY + 1.4),
      Offset(w * 0.96, creaseY + 1.4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    // Folded-over corner flap.
    final flap = Path()
      ..moveTo(w * 0.62, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.42)
      ..close();
    canvas.drawPath(
      flap,
      Paint()..color = Color.lerp(edge, Colors.black, 0.06)!,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.62, 0)
        ..lineTo(w, h * 0.42),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_FoldedChitPainter old) =>
      old.lifted != lifted || old.glow != glow || old.paper != paper;
}

/// A slip that folds in half along its middle. [progress] 0 = folded shut
/// (the top half lies over the bottom half, showing the back of the paper),
/// 1 = fully open showing [child].
class FoldPaper extends StatelessWidget {
  const FoldPaper({
    super.key,
    required this.progress,
    required this.width,
    required this.height,
    required this.child,
  });

  final double progress;
  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final angle = pi * (1 - progress.clamp(0.0, 1.0));
    final half = height / 2;
    Widget halfOf(Alignment align) => ClipRect(
      child: OverflowBox(
        alignment: align,
        minHeight: height,
        maxHeight: height,
        minWidth: width,
        maxWidth: width,
        child: child,
      ),
    );
    final back = Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.paperEdge, Color.lerp(c.paperEdge, c.paper, 0.6)!],
        ),
        border: Border.all(color: c.paperEdge),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: half,
            left: 0,
            width: width,
            height: half,
            child: halfOf(Alignment.bottomCenter),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: width,
            height: half,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016)
                ..rotateX(-angle),
              child: angle > pi / 2
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateX(pi),
                      child: back,
                    )
                  : halfOf(Alignment.topCenter),
            ),
          ),
          // Shading on the crease while partly folded.
          if (progress < 1)
            Positioned(
              top: half - 2,
              left: 4,
              right: 4,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12 * (1 - progress)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The suspenseful reveal: a folded chit wobbles, then unfolds to show
/// [child]. Calls [onOpened] at the moment it opens and [onDone] after a
/// short pause.
class UnfoldReveal extends StatefulWidget {
  const UnfoldReveal({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.onOpenStart,
    this.onOpened,
    this.onDone,
    this.caption,
  });

  final double width;
  final double height;
  final Widget child;
  final VoidCallback? onOpenStart;
  final VoidCallback? onOpened;
  final VoidCallback? onDone;
  final String? caption;

  @override
  State<UnfoldReveal> createState() => _UnfoldRevealState();
}

class _UnfoldRevealState extends State<UnfoldReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool _openStarted = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_openStarted && _c.value >= 0.38) {
        _openStarted = true;
        widget.onOpenStart?.call();
      }
      if (!_opened && _c.value >= 0.78) {
        _opened = true;
        widget.onOpened?.call();
      }
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) widget.onDone?.call();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
        widget.onOpenStart?.call();
        widget.onOpened?.call();
        Future<void>.delayed(const Duration(milliseconds: 900), () {
          if (mounted) widget.onDone?.call();
        });
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 0–0.38: arrive and wobble with suspense; 0.38–0.78: unfold.
        final arrive = Curves.easeOutBack.transform((t / 0.2).clamp(0, 1));
        final wobble = t < 0.38 ? sin(t * 70) * 0.06 * (1 - t / 0.38) : 0.0;
        final open = Curves.easeInOutCubic.transform(
          ((t - 0.38) / 0.4).clamp(0, 1),
        );
        final settle = t > 0.78
            ? Curves.easeOut.transform((t - 0.78) / 0.22)
            : 0.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.caption != null)
              Opacity(
                opacity: arrive.clamp(0, 1),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  child: Text(
                    widget.caption!,
                    style: context.text.titleMedium?.copyWith(
                      color: context.colors.muted,
                    ),
                  ),
                ),
              ),
            Transform.scale(
              scale: (0.5 + 0.5 * arrive) * (1 + 0.04 * settle),
              child: Transform.rotate(
                angle: wobble,
                child: FoldPaper(
                  progress: open,
                  width: widget.width,
                  height: widget.height,
                  child: widget.child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A character written on a paper slip, used for reveals.
class CharacterSlip extends StatelessWidget {
  const CharacterSlip({
    super.key,
    required this.name,
    required this.points,
    required this.icon,
    required this.width,
  });

  final String name;
  final int points;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      height: width * 1.42,
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.marigold, width: 3),
        boxShadow: [
          BoxShadow(color: c.marigold.withValues(alpha: 0.4), blurRadius: 18),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: width * 0.34, color: c.kumkum),
          const SizedBox(height: 6),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.ink,
              fontWeight: FontWeight.w900,
              fontSize: width * 0.16,
            ),
          ),
          Text(
            '+$points',
            style: TextStyle(
              color: c.leaf,
              fontWeight: FontWeight.w900,
              fontSize: width * 0.12,
            ),
          ),
        ],
      ),
    );
  }
}

/// The table of folded chits, with the creation ceremony and live picks.
///
/// Ceremony (client-side, timed to finish when picking opens on the server):
/// names are written on slips, the slips fold, every chit collapses into a
/// single spinning pile (so no chit can be tracked), then they scatter.
class ChitTable extends StatefulWidget {
  const ChitTable({
    super.key,
    required this.seed,
    required this.ids,
    required this.picks,
    required this.myUid,
    required this.players,
    required this.pending,
    required this.canPick,
    required this.onPick,
    required this.ceremonyLabels,
    required this.opensAt,
    required this.now,
    this.counts = const {},
    this.capacity = 4,
    this.onCeremonyCue,
  });

  final String seed;
  final List<String> ids;
  final Map<String, String> picks;
  final String? myUid;

  /// Players shown along the top (uid -> name), who chits fly to.
  final Map<String, String> players;
  final Set<String> pending;
  final bool canPick;
  final ValueChanged<String> onPick;
  final List<String> ceremonyLabels;
  final DateTime? opensAt;
  final DateTime Function() now;
  final Map<String, int> counts;
  final int capacity;

  /// 'write' | 'fold' | 'shuffle' | 'scatter' — for sounds and haptics.
  final ValueChanged<String>? onCeremonyCue;

  @override
  State<ChitTable> createState() => _ChitTableState();
}

class _ChitTableState extends State<ChitTable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ceremony = AnimationController(vsync: this);
  final _cued = <String>{};

  @override
  void initState() {
    super.initState();
    _ceremony.addListener(_cue);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRunCeremony());
  }

  void _maybeRunCeremony() {
    if (!mounted) return;
    final opens = widget.opensAt;
    final left = opens == null ? Duration.zero : opens.difference(widget.now());
    if (MediaQuery.of(context).disableAnimations ||
        left < const Duration(milliseconds: 1200) ||
        widget.picks.isNotEmpty) {
      _ceremony.value = 1;
      return;
    }
    final ms = min(left.inMilliseconds, 4200);
    _ceremony.duration = Duration(milliseconds: ms);
    _ceremony.forward(from: 0);
  }

  void _cue() {
    final t = _ceremony.value;
    void once(String k, double at) {
      if (t >= at && _cued.add(k)) widget.onCeremonyCue?.call(k);
    }

    once('write', 0.0);
    once('fold', 0.3);
    once('shuffle', 0.5);
    once('scatter', 0.74);
  }

  @override
  void dispose() {
    _ceremony.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        const stripH = 64.0;
        final matTop = stripH;
        final matH = max(80.0, h - stripH);
        final spots = chitLayout(widget.seed, widget.ids, w / matH);
        final cols = max(1, sqrt(widget.ids.length * w / matH).ceil());
        final chitW = (w / cols * 0.7).clamp(40.0, 84.0);
        final chitH = chitW * 0.72;
        final players = widget.players.entries.toList();
        Offset avatarAt(String uid) {
          final i = players.indexWhere((e) => e.key == uid);
          final n = max(1, players.length);
          return Offset((i + 0.5) / n * w, stripH / 2);
        }

        return AnimatedBuilder(
          animation: _ceremony,
          builder: (context, _) {
            final t = _ceremony.value;
            final ceremonyDone = t >= 1;
            final center = Offset(w / 2, matTop + matH / 2);
            final chitWidgets = <Widget>[];
            for (var i = 0; i < widget.ids.length; i++) {
              final id = widget.ids[i];
              final spot = spots[id]!;
              final home = Offset(spot.x * w, matTop + spot.y * matH);
              final owner = widget.picks[id];
              Offset pos;
              double angle;
              double opacity = 1;
              double scale = 1;
              if (!ceremonyDone) {
                if (t < 0.45) continue; // slips are still being written/folded
                final r = Random(i * 7919);
                if (t < 0.74) {
                  // Collapse into one pile and shuffle around its centre.
                  final gather = Curves.easeIn.transform(
                    ((t - 0.45) / 0.08).clamp(0, 1),
                  );
                  final phase = r.nextDouble() * pi * 2;
                  final s = (t - 0.5) * 60;
                  final jiggle = Offset(
                    sin(s + phase) * 16,
                    cos(s * 0.8 + phase) * 10,
                  );
                  pos = Offset.lerp(center, center + jiggle, gather)!;
                  angle = sin(s * 0.5 + phase) * 0.9;
                  opacity = gather.clamp(0.0, 1.0);
                } else {
                  final k = Curves.easeOutBack.transform(
                    ((t - 0.74) / 0.26).clamp(0, 1),
                  );
                  pos = Offset.lerp(center, home, k)!;
                  angle = spot.angle * k + (1 - k) * 2.5;
                }
              } else if (owner != null) {
                pos = owner == widget.myUid
                    ? Offset(w / 2, h + chitH)
                    : avatarAt(owner);
                angle = 0;
                opacity = 0;
                scale = 0.4;
              } else {
                pos = home;
                angle = spot.angle;
              }
              final pending = widget.pending.contains(id);
              final tappable =
                  ceremonyDone && owner == null && widget.canPick && !pending;
              final chit = Transform.rotate(
                angle: angle,
                child: FoldedChit(
                  width: chitW,
                  lifted: pending,
                  glow: pending ? c.marigold : null,
                  seed: i,
                ),
              );
              final positionedChild = Semantics(
                button: tappable,
                label: owner == null ? 'Folded chit' : 'Picked chit',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: tappable ? () => widget.onPick(id) : null,
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: ceremonyDone
                        ? Motion.of(context, Motion.slow)
                        : Duration.zero,
                    child: AnimatedScale(
                      scale: scale,
                      duration: ceremonyDone
                          ? Motion.of(context, Motion.slow)
                          : Duration.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: chit,
                      ),
                    ),
                  ),
                ),
              );
              chitWidgets.add(
                ceremonyDone
                    ? AnimatedPositioned(
                        key: ValueKey(id),
                        duration: Motion.of(context, Motion.slow),
                        curve: Curves.easeInOutCubic,
                        left: pos.dx - chitW / 2 - 6,
                        top: pos.dy - chitH / 2 - 6,
                        child: positionedChild,
                      )
                    : Positioned(
                        key: ValueKey(id),
                        left: pos.dx - chitW / 2 - 6,
                        top: pos.dy - chitH / 2 - 6,
                        child: positionedChild,
                      ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: matTop,
                  height: matH,
                  child: const _WovenMat(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: stripH,
                  child: _PlayerStrip(
                    players: players,
                    counts: widget.counts,
                    capacity: widget.capacity,
                    myUid: widget.myUid,
                  ),
                ),
                if (!ceremonyDone && t < 0.55)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: matTop,
                    height: matH,
                    child: _CeremonySlips(
                      labels: widget.ceremonyLabels,
                      t: t,
                      width: w,
                    ),
                  ),
                ...chitWidgets,
              ],
            );
          },
        );
      },
    );
  }
}

/// Writing and folding the named slips at the start of the ceremony.
class _CeremonySlips extends StatelessWidget {
  const _CeremonySlips({
    required this.labels,
    required this.t,
    required this.width,
  });

  final List<String> labels;
  final double t;
  final double width;

  @override
  Widget build(BuildContext context) {
    final n = max(1, labels.length);
    final perRow = min(n, 5);
    final slipW = min(78.0, (width - 32) / perRow - 10);
    final slipH = slipW * 1.42;
    // 0–0.28 write, 0.28–0.45 fold, 0.45–0.55 shrink into the pile.
    final shrink = ((t - 0.45) / 0.1).clamp(0.0, 1.0);
    return Center(
      child: Opacity(
        opacity: 1 - shrink,
        child: Transform.scale(
          scale: 1 - 0.6 * shrink,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < labels.length; i++)
                Builder(
                  builder: (context) {
                    final start = i / n * 0.18;
                    final write = ((t - start) / 0.1).clamp(0.0, 1.0);
                    final fold =
                        1 - ((t - 0.28 - i * 0.01) / 0.15).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: min(1, write * 2),
                      child: FoldPaper(
                        progress: Curves.easeInOut.transform(fold),
                        width: slipW,
                        height: slipH,
                        child: Opacity(
                          opacity: 0.35 + 0.65 * write,
                          child: PaperSlip(label: labels[i], width: slipW),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerStrip extends StatelessWidget {
  const _PlayerStrip({
    required this.players,
    required this.counts,
    required this.capacity,
    required this.myUid,
  });

  final List<MapEntry<String, String>> players;
  final Map<String, int> counts;
  final int capacity;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (final p in players)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerAvatar(
                  name: p.value,
                  size: 32,
                  ring: (counts[p.key] ?? 0) >= capacity ? c.leaf : null,
                ),
                const SizedBox(height: 2),
                Text(
                  p.key == myUid
                      ? 'You ${counts[p.key] ?? 0}/$capacity'
                      : '${p.value} ${counts[p.key] ?? 0}/$capacity',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: (counts[p.key] ?? 0) >= capacity ? c.leaf : c.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A woven palm-leaf mat (chaapa) the chits are scattered on.
class _WovenMat extends StatelessWidget {
  const _WovenMat();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: RadialGradient(
          colors: [Color.lerp(c.surfaceHigh, c.marigold, 0.12)!, c.surface],
          radius: 1.1,
        ),
        border: Border.all(color: c.marigold.withValues(alpha: 0.35), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: CustomPaint(painter: _WeavePainter(c.marigold)),
      ),
    );
  }
}

class _WeavePainter extends CustomPainter {
  _WeavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..strokeWidth = 6;
    for (var x = -size.height; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
    final q = Paint()
      ..color = color.withValues(alpha: 0.035)
      ..strokeWidth = 6;
    for (var x = 0.0; x < size.width + size.height; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), q);
    }
  }

  @override
  bool shouldRepaint(_WeavePainter old) => old.color != color;
}
