/// Quick chat: preset emojis and phrases only, so there is no free text to
/// moderate. Codes are stored in Firestore (see firestore.rules) and must stay
/// stable: add new entries, never rename or reuse a code.
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
];

/// Preset phrases, Telugu first (it's a Telugu game), then English.
const quickPhrases = [
  QuickItem('twaraga', 'త్వరగా! ⏰'),
  QuickItem('ayyo', 'అయ్యో! 😩'),
  QuickItem('super', 'సూపర్! 👏'),
  QuickItem('nene', 'నేనే గెలుస్తా! 😎'),
  QuickItem('mosam', 'మోసం! 🤨'),
  QuickItem('baaga', 'బాగా ఆడావ్! 🙌'),
  QuickItem('hurry', 'Hurry up! ⏰'),
  QuickItem('nice', 'Nice one! 👏'),
  QuickItem('close', "I'm so close! 🤞"),
  QuickItem('oops', 'Oops! 🙈'),
  QuickItem('unfair', 'Not fair! 😤'),
  QuickItem('gg', 'Good game! 🤝'),
];

const nudgeCode = 'nudge';

enum ChatKind { emoji, phrase, nudge }

/// The latest quick-chat message from one player.
class ChatEvent {
  const ChatEvent({
    required this.id,
    required this.uid,
    required this.kind,
    required this.code,
    required this.at,
    this.to,
  });

  /// Random per message, so a local echo and its server copy count once.
  final String id;
  final String uid;
  final ChatKind kind;
  final String code;
  final DateTime at;

  /// Nudge target.
  final String? to;

  /// The emoji or phrase to show, or null for unknown codes from newer apps.
  String? get text {
    final list = switch (kind) {
      ChatKind.emoji => quickEmojis,
      ChatKind.phrase => quickPhrases,
      ChatKind.nudge => const <QuickItem>[QuickItem(nudgeCode, '👋')],
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
    return ChatEvent(
      id: id,
      uid: uid,
      kind: kind,
      code: code,
      at: at,
      to: m['to'] as String?,
    );
  }
}
