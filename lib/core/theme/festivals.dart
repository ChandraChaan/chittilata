import 'package:flutter/material.dart';

/// Festival looks: colours, background decorations and a greeting.
enum Festival {
  sankranti('Sankranti', '🪁', 'Happy Sankranti! 🪁 Kites are up'),
  ugadi('Ugadi', '🥭', 'Ugadi Subhakankshalu! 🥭 Happy new year'),
  diwali('Diwali', '🪔', 'Happy Diwali! 🪔 Light up the table');

  const Festival(this.label, this.emoji, this.greeting);
  final String label;
  final String emoji;
  final String greeting;

  /// The days the theme switches on by itself (a few days around the
  /// festival). Sankranti is fixed; Ugadi and Diwali follow the lunar
  /// calendar, so their dates are listed per year (as yyyymmdd).
  static const _windows = <Festival, List<(int, int)>>{
    Festival.ugadi: [
      (20260316, 20260322),
      (20270404, 20270410),
      (20280324, 20280330),
    ],
    Festival.diwali: [
      (20261103, 20261112),
      (20271025, 20271102),
      (20281013, 20281021),
    ],
  };

  /// The festival on [now], if any.
  static Festival? on(DateTime now) {
    final day = now.year * 10000 + now.month * 100 + now.day;
    if (now.month == 1 && now.day >= 10 && now.day <= 17) {
      return Festival.sankranti;
    }
    for (final e in _windows.entries) {
      for (final (from, to) in e.value) {
        if (day >= from && day <= to) return e.key;
      }
    }
    return null;
  }

  /// [pref] is 'auto' (festivals as they come), 'off', or a festival name.
  static Festival? chosen(String pref, DateTime now) => switch (pref) {
    'off' => null,
    'auto' => on(now),
    _ => Festival.values.where((f) => f.name == pref).firstOrNull,
  };
}

/// The festival currently decorating the app (null: none).
@immutable
class FestivalTheme extends ThemeExtension<FestivalTheme> {
  const FestivalTheme(this.festival);
  final Festival? festival;

  @override
  FestivalTheme copyWith({Festival? festival}) =>
      FestivalTheme(festival ?? this.festival);

  @override
  FestivalTheme lerp(ThemeExtension<FestivalTheme>? other, double t) =>
      other is FestivalTheme && t > 0.5 ? other : this;
}

/// Paints the festival's decorations behind the screen content.
class FestivalPainter extends CustomPainter {
  FestivalPainter(this.festival, {required this.dark});
  final Festival festival;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    switch (festival) {
      case Festival.sankranti:
        _kites(canvas, size);
      case Festival.ugadi:
        _toranam(canvas, size);
      case Festival.diwali:
        _diyas(canvas, size);
    }
  }

  void _kites(Canvas canvas, Size size) {
    const colors = [
      Color(0xFFFF4D6D),
      Color(0xFFFFB627),
      Color(0xFF3CC9C0),
      Color(0xFF9B5DE5),
      Color(0xFF58D68D),
    ];
    final spots = [
      (0.12, 0.10, 0.25),
      (0.82, 0.07, -0.2),
      (0.68, 0.28, 0.15),
      (0.20, 0.46, -0.1),
      (0.90, 0.58, 0.3),
    ];
    for (var i = 0; i < spots.length; i++) {
      final (x, y, tilt) = spots[i];
      final s = size.shortestSide * (0.07 + (i % 3) * 0.015);
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.rotate(tilt);
      final kite = Path()
        ..moveTo(0, -s)
        ..lineTo(s * 0.75, 0)
        ..lineTo(0, s * 1.1)
        ..lineTo(-s * 0.75, 0)
        ..close();
      canvas.drawPath(
        kite,
        Paint()..color = colors[i].withValues(alpha: dark ? 0.32 : 0.4),
      );
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, -s), Offset(0, s * 1.1), line);
      canvas.drawLine(Offset(-s * 0.75, 0), Offset(s * 0.75, 0), line);
      // A wavy tail and string drifting down.
      final tail = Path()..moveTo(0, s * 1.1);
      for (var k = 1; k <= 4; k++) {
        tail.quadraticBezierTo(
          (k.isOdd ? 1 : -1) * s * 0.3,
          s * (1.1 + k * 0.35 - 0.17),
          0,
          s * (1.1 + k * 0.35),
        );
      }
      canvas.drawPath(tail, line..color = colors[i].withValues(alpha: 0.35));
      canvas.restore();
    }
  }

  void _toranam(Canvas canvas, Size size) {
    // Mango-leaf garland along the top, with marigold flowers between.
    final leaf = Paint()
      ..color = const Color(0xFF2E9E4F).withValues(alpha: 0.7);
    final vein = Paint()
      ..color = const Color(0xFFB8F5A0).withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final flower = Paint()
      ..color = const Color(0xFFFF9F1C).withValues(alpha: 0.85);
    final string = Paint()
      ..color = const Color(0xFFFFD86B).withValues(alpha: 0.5)
      ..strokeWidth = 2;
    final n = (size.width / 34).ceil();
    canvas.drawLine(const Offset(0, 6), Offset(size.width, 6), string);
    for (var i = 0; i <= n; i++) {
      final x = i * size.width / n;
      if (i.isEven) {
        final h = 34.0 + (i % 4) * 6;
        final p = Path()
          ..moveTo(x, 6)
          ..quadraticBezierTo(x + 11, 6 + h * 0.45, x, 6 + h)
          ..quadraticBezierTo(x - 11, 6 + h * 0.45, x, 6)
          ..close();
        canvas.drawPath(p, leaf);
        canvas.drawLine(Offset(x, 8), Offset(x, 4 + h), vein);
      } else {
        canvas.drawCircle(Offset(x, 16), 7, flower);
        canvas.drawCircle(
          Offset(x, 16),
          3,
          Paint()..color = const Color(0xFFE85D04).withValues(alpha: 0.9),
        );
      }
    }
  }

  void _diyas(Canvas canvas, Size size) {
    final spots = [
      (0.10, 0.92),
      (0.30, 0.95),
      (0.50, 0.93),
      (0.70, 0.95),
      (0.90, 0.92),
      (0.92, 0.25),
      (0.08, 0.25),
    ];
    for (final (x, y) in spots) {
      final c = Offset(size.width * x, size.height * y);
      final s = size.shortestSide * 0.045;
      // Warm glow.
      canvas.drawCircle(
        c.translate(0, -s * 0.9),
        s * 2.4,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFB627).withValues(alpha: dark ? 0.35 : 0.25),
              const Color(0x00FFB627),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: s * 2.4)),
      );
      // Clay lamp.
      final lamp = Path()
        ..moveTo(c.dx - s, c.dy - s * 0.3)
        ..quadraticBezierTo(c.dx, c.dy + s * 0.9, c.dx + s, c.dy - s * 0.3)
        ..close();
      canvas.drawPath(
        lamp,
        Paint()..color = const Color(0xFFB5541E).withValues(alpha: 0.85),
      );
      // Flame.
      final flame = Path()
        ..moveTo(c.dx, c.dy - s * 1.5)
        ..quadraticBezierTo(
          c.dx + s * 0.35,
          c.dy - s * 0.7,
          c.dx,
          c.dy - s * 0.35,
        )
        ..quadraticBezierTo(
          c.dx - s * 0.35,
          c.dy - s * 0.7,
          c.dx,
          c.dy - s * 1.5,
        )
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFFD86B));
    }
  }

  @override
  bool shouldRepaint(FestivalPainter old) =>
      old.festival != festival || old.dark != dark;
}

/// Colour changes for each festival, applied over the normal palette.
({Color bgTop, Color bgBottom, Color glow}) festivalColors(
  Festival f,
  Brightness b,
) {
  final dark = b == Brightness.dark;
  return switch (f) {
    Festival.sankranti => (
      bgTop: dark ? const Color(0xFF123F75) : const Color(0xFFDFF1FF),
      bgBottom: dark ? const Color(0xFF07152E) : const Color(0xFFFFE9C7),
      glow: const Color(0xFFFF7A00),
    ),
    Festival.ugadi => (
      bgTop: dark ? const Color(0xFF145A37) : const Color(0xFFE8F8DC),
      bgBottom: dark ? const Color(0xFF051D10) : const Color(0xFFFFF1C2),
      glow: const Color(0xFFFFC300),
    ),
    Festival.diwali => (
      bgTop: dark ? const Color(0xFF4A0F36) : const Color(0xFFFFE6D5),
      bgBottom: dark ? const Color(0xFF14030F) : const Color(0xFFFFD9A8),
      glow: const Color(0xFFFF8C1A),
    ),
  };
}
