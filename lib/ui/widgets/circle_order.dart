import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'common.dart';

class CircleSeat {
  const CircleSeat({
    required this.uid,
    required this.name,
    this.cards,
    this.online,
    this.isMe = false,
  });
  final String uid;
  final String name;
  final int? cards;
  final bool? online;
  final bool isMe;
}

/// Players around a circle in passing order, with arrows showing direction,
/// the current player ringed by the countdown and the next player tagged.
class CircleOrder extends StatelessWidget {
  const CircleOrder({
    super.key,
    required this.seats,
    this.currentUid,
    this.nextUid,
    this.progress,
    this.size = 260,
  });

  final List<CircleSeat> seats;
  final String? currentUid;
  final String? nextUid;

  /// 0..1 remaining time for the current player, or null when untimed.
  final double? progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = seats.length;
    final avatar = n > 7 ? 38.0 : 46.0;
    final radius = size / 2 - avatar / 2 - 18;
    Offset pos(int i) {
      final a = -pi / 2 + 2 * pi * i / n;
      return Offset(size / 2 + radius * cos(a), size / 2 + radius * sin(a));
    }

    final current = seats.indexWhere((s) => s.uid == currentUid);
    final order = seats.map((s) => s.name).join(', then ');

    return Semantics(
      label: 'Passing order: $order, then back to ${seats.first.name}.'
          '${current >= 0 ? ' Now: ${seats[current].name}.' : ''}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ArrowsPainter(
                  points: List.generate(n, pos),
                  gap: avatar / 2 + 6,
                  color: c.muted.withValues(alpha: 0.45),
                  active: current,
                  activeColor: c.marigold,
                ),
              ),
            ),
            Center(
              child: Icon(Icons.autorenew_rounded,
                  size: size * 0.16, color: c.muted.withValues(alpha: 0.35)),
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: pos(i).dx - avatar / 2 - 14,
                top: pos(i).dy - avatar / 2 - 6,
                width: avatar + 28,
                child: _Seat(
                  seat: seats[i],
                  size: avatar,
                  isCurrent: seats[i].uid == currentUid,
                  isNext: seats[i].uid == nextUid,
                  progress: seats[i].uid == currentUid ? progress : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({
    required this.seat,
    required this.size,
    required this.isCurrent,
    required this.isNext,
    required this.progress,
  });

  final CircleSeat seat;
  final double size;
  final bool isCurrent;
  final bool isNext;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warn = progress != null && progress! < 0.3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            if (isCurrent)
              SizedBox(
                width: size + 10,
                height: size + 10,
                child: CircularProgressIndicator(
                  value: progress ?? 1,
                  strokeWidth: 4,
                  color: warn ? c.kumkum : c.marigold,
                  backgroundColor: c.outline,
                ),
              ),
            PlayerAvatar(
              name: seat.name,
              size: size,
              online: seat.online,
              ring: isNext ? c.teal : null,
            ),
            if (seat.cards != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${seat.cards}',
                      style: TextStyle(
                          color: c.ink, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          seat.isMe ? 'You' : seat.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
            color: isCurrent ? c.marigold : c.onSurface,
          ),
        ),
        if (isNext)
          Text('NEXT',
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w900,
                  color: c.teal)),
      ],
    );
  }
}

class _ArrowsPainter extends CustomPainter {
  _ArrowsPainter({
    required this.points,
    required this.gap,
    required this.color,
    required this.active,
    required this.activeColor,
  });

  final List<Offset> points;
  final double gap;
  final Color color;
  final int active;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n < 2) return;
    final center = size.center(Offset.zero);
    for (var i = 0; i < n; i++) {
      final a = points[i];
      final b = points[(i + 1) % n];
      final isActive = i == active;
      final paint = Paint()
        ..color = isActive ? activeColor : color
        ..strokeWidth = isActive ? 3.5 : 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final dir = (b - a);
      final unit = dir / dir.distance;
      final start = a + unit * gap;
      final end = b - unit * gap;
      if ((end - start).distance < 4) continue;
      // Bow the arrow slightly outward from the centre.
      final mid = (start + end) / 2;
      final out = mid - center;
      final control = mid + out / out.distance * 14;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
      final tangent = (end - control);
      final t = tangent / tangent.distance;
      final normal = Offset(-t.dy, t.dx);
      final head = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - t.dx * 9 + normal.dx * 5, end.dy - t.dy * 9 + normal.dy * 5)
        ..lineTo(end.dx - t.dx * 9 - normal.dx * 5, end.dy - t.dy * 9 - normal.dy * 5)
        ..close();
      canvas.drawPath(head, Paint()..color = paint.color);
    }
  }

  @override
  bool shouldRepaint(_ArrowsPainter old) =>
      old.active != active || old.points.length != points.length || old.color != color;
}

/// A large numeric countdown with a draining ring.
class CountdownBadge extends StatelessWidget {
  const CountdownBadge({
    super.key,
    required this.seconds,
    required this.progress,
    this.size = 64,
  });

  final int seconds;
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warn = seconds <= 5;
    return Semantics(
      label: '$seconds seconds left',
      liveRegion: seconds <= 5,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 6,
                color: warn ? c.kumkum : c.marigold,
                backgroundColor: c.outline,
              ),
            ),
            AnimatedDefaultTextStyle(
              duration: Motion.fast,
              style: TextStyle(
                fontSize: warn ? size * 0.42 : size * 0.36,
                fontWeight: FontWeight.w900,
                color: warn ? c.kumkum : c.onSurface,
              ),
              child: Text('$seconds'),
            ),
          ],
        ),
      ),
    );
  }
}
