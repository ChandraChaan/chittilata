import 'package:flutter/material.dart';

class RuleSection {
  const RuleSection(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

/// The in-app rules. Keep in sync with docs/GAME_RULES.md.
const ruleSections = [
  RuleSection(
    Icons.groups_rounded,
    'Gather 3–10 friends',
    'Everyone plays on their own phone. One person creates a room and '
        'shares the 6-letter code; the others join with it. Four players is '
        'the classic game.',
  ),
  RuleSection(
    Icons.style_rounded,
    'Pick 4 folded chits',
    'Each round, the movie names are written on paper, folded, shuffled '
        'and scattered on the mat: 4 chits per name. Tap any 4 chits and '
        'each one unfolds just for you. The server deals everyone a fair hand '
        'of different names, so which chit you pick never changes your '
        'chances and nobody starts close to winning. Only you can see your '
        'slips.',
  ),
  RuleSection(
    Icons.autorenew_rounded,
    'Pass around the circle',
    'A new random seating circle is shown before each round. The first '
        'player passes one slip to the next player. That player now holds 5, '
        'looks at the new slip, and passes any one of their 5 onward. Then '
        'the next player does the same, all the way around, again and again.',
  ),
  RuleSection(
    Icons.timer_rounded,
    'Beat the timer',
    'Each turn has a timer set by the host. If time runs out, the game '
        'passes a slip for you: by default the slip you just received, or a '
        'random slip if the host picked that rule. Timeouts never help you, '
        'so pass in time! With "No timer", the game waits 5 minutes before '
        'passing for you.',
  ),
  RuleSection(
    Icons.emoji_events_rounded,
    'Collect four of a kind',
    'The first player to hold 4 slips with the same movie wins the round '
        'and earns the win points (1,000 by default). If you hold 5 slips '
        'with four matching, pass the odd one out to win. Passing stops '
        'the moment someone wins.',
  ),
  RuleSection(
    Icons.theater_comedy_rounded,
    'Secret characters',
    'Everyone else picks one folded character chit, such as Queen 800, '
        'Police 500 or Thief 100. The character inside is exactly what you '
        'get, and only you see it until the reveal. With more players there '
        'are more characters.',
  ),
  RuleSection(
    Icons.visibility_rounded,
    'Reveal and score',
    'After a few seconds, everyone\'s slips and characters are revealed. '
        'Round points are added to your total and the leaderboard updates.',
  ),
  RuleSection(
    Icons.workspace_premium_rounded,
    'Crown the King and Queen',
    'After the last round, the highest total is King and the second '
        'highest is Queen. Ties are settled by most movie wins. If players '
        'are still tied for a title, they choose: play one tie-breaker round '
        'between just the tied players, or share the title. Everyone tied '
        'must agree to play; otherwise, or with no answer in 30 seconds, the '
        'title is shared. Tie-breaker points only break the tie and never '
        'change anyone\'s total.',
  ),
  RuleSection(
    Icons.logout_rounded,
    'If someone leaves',
    'If a player leaves during passing, that round is cancelled with no '
        'points, and it still counts as one of the rounds. If fewer than 3 '
        'players remain, the game ends with the scores so far. Losing '
        'connection does not remove you; reopen the app to rejoin.',
  ),
];

/// King & Queen rules. Keep in sync with docs/KING_QUEEN_RULES.md.
const kqRuleSections = [
  RuleSection(
    Icons.groups_rounded,
    'Gather 4–10 friends',
    'One person creates a King & Queen room and shares the code. Everyone '
        'plays on their own phone.',
  ),
  RuleSection(
    Icons.style_rounded,
    'Pick one folded chit',
    'The roles are written on paper, folded, shuffled and scattered. Each '
        'player picks exactly one chit and sees their role privately. Four '
        'players use King, Queen, Police and Thief. With more players, '
        'Minister, Commander, Merchant, Poet, Farmer and Jester join in.',
  ),
  RuleSection(
    Icons.workspace_premium_rounded,
    'The King starts',
    'The King is announced to everyone and must find the Queen. Tap the '
        'player you think is the Queen and confirm.',
  ),
  RuleSection(
    Icons.check_circle_rounded,
    'Right guess',
    'The King keeps the crown for good. The Queen is revealed and must now '
        'find the next role in the chain (the Police, or the Minister in '
        'bigger games), and so on down to the Thief.',
  ),
  RuleSection(
    Icons.swap_horiz_rounded,
    'Wrong guess: swap!',
    'If you pick the wrong player, you two swap roles and you lose your '
        'turn. They now hold your role and must find the same target. You '
        'are marked "not the target", so nobody guesses you again for it. '
        'When only one player is left, they must be the one.',
  ),
  RuleSection(
    Icons.timer_rounded,
    'Beat the timer',
    'Each guess has a timer. If it runs out, the game picks a random '
        'player for you. That never helps or hurts anyone in particular.',
  ),
  RuleSection(
    Icons.emoji_events_rounded,
    'Score your final role',
    'When every role is found, all roles are revealed. Everyone scores '
        'their final role: King 1000, Queen 800, Police 500, Thief 100 (the '
        'host can change points). Totals add up across rounds.',
  ),
  RuleSection(
    Icons.diamond_rounded,
    'Crown the champions',
    'After the last round, the top total is King and the next is Queen. '
        'Ties go to whoever finished the most rounds as King. If still tied, '
        'the title is shared.',
  ),
];
