import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Lightweight paper-confetti burst. Skipped entirely under reduced motion.
class Confetti extends StatefulWidget {
  const Confetti({
    super.key,
    this.pieces = 70,
    this.duration = const Duration(seconds: 3),
  });
  final int pieces;
  final Duration duration;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final r = Random();
    _pieces = List.generate(widget.pieces, (_) {
      return _Piece(
        x: r.nextDouble(),
        delay: r.nextDouble() * 0.3,
        speed: 0.7 + r.nextDouble() * 0.6,
        drift: (r.nextDouble() - 0.5) * 0.3,
        spin: (r.nextDouble() - 0.5) * 12,
        size: 6 + r.nextDouble() * 8,
        hue: r.nextInt(4),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final colors = [c.marigold, c.kumkum, c.teal, c.paper];
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _c.value, colors),
        ),
      ),
    );
  }
}

class _Piece {
  _Piece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.spin,
    required this.size,
    required this.hue,
  });
  final double x, delay, speed, drift, spin, size;
  final int hue;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t, this.colors);
  final List<_Piece> pieces;
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = (p.x + p.drift * local) * size.width;
      final fade = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        Paint()..color = colors[p.hue].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
