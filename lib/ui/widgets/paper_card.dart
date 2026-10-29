import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum SlipState { normal, selected, incoming, matching, winning, faceDown }

/// A folded paper slip ("chitti"): cream paper with a folded corner, faint
/// ruled lines, and the name written in ink.
class PaperSlip extends StatelessWidget {
  const PaperSlip({
    super.key,
    required this.label,
    this.state = SlipState.normal,
    this.width = 92,
    this.onTap,
    this.semanticsHint,
  });

  final String label;
  final SlipState state;
  final double width;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = width * 1.42;
    final lifted = state == SlipState.selected;
    final glow = switch (state) {
      SlipState.selected => c.marigold,
      SlipState.incoming => c.teal,
      SlipState.matching => c.leaf,
      SlipState.winning => c.marigold,
      _ => null,
    };
    final duration = Motion.of(context, Motion.fast);

    return Semantics(
      button: onTap != null,
      selected: lifted,
      label: state == SlipState.faceDown ? 'Folded slip' : 'Slip: $label',
      hint: semanticsHint,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          curve: Motion.curve,
          width: width,
          height: height,
          transform: Matrix4.translationValues(0, lifted ? -18 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: lifted ? 18 : 8,
                offset: Offset(0, lifted ? 10 : 4),
              ),
              if (glow != null)
                BoxShadow(
                  color: glow.withValues(alpha: 0.55),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: CustomPaint(
            painter: _SlipPainter(
              paper: state == SlipState.faceDown ? c.paperEdge : c.paper,
              edge: c.paperEdge,
              line: c.ink.withValues(alpha: 0.06),
              border: glow ?? c.paperEdge,
              borderWidth: glow != null ? 3 : 1,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  width * 0.1, width * 0.2, width * 0.1, width * 0.1),
              child: state == SlipState.faceDown
                  ? Center(
                      child: Text('చిట్టి',
                          style: TextStyle(
                              color: c.ink.withValues(alpha: 0.35),
                              fontWeight: FontWeight.w800,
                              fontSize: width * 0.18)))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.ink,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                fontSize: width *
                                    (label.length > 18
                                        ? 0.13
                                        : label.length > 10
                                            ? 0.155
                                            : 0.19),
                              ),
                            ),
                          ),
                        ),
                        if (state == SlipState.incoming)
                          _Tag(text: 'NEW', color: c.teal),
                        if (state == SlipState.matching ||
                            state == SlipState.winning)
                          _Tag(text: '★', color: c.leaf),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1)),
      );
}

class _SlipPainter extends CustomPainter {
  _SlipPainter({
    required this.paper,
    required this.edge,
    required this.line,
    required this.border,
    required this.borderWidth,
  });

  final Color paper;
  final Color edge;
  final Color line;
  final Color border;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final fold = size.width * 0.22;
    const r = 14.0;
    final body = Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - fold, 0)
      ..lineTo(size.width, fold)
      ..lineTo(size.width, size.height - r)
      ..quadraticBezierTo(size.width, size.height, size.width - r, size.height)
      ..lineTo(r, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    canvas.drawPath(body, Paint()..color = paper);

    canvas.save();
    canvas.clipPath(body);
    final lp = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var y = size.height * 0.18; y < size.height; y += size.height / 9) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), lp);
    }
    canvas.restore();

    final flap = Path()
      ..moveTo(size.width - fold, 0)
      ..lineTo(size.width - fold, fold * 0.8)
      ..quadraticBezierTo(size.width - fold, fold, size.width - fold * 0.8, fold)
      ..lineTo(size.width, fold)
      ..close();
    canvas.drawPath(flap, Paint()..color = edge);
    canvas.drawPath(
        flap,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke);

    canvas.drawPath(
        body,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth);
  }

  @override
  bool shouldRepaint(_SlipPainter old) =>
      old.paper != paper ||
      old.border != border ||
      old.borderWidth != borderWidth;
}
