/// Room chat: one-tap emojis, preset lines and (in rooms of friends) short
/// text messages. Codes are stored in Firestore (see firestore.rules) and
/// must stay stable: add new entries, never rename or reuse a code.
library;

class QuickItem {
  const QuickItem(this.code, this.text);
  final String code;
  final String text;
}

/// One-tap reactions, in bar order.
const quickEmojis = [
  QuickItem('laugh', '😂'),
  QuickItem('fire', '🔥'),
  QuickItem('shock', '😱'),
  QuickItem('clap', '👏'),
  QuickItem('cry', '😭'),
  QuickItem('think', '🤔'),
  QuickItem('cool', '😎'),
  QuickItem('sleep', '😴'),
  QuickItem('pray', '🙏'),
  QuickItem('crown', '👑'),
  QuickItem('heart', '❤️'),
  QuickItem('devil', '😈'),
  QuickItem('eyes', '👀'),
  QuickItem('party', '🥳'),
  QuickItem('skull', '💀'),
  QuickItem('salute', '🫡'),
];

/// Preset lines, English first with a Telugu accent; the old Telugu codes
/// stay so older apps still show them.
const quickPhrases = [
  QuickItem('hurry', 'Hurry up! ⏰'),
  QuickItem('nice', 'Nice one! 👏'),
  QuickItem('close', "I'm so close! 🤞"),
  QuickItem('oops', 'Oops! 🙈'),
  QuickItem('unfair', 'Not fair! 😤'),
  QuickItem('gg', 'Good game! 🤝'),
  QuickItem('fourth', 'Who has my fourth chit? 👀'),
  QuickItem('chai', 'Pass faster, my chai is going cold ☕'),
  QuickItem('thief', 'I smell a Thief around here 🕵️'),
  QuickItem('bow', 'All bow to the King 🙇'),
  QuickItem('poker', 'Poker face activated 😐'),
  QuickItem('lag', 'Lag! It was the network, I swear 📶'),
  QuickItem('bluff', 'Bluffing? Me? Never 😇'),
  QuickItem('plan', 'This was my plan all along 🧠'),
  QuickItem('twaraga', 'త్వరగా! ⏰'),
  QuickItem('ayyo', 'అయ్యో! 😩'),
  QuickItem('super', 'సూపర్! 👏'),
  QuickItem('nene', 'నేనే గెలుస్తా! 😎'),
  QuickItem('mosam', 'మోసం! 🤨'),
  QuickItem('baaga', 'బాగా ఆడావ్! 🙌'),
];

const nudgeCode = 'nudge';

/// The code stored with a free-text message.
const textCode = 'text';

/// Longest free-text message (the rules enforce it too).
const maxChatText = 80;

enum ChatKind { emoji, phrase, nudge, text }

/// The latest message from one player (what floats up on screen).
class ChatEvent {
  const ChatEvent({
    required this.id,
    required this.uid,
    required this.kind,
    required this.code,
    required this.at,
    this.to,
    this.freeText,
  });

  /// Random per message, so a local echo and its server copy count once.
  final String id;
  final String uid;
  final ChatKind kind;
  final String code;
  final DateTime at;

  /// Nudge target.
  final String? to;

  /// The message typed by the player (kind == text).
  final String? freeText;

  /// The emoji, phrase or text to show, or null for unknown codes from
  /// newer apps.
  String? get text {
    if (kind == ChatKind.text) return freeText;
    return textFor(kind, code);
  }

  static String? textFor(ChatKind kind, String code) {
    final list = switch (kind) {
      ChatKind.emoji => quickEmojis,
      ChatKind.phrase => quickPhrases,
      ChatKind.nudge => const <QuickItem>[QuickItem(nudgeCode, '👋')],
      ChatKind.text => const <QuickItem>[],
    };
    for (final q in list) {
      if (q.code == code) return q.text;
    }
    return null;
  }

  static ChatEvent? fromMap(String uid, Map<String, dynamic> m, DateTime at) {
    final kind = ChatKind.values.where((k) => k.name == m['kind']).firstOrNull;
    final id = m['id'];
    final code = m['code'];
    if (kind == null || id is! String || code is! String) return null;
    final text = m['text'];
    if (kind == ChatKind.text && text is! String) return null;
    return ChatEvent(
      id: id,
      uid: uid,
      kind: kind,
      code: code,
      at: at,
      to: m['to'] as String?,
      freeText: kind == ChatKind.text ? text as String : null,
    );
  }
}

/// One line of the room's chat history (emojis, lines and texts; nudges
/// are not kept).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.kind,
    required this.text,
    required this.at,
  });
  final String id;
  final String uid;
  final ChatKind kind;
  final String text;
  final DateTime at;

  static ChatMessage? fromMap(String id, Map<String, dynamic> m, DateTime at) {
    final kind = ChatKind.values.where((k) => k.name == m['kind']).firstOrNull;
    final uid = m['uid'];
    final code = m['code'];
    if (kind == null || kind == ChatKind.nudge || uid is! String) return null;
    final text = kind == ChatKind.text
        ? m['text']
        : (code is String ? ChatEvent.textFor(kind, code) : null);
    if (text is! String) return null;
    return ChatMessage(id: id, uid: uid, kind: kind, text: text, at: at);
  }
}

/// A short, friendly filter for free text between friends: trims, collapses
/// whitespace, caps the length and masks a few words nobody wants to see
/// in a family room. Returns null when nothing is left to send.
String? cleanChatText(String raw) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;
  if (t.length > maxChatText) t = t.substring(0, maxChatText);
  for (final w in _blocked) {
    t = t.replaceAll(
      RegExp('\\b${RegExp.escape(w)}\\w*', caseSensitive: false),
      '*' * w.length,
    );
  }
  return t;
}

const _blocked = [
  'fuck',
  'shit',
  'bitch',
  'bastard',
  'asshole',
  'cunt',
  'slut',
  'whore',
  'lanja',
  'dengu',
  'puku',
  'modda',
  'gudda',
  'kojja',
  'randi',
  'chutiya',
  'madarchod',
  'behenchod',
  'bhosdi',
  'gandu',
];
