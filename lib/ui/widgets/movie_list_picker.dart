import 'package:flutter/material.dart';

import '../../core/services/preferences.dart';
import '../../core/theme/app_theme.dart';

/// The movie lists a player can start rooms with, English first.
const movieListChoices = [
  ('hollywood', '🎬', 'English movies', 'Titanic, Avatar, Inception…'),
  ('telugu', '🌶️', 'Telugu movies', 'Baahubali, RRR, Pushpa…'),
  ('indian', '🇮🇳', 'All Indian movies', 'Hindi, Tamil, Telugu hits'),
  ('mixed', '🎲', 'Mixed', 'A bit of everything'),
];

/// Asks which movie list new rooms should use, once (English is
/// pre-selected). Returns the chosen list, or null if dismissed.
Future<String?> askMovieList(BuildContext context, Preferences prefs) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Which movies does your group know?',
              style: ctx.text.titleMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'You can change this any time in Settings, and the host can '
              'switch lists in the lobby.',
              style: TextStyle(color: ctx.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: Space.md),
            MovieListChoices(
              selected: prefs.movieList,
              onSelected: (v) {
                prefs.movieList = v;
                Navigator.pop(ctx, v);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// One tappable row per movie list, the selected one highlighted.
class MovieListChoices extends StatelessWidget {
  const MovieListChoices({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (final (value, emoji, title, hint) in movieListChoices)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Material(
              color: value == selected
                  ? c.marigold.withValues(alpha: 0.16)
                  : c.surfaceHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: value == selected ? c.marigold : c.outline,
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Text(emoji, style: const TextStyle(fontSize: 26)),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(hint),
                trailing: value == selected
                    ? Icon(Icons.check_circle_rounded, color: c.marigold)
                    : null,
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
          ),
      ],
    );
  }
}
