import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/chat.dart';
import '../../game/room_controller.dart';
import 'common.dart';

/// A slim bar of one-tap emojis, plus a button for preset phrases.
class QuickChatBar extends StatelessWidget {
  const QuickChatBar({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: c.outline)),
      ),
      child: Row(
        children: [
          const SizedBox(width: Space.sm),
          IconButton(
            tooltip: 'Quick chat',
            icon: Icon(Icons.chat_bubble_rounded, color: c.marigold),
            onPressed: () => showQuickChatSheet(context, ctrl),
          ),
          Container(width: 1, height: 28, color: c.outline),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              children: [
                for (final e in quickEmojis)
                  _EmojiButton(
                    item: e,
                    onTap: () => _send(context, ChatKind.emoji, e.code),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _send(BuildContext context, ChatKind kind, String code) {
    if (!ctrl.sendQuick(kind, code)) showGameSnack(context, 'Easy there! 🙂');
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.item, required this.onTap});
  final QuickItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send ${item.text}',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          child: Center(
            child: Text(item.text, style: const TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }
}

/// Preset phrases (Telugu and English) and every emoji.
Future<void> showQuickChatSheet(BuildContext context, RoomController ctrl) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final c = ctx.colors;
      void send(ChatKind kind, String code) {
        if (ctrl.sendQuick(kind, code)) Navigator.pop(ctx);
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Say something', style: ctx.text.titleMedium),
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final p in quickPhrases)
                      ActionChip(
                        label: Text(p.text),
                        onPressed: () => send(ChatKind.phrase, p.code),
                      ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Wrap(
                  children: [
                    for (final e in quickEmojis)
                      _EmojiButton(
                        item: e,
                        onTap: () => send(ChatKind.emoji, e.code),
                      ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'Everyone in the room sees it for a few seconds.',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Emojis and phrases floating up the screen; nudges aimed at me shake big
/// in the middle. Never blocks touches.
class ChatLayer extends StatelessWidget {
  const ChatLayer({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            for (final b in ctrl.chatFeed)
              _FloatingBubble(
                key: ValueKey(b.seq),
                bubble: b,
                mine: b.event.uid == ctrl.uid,
                forMe: b.event.kind == ChatKind.nudge && b.event.to == ctrl.uid,
                targetName: b.event.to == null
                    ? null
                    : (b.event.to == ctrl.uid
                          ? 'you'
                          : ctrl.room?.nameOf(b.event.to!) ?? 'someone'),
                box: box.biggest,
              ),
          ],
        ),
      ),
    );
  }
}

class _FloatingBubble extends StatefulWidget {
  const _FloatingBubble({
    super.key,
    required this.bubble,
    required this.mine,
    required this.forMe,
    required this.targetName,
    required this.box,
  });

  final ChatBubble bubble;
  final bool mine;
  final bool forMe;
  final String? targetName;
  final Size box;

  @override
  State<_FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<_FloatingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = widget.bubble.event;
    final still = MediaQuery.of(context).disableAnimations;
    // Spread bubbles across the width so bursts don't stack on one spot.
    final lane = Random(widget.bubble.seq * 31 + e.uid.hashCode).nextDouble();
    final w = widget.box.width;
    final h = widget.box.height;

    final Widget content;
    if (widget.forMe) {
      content = _NudgeCard(name: widget.bubble.name);
    } else if (e.kind == ChatKind.emoji) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e.text!, style: const TextStyle(fontSize: 44)),
          _NameTag(name: widget.mine ? 'You' : widget.bubble.name),
        ],
      );
    } else {
      final text = e.kind == ChatKind.nudge
          ? '👋 ${widget.mine ? 'You' : widget.bubble.name} nudged ${widget.targetName}'
          : e.text!;
      content = Container(
        constraints: BoxConstraints(maxWidth: w * 0.7),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: c.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: widget.mine ? c.teal : c.marigold),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: Text.rich(
          TextSpan(
            children: [
              if (e.kind == ChatKind.phrase)
                TextSpan(
                  text: '${widget.mine ? 'You' : widget.bubble.name}  ',
                  style: TextStyle(color: c.marigold, fontSize: 12),
                ),
              TextSpan(text: text),
            ],
          ),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _c,
      child: content,
      builder: (context, child) {
        final t = still ? 0.5 : _c.value;
        final fade = t < 0.1 ? t / 0.1 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
        if (widget.forMe) {
          final shake = still ? 0.0 : sin(t * 60) * 10 * (1 - t);
          return Positioned(
            left: 0,
            right: 0,
            top: h * 0.32,
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(shake, 0),
                child: Center(child: child),
              ),
            ),
          );
        }
        final rise = Curves.easeOut.transform(t);
        final sway = still ? 0.0 : sin(t * 7 + lane * 6) * 14;
        final x = e.kind == ChatKind.emoji
            ? w * (0.12 + 0.76 * lane) - 34
            : w * 0.15;
        return Positioned(
          left: x + (e.kind == ChatKind.emoji ? sway : 0),
          bottom: 8 + rise * min(h * 0.45, 320),
          child: Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.7 + 0.3 * Curves.easeOutBack.transform(min(1, t * 5)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _NameTag extends StatelessWidget {
  const _NameTag({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.surfaceHigh.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        name,
        maxLines: 1,
        style: TextStyle(
          color: c.onSurface,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.lg,
      ),
      decoration: BoxDecoration(
        color: c.kumkum,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: c.kumkum.withValues(alpha: 0.5), blurRadius: 30),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👋', style: TextStyle(fontSize: 52)),
          Text(
            '$name nudged you!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once a deadline passes. Nothing is played automatically: the late
/// player gets a shaking reminder (and a buzz from the controller), everyone
/// else can nudge them, and after a while (or if they are offline) play for
/// them.
class LateBanner extends StatelessWidget {
  const LateBanner({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final l = ctrl.late;
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.curve,
      alignment: Alignment.bottomCenter,
      child: l == null
          ? const SizedBox(width: double.infinity)
          : ctrl.iAmLate
          ? _MeLate(ctrl: ctrl)
          : _OthersLate(ctrl: ctrl, late: l),
    );
  }
}

String _lateTask(Phase p) => switch (p) {
  Phase.picking || Phase.kqPicking => 'Pick your chits',
  Phase.characters => 'Pick your character chit',
  Phase.exchange => 'Pass one slip',
  Phase.kqGuessing => 'Make your guess',
  _ => 'Your move',
};

class _MeLate extends StatefulWidget {
  const _MeLate({required this.ctrl});
  final RoomController ctrl;

  @override
  State<_MeLate> createState() => _MeLateState();
}

class _MeLateState extends State<_MeLate> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
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
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // A quick wiggle, then a pause, on repeat.
        final t = _shake.value;
        final dx = t < 0.35 ? sin(t / 0.35 * pi * 6) * 5 : 0.0;
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
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: c.kumkum,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: c.kumkum.withValues(alpha: 0.45),
                blurRadius: 18,
              ),
            ],
          ),
          child: Row(
            children: [
              const Text('⏰', style: TextStyle(fontSize: 28)),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Time's up! Everyone is waiting for you",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _lateTask(ctrl.phase),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Text(
                '+${ctrl.overtimeSeconds}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OthersLate extends StatelessWidget {
  const _OthersLate({required this.ctrl, required this.late});
  final RoomController ctrl;
  final LateState late;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final first = late.uids.first;
    final name = room.nameOf(first);
    final who = late.uids.length == 1
        ? name
        : '$name and ${late.uids.length - 1} more';
    final over = ctrl.overtimeSeconds;
    final offline = late.uids.every(ctrl.isOffline);
    final String line;
    if (offline) {
      line = late.uids.length == 1
          ? '$name is offline 📵'
          : '$who are offline 📵';
    } else if (over < 10) {
      line = 'Waiting for $who ⏰';
    } else if (over < 25) {
      line = late.uids.length == 1
          ? '$name is thinking hard 🤔'
          : '$who are thinking hard 🤔';
    } else {
      line = late.uids.length == 1
          ? '$name fell asleep 😴'
          : '$who fell asleep 😴';
    }
    final nudgeTarget = late.uids.where(ctrl.canNudge).firstOrNull;
    final playForIn = (playForAfter.inSeconds - over).clamp(0, 99);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.sm),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.sm,
        Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.marigold.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  ctrl.canPlayForLate
                      ? '+${over}s over time'
                      : '+${over}s · you can play for them in ${playForIn}s',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (ctrl.canPlayForLate)
            FilledButton(
              onPressed: ctrl.busy ? null : ctrl.playForLate,
              child: Text(
                late.uids.length == 1 ? 'Play for $name' : 'Play for them',
              ),
            )
          else
            FilledButton.tonal(
              onPressed: nudgeTarget == null
                  ? null
                  : () => ctrl.nudge(nudgeTarget),
              child: const Text('Nudge 👋'),
            ),
        ],
      ),
    );
  }
}
