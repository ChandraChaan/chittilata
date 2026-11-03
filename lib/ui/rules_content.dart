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
        'and scattered on the mat: 4 chits per name. Tap any 4 chits, or '
        'drag them down into your tray, and each one unfolds just for you. '
        'You have a minute; after that the '
        'rest are picked for you. The server deals everyone a fair hand '
        'of different names, so which chit you pick never changes your '
        'chances and nobody starts close to winning. Only you can see your '
        'slips.',
  ),
  RuleSection(
    Icons.autorenew_rounded,
    'Pass around the circle',
    'A new random seating circle is shown before each round. The first '
        'player passes one slip to the next player. That player now holds 5, '
        'looks at the new slip, and passes any one of their 5 onward: drag '
        'it onto the circle, or tap it and press Pass. Then the next player '
        'does the same, all the way around, again and again. Drop a slip on '
        'another to rearrange your hand.',
  ),
  RuleSection(
    Icons.timer_rounded,
    'Beat the timer',
    'Each turn has a timer set by the host. Nothing is ever played for '
        'you automatically: when time runs out your phone buzzes and everyone '
        'can nudge you 👋. If you still haven\'t passed after 45 seconds (or '
        'your phone is offline), another player can pass for you: by default '
        'the slip you just received, or a random slip if the host picked that '
        'rule. That never helps you, so pass in time!',
  ),
  RuleSection(
    Icons.chat_bubble_rounded,
    'Quick chat',
    'Tap an emoji at the bottom of the screen, or the chat button for fun '
        'lines in English and Telugu. Everyone in the room sees them float '
        'up for a few seconds.',
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
    Icons.flag_rounded,
    'No winner after 4 laps?',
    'If the slips have gone round the whole circle 4 times and nobody has '
        'four of a kind, the host can end the round. Nobody wins the movie '
        'points: instead everyone picks a folded character chit, and one of '
        'them is a King worth the win points.',
  ),
  RuleSection(
    Icons.logout_rounded,
    'Leaving, joining and the host',
    'You can leave at any time. If you leave during a round, that round is '
        'cancelled with no points and still counts. Friends can join a game '
        'that has already started when a seat is free: they play from the '
        'next round. The host can end the game for everyone at any time, and '
        'can warn a silent player, who then has a minute to tap "I\'m here"; '
        'after two warnings the host can remove them. If fewer than 3 '
        'players remain, the game ends with the scores so far.',
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
        'When only one player is left, it has to be them: you still make '
        'that last guess yourself, so every player finishes their own step.',
  ),
  RuleSection(
    Icons.timer_rounded,
    'Beat the timer',
    'Each guess has a timer. When it runs out your phone buzzes and the '
        'others can nudge you. After 45 seconds (or if you are offline) '
        'another player can make a random guess for you, which never helps '
        'or hurts anyone in particular.',
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

/// Movie Dumb Charades. Keep in sync with docs/CHARADES_RULES.md.
const charadesRuleSections = [
  RuleSection(
    Icons.groups_rounded,
    'Get together',
    'Play with 3–10 people in the same room (or on a video call). Everyone '
        'joins the room on their own phone.',
  ),
  RuleSection(
    Icons.theater_comedy_rounded,
    'Take turns acting',
    'Each round one player secretly sees a movie title on their phone and '
        'acts it out — no talking, no lip-syncing, no pointing at letters.',
  ),
  RuleSection(
    Icons.touch_app_rounded,
    'Pick the title',
    'Everyone else sees six titles and taps the one they think it is. You '
        'get one guess per round, so watch carefully!',
  ),
  RuleSection(
    Icons.bolt_rounded,
    'Fastest wins',
    'The first right guess scores 100 points plus 2 for every second left. '
        'The actor scores 75 when someone gets it. Nobody right in 75 seconds? '
        'Nobody scores.',
  ),
  RuleSection(
    Icons.emoji_events_rounded,
    'King and Queen',
    'After the last round, the top two are crowned King and Queen. Ties go '
        'to whoever guessed right most often.',
  ),
];
