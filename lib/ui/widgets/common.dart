import 'dart:math';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';

/// Widest the content gets: on tablets and foldables screens stay a
/// comfortable phone-like column in the middle instead of stretching.
const kMaxContentWidth = 620.0;

/// Night-sky backdrop: a deep gradient, two soft coloured glows, faint
/// floating paper slips and a vignette. Content is centred and width-capped.
class GameBackground extends StatelessWidget {
  const GameBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.8, -1.0),
                    radius: 1.1,
                    colors: [
                      c.glow.withValues(alpha: dark ? 0.22 : 0.25),
                      c.glow.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.0, 0.9),
                    radius: 1.0,
                    colors: [
                      c.marigold.withValues(alpha: dark ? 0.13 : 0.18),
                      c.marigold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SlipsPainter(c.onSurface, c.goldHi, dark),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SlipsPainter extends CustomPainter {
  _SlipsPainter(this.color, this.spark, this.dark);
  final Color color;
  final Color spark;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final p = Paint()..color = color.withValues(alpha: 0.035);
    for (var i = 0; i < 14; i++) {
      canvas.save();
      canvas.translate(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      canvas.rotate((rnd.nextDouble() - 0.5) * 0.9);
      final w = 30 + rnd.nextDouble() * 40;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, w * 1.4),
          const Radius.circular(6),
        ),
        p,
      );
      canvas.restore();
    }
    // Tiny stars, only at night.
    if (dark) {
      final star = Paint();
      for (var i = 0; i < 40; i++) {
        final o = Offset(
          rnd.nextDouble() * size.width,
          rnd.nextDouble() * size.height * 0.7,
        );
        star.color = spark.withValues(alpha: 0.10 + rnd.nextDouble() * 0.25);
        canvas.drawCircle(o, 0.6 + rnd.nextDouble() * 1.1, star);
      }
    }
  }

  @override
  bool shouldRepaint(_SlipsPainter old) =>
      old.color != color || old.spark != spark || old.dark != dark;
}

/// Adds the game's click and a light haptic to a tap handler. Keeps `null`
/// (a disabled control) as `null`.
VoidCallback? withClick(
  BuildContext context,
  VoidCallback? onTap, {
  Sfx sound = Sfx.tap,
}) {
  if (onTap == null) return null;
  return () {
    onTap();
    Services.read(context).feedback.ui(sound);
  };
}

/// [withClick] for callbacks that take a value (switches, chips, sliders).
ValueChanged<T>? withClickValue<T>(
  BuildContext context,
  ValueChanged<T>? onChanged, {
  Sfx sound = Sfx.toggle,
}) {
  if (onChanged == null) return null;
  return (v) {
    // After the change, so turning sound or vibration on confirms itself.
    onChanged(v);
    Services.read(context).feedback.ui(sound);
  };
}

/// Big, chunky 3D game button: a gold (or dark) face on a darker edge that
/// sinks in when pressed, with a click and a haptic. Tapping it while it is
/// disabled gives a soft "not yet" buzz instead of silence.
class BigButton extends StatefulWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.busy = false,
    this.sound = Sfx.button,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool busy;
  final Sfx sound;

  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;
  static const _depth = 5.0;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  void _tap() {
    final fx = Services.read(context).feedback;
    if (widget.busy) return;
    if (widget.onPressed == null) {
      fx.play(Sfx.error);
      fx.light();
      return;
    }
    fx.play(widget.sound);
    fx.ui(widget.sound, haptic: false); // marks the click for de-duplication
    fx.light();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.busy;
    final secondary = widget.secondary;
    final fg = secondary ? c.onSurface : c.ink;
    final face = secondary
        ? [Color.lerp(c.surfaceHigh, Colors.white, 0.06)!, c.surfaceHigh]
        : [c.goldHi, c.goldLo];
    final lip = secondary ? c.lip : c.goldLip;
    final pressed = _down && enabled;
    final dur = Motion.of(context, const Duration(milliseconds: 70));
    const radius = BorderRadius.all(Radius.circular(18));
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: _tap,
        child: AnimatedOpacity(
          duration: Motion.fast,
          opacity: enabled ? 1 : 0.55,
          child: AnimatedScale(
            duration: dur,
            scale: pressed ? 0.98 : 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 58 + _depth),
              decoration: BoxDecoration(
                color: lip,
                borderRadius: radius,
                boxShadow: [
                  if (!secondary && enabled)
                    BoxShadow(
                      color: c.marigold.withValues(alpha: pressed ? 0.2 : 0.4),
                      blurRadius: pressed ? 8 : 18,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              child: AnimatedPadding(
                duration: dur,
                padding: EdgeInsets.only(
                  top: pressed ? _depth - 1 : 0,
                  bottom: pressed ? 1 : _depth,
                ),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 58),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: face,
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(
                          alpha: secondary ? 0.12 : 0.55,
                        ),
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.busy)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: fg,
                          ),
                        )
                      else if (widget.icon != null)
                        Icon(widget.icon, color: fg),
                      if (widget.busy || widget.icon != null)
                        const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: context.text.titleMedium?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            shadows: secondary
                                ? null
                                : [
                                    Shadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.45,
                                      ),
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Big title text painted with the gold gradient, like a game logo.
class GoldText extends StatelessWidget {
  const GoldText(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.goldHi, c.goldLo],
      ).createShader(r),
      child: Text(
        text,
        textAlign: textAlign,
        style: (style ?? context.text.displaySmall)?.copyWith(
          shadows: [
            Shadow(
              color: c.goldLip.withValues(alpha: 0.6),
              offset: const Offset(0, 3),
              blurRadius: 0,
            ),
          ],
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
    Color(0xFFFF8A5B),
    Color(0xFF4CC9F0),
    Color(0xFFB794F4),
    Color(0xFF58D68D),
    Color(0xFFFFC75F),
    Color(0xFFF15BB5),
    Color(0xFF00BBF9),
    Color(0xFF9BDE7E),
    Color(0xFFFF6F91),
    Color(0xFF845EC2),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hue =
        _hues[name.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
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
              child: Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.42,
                ),
              ),
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

/// Rounded glassy panel used throughout: a soft vertical gradient with a
/// light top edge, so cards read as raised above the night background.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = color ?? c.surface;
    const radius = BorderRadius.all(Radius.circular(24));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: color != null
              ? [base, base]
              : [
                  Color.lerp(
                    base,
                    c.surfaceHigh,
                    0.55,
                  )!.withValues(alpha: 0.92),
                  base.withValues(alpha: 0.86),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      // A Material (not just a box) so ListTiles inside show ink splashes.
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: c.outline),
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(Space.lg),
          child: child,
        ),
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
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 12,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Reconnecting… your seat is saved',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
