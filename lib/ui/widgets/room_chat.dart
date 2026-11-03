import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/chat.dart';
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
  });
  final ChatMessage message;
  final String name;
  final bool mine;
  final bool isHost;
  final bool first;

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
              bubble,
            ],
          ),
        ],
      ),
    );
  }
}
