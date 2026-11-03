import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A score that counts up (or down) to its new value instead of jumping.
class AnimatedPoints extends StatelessWidget {
  const AnimatedPoints({
    super.key,
    required this.value,
    this.style,
    this.suffix = ' pts',
  });
  final int value;
  final TextStyle? style;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: value, end: value),
      duration: Motion.of(context, const Duration(milliseconds: 900)),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(
        '$v$suffix',
        style: (style ?? context.text.titleMedium)?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A soft, slow glow that breathes around its child while [on] is true.
/// Used to draw the eye to "your turn". Still when animations are off.
class PulseGlow extends StatefulWidget {
  const PulseGlow({
    super.key,
    required this.on,
    required this.color,
    required this.child,
    this.radius = 20,
  });
  final bool on;
  final Color color;
  final Widget child;
  final double radius;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseGlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.of(context).disableAnimations;
    if (widget.on && !still) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = widget.on ? 1 : 0;
    }
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
      child: widget.child,
      builder: (context, child) {
        final t = widget.on ? 0.35 + 0.65 * _c.value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: t == 0
                ? const []
                : [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.25 + 0.3 * t),
                      blurRadius: 14 + 18 * t,
                      spreadRadius: 1 + 3 * t,
                    ),
                  ],
          ),
          child: child,
        );
      },
    );
  }
}

/// A small rounded label, e.g. "LAP 3" or "ROUND 2 OF 7".
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
  });
  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? accent : c.surfaceHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: filled ? 0 : 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? c.ink : accent),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? c.ink : accent,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// A gentle entrance: fades and slides a child up when it first appears.
class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.delayMs = 0});
  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.of(context, Duration(milliseconds: 420 + delayMs)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) {
        final k = delayMs == 0
            ? t
            : max(0.0, (t * (420 + delayMs) - delayMs) / 420);
        return Opacity(
          opacity: k.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - k) * 16),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A number badge (unread messages) in the corner of an icon.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: AnimatedScale(
              scale: 1,
              duration: Motion.of(context, Motion.fast),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: c.kumkum,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: c.surface, width: 1.5),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
