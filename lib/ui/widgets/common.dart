import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Soft gradient backdrop with faint floating paper-slip shapes.
class GameBackground extends StatelessWidget {
  const GameBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.bgTop, c.bgBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _SlipsPainter(c.onSurface)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SlipsPainter extends CustomPainter {
  _SlipsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final p = Paint()..color = color.withValues(alpha: 0.035);
    for (var i = 0; i < 14; i++) {
      canvas.save();
      canvas.translate(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.rotate((rnd.nextDouble() - 0.5) * 0.9);
      final w = 30 + rnd.nextDouble() * 40;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, w * 1.4), const Radius.circular(6)),
          p);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SlipsPainter old) => old.color != color;
}

/// Big tactile primary action.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !busy;
    final bg = secondary ? c.surfaceHigh : c.marigold;
    final fg = secondary ? c.onSurface : c.ink;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: Motion.fast,
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          elevation: secondary ? 0 : 4,
          shadowColor: c.marigold.withValues(alpha: 0.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled ? onPressed : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
                      )
                    else if (icon != null)
                      Icon(icon, color: fg),
                    if (busy || icon != null) const SizedBox(width: 10),
                    Flexible(
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: context.text.titleMedium?.copyWith(
                              color: fg, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular initial avatar with a stable colour per name.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.ring,
    this.online,
    this.dimmed = false,
  });

  final String name;
  final double size;
  final Color? ring;
  final bool? online;
  final bool dimmed;

  static const _hues = [
    Color(0xFFFF8A5B), Color(0xFF4CC9F0), Color(0xFFB794F4), Color(0xFF58D68D),
    Color(0xFFFFC75F), Color(0xFFF15BB5), Color(0xFF00BBF9), Color(0xFF9BDE7E),
    Color(0xFFFF6F91), Color(0xFF845EC2),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hue = _hues[name.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [hue, Color.lerp(hue, Colors.black, 0.25)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: ring ?? Colors.transparent, width: 3),
              ),
              alignment: Alignment.center,
              child: Text(initial,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: size * 0.42)),
            ),
            if (online != null)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: size * 0.3,
                  height: size * 0.3,
                  decoration: BoxDecoration(
                    color: online! ? c.leaf : c.muted,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounded translucent panel used throughout.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // A Material (not a DecoratedBox) so ListTiles inside show ink splashes.
    return Material(
      color: color ?? c.surface.withValues(alpha: 0.85),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: c.outline),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(Space.lg),
        child: child,
      ),
    );
  }
}

/// Thin banner shown whenever the device is offline / reconnecting.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      child: connected
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: c.kumkum,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                    SizedBox(width: 8),
                    Text('Reconnecting… your seat is saved',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
    );
  }
}

void showGameSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
