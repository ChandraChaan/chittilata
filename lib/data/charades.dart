import 'models.dart';

/// One round of Movie Dumb Charades (public: no answer until it ends).
class CharadesRound {
  const CharadesRound({
    required this.key,
    required this.gameNo,
    required this.roundNo,
    required this.revealed,
    required this.actor,
    required this.options,
    required this.startsAt,
    required this.deadline,
    required this.guesses,
    this.solvedBy,
    this.answer,
    this.scores,
    this.endedReason,
  });
  final String key;
  final int gameNo;
  final int roundNo;
  final bool revealed;
  final String actor;
  final List<String> options;
  final DateTime startsAt;
  final DateTime deadline;

  /// uid -> option index (one guess each).
  final Map<String, int> guesses;
  final String? solvedBy;
  final int? answer;
  final Map<String, int>? scores;
  final String? endedReason;

  factory CharadesRound.fromMap(String key, Map<String, dynamic> m) =>
      CharadesRound(
        key: key,
        gameNo: (m['gameNo'] as num?)?.toInt() ?? 1,
        roundNo: (m['roundNo'] as num?)?.toInt() ?? 1,
        revealed: m['status'] == 'revealed',
        actor: m['actor'] as String? ?? '',
        options: List<String>.from(m['options'] as List? ?? const []),
        startsAt: timeOf(m['startsAt']) ?? DateTime.now(),
        deadline: timeOf(m['deadline']) ?? DateTime.now(),
        guesses: {
          for (final e in (m['guesses'] as Map? ?? {}).entries)
            e.key as String: (e.value as num).toInt(),
        },
        solvedBy: m['solvedBy'] as String?,
        answer: (m['answer'] as num?)?.toInt(),
        scores: m['scores'] == null
            ? null
            : {
                for (final e in (m['scores'] as Map).entries)
                  e.key as String: (e.value as num).toInt(),
              },
        endedReason: m['endedReason'] as String?,
      );
}

/// The movie only the actor can see.
class CharadesCard {
  const CharadesCard(this.roundKey, this.movie);
  final String roundKey;
  final String movie;
}
