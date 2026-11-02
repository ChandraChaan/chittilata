import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/services/feedback.dart';
import '../../core/services/stats.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/common.dart';

/// Your avatar, level, stats and badges. Everything here stays on this
/// phone; only the avatar is shown to the players in your rooms.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = Services.of(context).prefs;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Your profile')),
      extendBodyBehindAppBar: true,
      body: GameBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: prefs,
            builder: (context, _) {
              final stats = prefs.stats;
              final counters = stats.counters;
              final earned = stats.earned.map((b) => b.id).toSet();
              final name = prefs.playerName.isEmpty
                  ? 'Player'
                  : prefs.playerName;
              return ListView(
                padding: const EdgeInsets.all(Space.lg),
                children: [
                  Panel(
                    child: Column(
                      children: [
                        PlayerAvatar(name: name, size: 88, emoji: prefs.avatar),
                        const SizedBox(height: Space.sm),
                        Text(name, style: context.text.headlineSmall),
                        const SizedBox(height: Space.md),
                        Row(
                          children: [
                            GoldText(
                              'Lv ${stats.level}',
                              style: context.text.titleLarge,
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: stats.levelProgress,
                                  minHeight: 12,
                                  color: c.marigold,
                                  backgroundColor: c.surfaceHigh,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          '${stats.xp} XP · ${stats.xpToNext} XP to '
                          'level ${stats.level + 1}',
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  _Title('Avatar'),
                  Panel(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        _AvatarChoice(
                          label: name.characters.first.toUpperCase(),
                          selected: prefs.avatar == null,
                          onTap: () => prefs.avatar = null,
                        ),
                        for (final a in avatarChoices)
                          _AvatarChoice(
                            label: a,
                            selected: prefs.avatar == a,
                            onTap: () => prefs.avatar = a,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'Other players see it in rooms you create or join.',
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  _Title('Stats'),
                  Panel(
                    child: Wrap(
                      spacing: Space.md,
                      runSpacing: Space.md,
                      alignment: WrapAlignment.spaceAround,
                      children: [
                        _Stat('🎲', 'Games', counters['games'] ?? 0),
                        _Stat('🎬', 'Rounds won', counters['roundWins'] ?? 0),
                        _Stat('👑', 'King titles', counters['kings'] ?? 0),
                        _Stat('👸', 'Queen titles', counters['queens'] ?? 0),
                        _Stat(
                          '🤴',
                          'Rounds as King',
                          counters['kingRounds'] ?? 0,
                        ),
                        _Stat('💬', 'Chats', counters['chats'] ?? 0),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  _Title('Badges · ${earned.length}/${achievements.length}'),
                  Panel(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Column(
                      children: [
                        for (final b in achievements)
                          _BadgeRow(
                            badge: b,
                            have: earned.contains(b.id),
                            progress: counters[b.stat] ?? 0,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Text(text, style: context.text.titleMedium),
  );
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Avatar $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Services.read(context).feedback.ui(Sfx.select);
          onTap();
        },
        child: AnimatedContainer(
          duration: Motion.fast,
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.marigold.withValues(alpha: 0.25) : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? c.marigold : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.emoji, this.label, this.value);
  final String emoji;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          Text('$value', style: context.text.titleLarge),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({
    required this.badge,
    required this.have,
    required this.progress,
  });
  final Achievement badge;
  final bool have;
  final int progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      leading: Opacity(
        opacity: have ? 1 : 0.35,
        child: Text(badge.emoji, style: const TextStyle(fontSize: 30)),
      ),
      title: Text(
        badge.title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: have ? c.onSurface : c.muted,
        ),
      ),
      subtitle: Text(badge.how, style: TextStyle(color: c.muted)),
      trailing: have
          ? Icon(Icons.verified_rounded, color: c.marigold)
          : Text(
              '${progress.clamp(0, badge.goal)}/${badge.goal}',
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
            ),
    );
  }
}
