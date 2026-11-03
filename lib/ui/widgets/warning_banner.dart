import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../game/room_controller.dart';
import 'circle_order.dart';

/// The host asked "are you still there?". For the warned player: a loud
/// card with a countdown and an "I'm here!" button (any move counts too).
/// For everyone else: a slim line saying who has how long to respond.
class WarningBanner extends StatelessWidget {
  const WarningBanner({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final room = ctrl.room;
    if (room == null) return const SizedBox.shrink();
    if (ctrl.iAmWarned) return _MeWarned(ctrl: ctrl);
    final warned = room.memberUids.where(ctrl.warningOpen).toList();
    if (warned.isEmpty) return const SizedBox.shrink();
    return _OthersWarned(ctrl: ctrl, uids: warned);
  }
}

class _MeWarned extends StatefulWidget {
  const _MeWarned({required this.ctrl});
  final RoomController ctrl;

  @override
  State<_MeWarned> createState() => _MeWarnedState();
}

class _MeWarnedState extends State<_MeWarned>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _shake.stop();
    } else if (!_shake.isAnimating) {
      _shake.repeat();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctrl = widget.ctrl;
    final left = ctrl.warningSecondsLeft(ctrl.uid!);
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        final dx = t < 0.3 ? sin(t / 0.3 * pi * 6) * 4 : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(
            Space.md,
            Space.xs,
            Space.md,
            Space.sm,
          ),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.kumkum, Color.lerp(c.kumkum, Colors.black, 0.25)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: c.kumkum.withValues(alpha: 0.5), blurRadius: 22),
            ],
          ),
          child: Row(
            children: [
              CountdownBadge(
                seconds: left,
                progress: (left / 60).clamp(0.0, 1.0),
                size: 52,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Are you still there?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'The host is waiting. Respond within ${left}s or '
                      "you'll be removed.",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: c.kumkum,
                ),
                onPressed: ctrl.busy ? null : ctrl.respondToWarning,
                child: const Text(
                  "I'm here!",
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OthersWarned extends StatelessWidget {
  const _OthersWarned({required this.ctrl, required this.uids});
  final RoomController ctrl;
  final List<String> uids;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final first = uids.first;
    final name = room.nameOf(first);
    final who = uids.length == 1 ? name : '$name and ${uids.length - 1} more';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, 0),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.kumkum.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              '$who ${uids.length == 1 ? 'has' : 'have'} '
              '${ctrl.warningSecondsLeft(first)}s to respond',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
