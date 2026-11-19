import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/chat.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import 'common.dart';

/// The room chat: a scrolling history of everyone's emojis, lines and
/// (between friends) typed messages, with one-tap reactions and preset
/// lines at the bottom. Opens as a sheet over the game.
Future<void> showRoomChat(BuildContext context, RoomController ctrl) {
  ctrl.setChatOpen(true);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChatPanel(ctrl: ctrl),
  ).whenComplete(() => ctrl.setChatOpen(false));
}

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(ChatKind kind, String code) {
    if (!widget.ctrl.sendQuick(kind, code)) {
      showGameSnack(context, 'Easy there! One message a second 🙂');
    }
  }

  void _sendText() {
    final raw = _text.text;
    if (raw.trim().isEmpty) return;
    if (widget.ctrl.sendText(raw)) {
      _text.clear();
    } else {
      showGameSnack(context, 'Easy there! One message a second 🙂');
    }
  }

  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctrl = widget.ctrl;
    final height = MediaQuery.sizeOf(context).height;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final history = ctrl.chatHistory;
        if (history.length != _shown) {
          _shown = history.length;
          _stickToBottom();
        }
        final room = ctrl.room;
        return AnimatedPadding(
          duration: Motion.of(context, Motion.fast),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: height * 0.72,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Row(
                    children: [
                      Icon(Icons.forum_rounded, color: c.marigold),
                      const SizedBox(width: Space.sm),
                      Text('Room chat', style: context.text.titleMedium),
                      const Spacer(),
                      Text(
                        '${room?.activePlayers.length ?? 0} playing',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                      _ChatOptions(ctrl: ctrl),
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
                Expanded(
                  child: history.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.xl),
                            child: Text(
                              ctrl.canSendText
                                  ? 'Nothing yet. Say hi, tease the Thief, '
                                        'or cheer the King 👑'
                                  : 'Nothing yet. Send an emoji or a quick '
                                        'line to the table 👇',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.muted, height: 1.4),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.lg,
                            vertical: Space.sm,
                          ),
                          itemCount: history.length,
                          itemBuilder: (context, i) => _MessageRow(
                            message: history[i],
                            name: room?.nameOf(history[i].uid) ?? 'Player',
                            mine: history[i].uid == ctrl.uid,
                            isHost: history[i].uid == room?.hostUid,
                            first:
                                i == 0 || history[i - 1].uid != history[i].uid,
                            onLongPress: history[i].uid == ctrl.uid
                                ? null
                                : () => showChatActions(
                                    context,
                                    ctrl,
                                    history[i].uid,
                                    message: history[i],
                                  ),
                          ),
                        ),
                ),
                Container(height: 1, color: c.outline),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: 2,
                    ),
                    children: [
                      for (final e in quickEmojis)
                        Semantics(
                          button: true,
                          label: 'Send ${e.text}',
                          excludeSemantics: true,
                          child: InkResponse(
                            onTap: () => _send(ChatKind.emoji, e.code),
                            radius: 24,
                            child: SizedBox(
                              width: 44,
                              child: Center(
                                child: Text(
                                  e.text,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    itemCount: quickPhrases.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(quickPhrases[i].text),
                      onPressed: () =>
                          _send(ChatKind.phrase, quickPhrases[i].code),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.xs,
                    Space.sm,
                    Space.md,
                  ),
                  child: ctrl.canSendText
                      ? Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _text,
                                maxLength: maxChatText,
                                textInputAction: TextInputAction.send,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (_) => _sendText(),
                                decoration: const InputDecoration(
                                  hintText: 'Message the table…',
                                  counterText: '',
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: 'Send',
                              onPressed: _sendText,
                              icon: const Icon(Icons.send_rounded),
                            ),
                          ],
                        )
                      : Text(
                          'Quick-match tables use emojis and preset lines '
                          'only, so strangers stay strangers.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.name,
    required this.mine,
    required this.isHost,
    required this.first,
    this.onLongPress,
  });
  final ChatMessage message;
  final String name;
  final bool mine;
  final bool isHost;
  final bool first;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final emoji = message.kind == ChatKind.emoji;
    final t = TimeOfDay.fromDateTime(message.at);
    final time =
        '${t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: emoji
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
      decoration: emoji
          ? null
          : BoxDecoration(
              color: mine ? c.marigold.withValues(alpha: 0.22) : c.surfaceHigh,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(mine ? 18 : 6),
                bottomRight: Radius.circular(mine ? 6 : 18),
              ),
              border: Border.all(color: mine ? c.marigold : c.outline),
            ),
      child: Text(
        message.text,
        style: emoji
            ? const TextStyle(fontSize: 30)
            : const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: first ? Space.md : 3),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            Opacity(
              opacity: first ? 1 : 0,
              child: PlayerAvatar(name: name, size: 28),
            ),
            const SizedBox(width: Space.sm),
          ],
          Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (first)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${mine ? 'You' : name}${isHost ? ' · host' : ''} · $time',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              GestureDetector(
                onLongPress: onLongPress,
                child: Semantics(
                  onLongPressHint: onLongPress == null
                      ? null
                      : 'Mute or report $name',
                  child: bubble,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chat header's ⋮: typed messages on/off and the people in the room,
/// each of whom can be muted or reported.
class _ChatOptions extends StatelessWidget {
  const _ChatOptions({required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final room = ctrl.room;
    final others = [
      for (final p in room?.players.values ?? const <PlayerInfo>[])
        if (p.uid != ctrl.uid) p,
    ];
    return PopupMenuButton<String>(
      tooltip: 'Chat options',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        if (v == '#typed') {
          ctrl.setTypedChat(!ctrl.prefs.typedChat);
        } else {
          showChatActions(context, ctrl, v);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: '#typed',
          checked: ctrl.prefs.typedChat,
          child: const Text('Show typed messages'),
        ),
        if (others.isNotEmpty) const PopupMenuDivider(),
        for (final p in others)
          PopupMenuItem(
            value: p.uid,
            child: Row(
              children: [
                Icon(
                  ctrl.isMuted(p.uid)
                      ? Icons.volume_off_rounded
                      : Icons.person_rounded,
                  size: 18,
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(
                    ctrl.isMuted(p.uid) ? '${p.name} (muted)' : p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mute / unmute and report for one player (and the message long-pressed).
Future<void> showChatActions(
  BuildContext context,
  RoomController ctrl,
  String player, {
  ChatMessage? message,
}) {
  final name = ctrl.room?.nameOf(player) ?? 'Player';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final muted = ctrl.isMuted(player);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ctx.text.titleMedium,
                ),
              ),
              if (message != null && message.kind == ChatKind.text)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.xs,
                    Space.lg,
                    0,
                  ),
                  child: Text(
                    '"${message.text}"',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ctx.colors.muted),
                  ),
                ),
              const SizedBox(height: Space.sm),
              ListTile(
                leading: Icon(
                  muted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                ),
                title: Text(muted ? 'Unmute $name' : 'Mute $name'),
                subtitle: Text(
                  muted
                      ? 'Show their messages again'
                      : 'Hide their messages and nudges on this phone',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.setMuted(player, !muted);
                  showGameSnack(
                    context,
                    muted ? '$name unmuted' : '$name muted on this phone',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_rounded),
                title: Text(
                  message == null ? 'Report $name' : 'Report this message',
                ),
                subtitle: const Text(
                  'Sends it to the developer to review, and mutes them',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final reason = await _pickReason(context);
                  if (reason == null) return;
                  final ok = await ctrl.report(
                    player,
                    message: message,
                    reason: reason,
                  );
                  if (!context.mounted) return;
                  showGameSnack(
                    context,
                    ok
                        ? 'Thanks. Report sent, and $name is muted.'
                        : "Couldn't send the report. $name is muted; "
                              'try again when you are online.',
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> _pickReason(BuildContext context) {
  const reasons = {
    'abusive': 'Abusive or hateful',
    'sexual': 'Sexual or inappropriate',
    'spam': 'Spam',
    'name': 'Offensive name',
    'other': 'Something else',
  };
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('What is wrong?'),
      children: [
        for (final r in reasons.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Text(r.value),
            ),
          ),
      ],
    ),
  );
}
