import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../core/services/invite_links.dart';
import '../../core/theme/app_theme.dart';
import '../../data/game_repository.dart';
import '../../data/groups.dart';
import '../../data/models.dart';
import '../widgets/common.dart';
import 'room_screen.dart';

/// Your friend groups, and creating or joining one.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key, this.joinCode});

  /// From a group invite link: joined as soon as the screen opens.
  final String? joinCode;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend groups')),
      extendBodyBehindAppBar: true,
      body: GameBackground(
        child: SafeArea(
          child: _AutoJoin(
            code: joinCode,
            child: StreamBuilder<List<Group>>(
              stream: s.repo.watchMyGroups(),
              builder: (context, snap) {
                final groups = snap.data ?? const <Group>[];
                return ListView(
                  padding: const EdgeInsets.all(Space.lg),
                  children: [
                    Text(
                      'Save your regular circle — family, cousins, office '
                      'gang — and play for a monthly leaderboard. Each '
                      'month crowns a champion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted, height: 1.4),
                    ),
                    const SizedBox(height: Space.lg),
                    if (!snap.hasData && !snap.hasError)
                      const Center(child: CircularProgressIndicator())
                    else if (groups.isEmpty)
                      Panel(
                        child: Column(
                          children: [
                            const Text('👥', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: Space.sm),
                            Text(
                              'No groups yet',
                              style: context.text.titleMedium,
                            ),
                          ],
                        ),
                      )
                    else
                      Panel(
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Column(
                          children: [
                            for (final g in groups)
                              ListTile(
                                leading: const Text(
                                  '👥',
                                  style: TextStyle(fontSize: 28),
                                ),
                                title: Text(
                                  g.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${g.memberUids.length} members',
                                  style: TextStyle(color: c.muted),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  gameRoute(GroupScreen(groupId: g.id)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.xl),
                    BigButton(
                      label: 'Create a group',
                      icon: Icons.group_add_rounded,
                      onPressed: () => _create(context),
                    ),
                    const SizedBox(height: Space.md),
                    BigButton(
                      label: 'Join with a group code',
                      icon: Icons.login_rounded,
                      secondary: true,
                      onPressed: () => _join(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await _ask(
      context,
      title: 'New group',
      hint: 'e.g. Family, Office gang',
      max: 24,
    );
    if (name == null || !context.mounted) return;
    final id = await _guard(context, (s) {
      return s.repo.createGroup(name, _playerName(s), s.prefs.avatar);
    });
    if (id != null && context.mounted) {
      Navigator.push(context, gameRoute(GroupScreen(groupId: id)));
    }
  }

  Future<void> _join(BuildContext context) async {
    final code = await _ask(
      context,
      title: 'Join a group',
      hint: '6-character group code',
      max: 6,
      code: true,
    );
    if (code == null || !context.mounted) return;
    await joinGroupAndOpen(context, code);
  }
}

/// Joins [code] and opens the group (used by links and the join button).
Future<void> joinGroupAndOpen(BuildContext context, String code) async {
  final id = await _guard(
    context,
    (s) => s.repo.joinGroup(code.toUpperCase(), _playerName(s), s.prefs.avatar),
  );
  if (id != null && context.mounted) {
    Navigator.push(context, gameRoute(GroupScreen(groupId: id)));
  }
}

String _playerName(AppServices s) =>
    s.prefs.playerName.trim().isEmpty ? 'Player' : s.prefs.playerName.trim();

Future<T?> _guard<T>(
  BuildContext context,
  Future<T> Function(AppServices s) f,
) async {
  final s = Services.read(context);
  try {
    return await f(s);
  } on GameException catch (e) {
    if (context.mounted) showGameSnack(context, e.message);
  } catch (_) {
    if (context.mounted) {
      showGameSnack(context, 'Could not reach the game server.');
    }
  }
  return null;
}

Future<String?> _ask(
  BuildContext context, {
  required String title,
  required String hint,
  required int max,
  bool code = false,
}) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: max,
        textCapitalization: code
            ? TextCapitalization.characters
            : TextCapitalization.words,
        inputFormatters: code
            ? [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]'))]
            : null,
        decoration: InputDecoration(hintText: hint, counterText: ''),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  ).then((v) => v == null || v.isEmpty ? null : v);
}

class _AutoJoin extends StatefulWidget {
  const _AutoJoin({required this.code, required this.child});
  final String? code;
  final Widget child;

  @override
  State<_AutoJoin> createState() => _AutoJoinState();
}

class _AutoJoinState extends State<_AutoJoin> {
  @override
  void initState() {
    super.initState();
    final code = widget.code;
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => joinGroupAndOpen(context, code),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One group: invite, this month's leaderboard, last month's champion,
/// members, and starting a game that counts for the group.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final c = context.colors;
    final now = Season.idFor(DateTime.now());
    final last = Season.previous(now);
    return StreamBuilder<Group?>(
      stream: s.repo.watchGroup(groupId),
      builder: (context, snap) {
        final g = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text(g?.name ?? 'Group')),
          extendBodyBehindAppBar: true,
          body: GameBackground(
            child: SafeArea(
              child: g == null
                  ? Center(
                      child: snap.connectionState == ConnectionState.waiting
                          ? const CircularProgressIndicator()
                          : const Text("You're not in this group."),
                    )
                  : AvatarScope(
                      avatars: {
                        for (final m in g.members.values)
                          if (m.avatar != null) m.name: m.avatar!,
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(Space.lg),
                        children: [
                          _InviteCard(group: g),
                          const SizedBox(height: Space.lg),
                          _SeasonCard(
                            group: g,
                            season: now,
                            title: '🏆 ${Season.label(now)}',
                          ),
                          const SizedBox(height: Space.md),
                          _Champion(group: g, season: last),
                          const SizedBox(height: Space.lg),
                          BigButton(
                            label: 'New Movie Chits game',
                            icon: Icons.movie_rounded,
                            onPressed: () =>
                                _newGame(context, g, GameMode.movie),
                          ),
                          const SizedBox(height: Space.sm),
                          BigButton(
                            label: 'New King & Queen game',
                            icon: Icons.workspace_premium_rounded,
                            secondary: true,
                            onPressed: () =>
                                _newGame(context, g, GameMode.kingQueen),
                          ),
                          const SizedBox(height: Space.lg),
                          Text(
                            'Members · ${g.memberUids.length}',
                            style: context.text.titleMedium,
                          ),
                          const SizedBox(height: Space.sm),
                          Panel(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.xs,
                            ),
                            child: Column(
                              children: [
                                for (final u in g.memberUids)
                                  ListTile(
                                    leading: PlayerAvatar(name: g.nameOf(u)),
                                    title: Text(
                                      u == s.repo.uid
                                          ? '${g.nameOf(u)} (you)'
                                          : g.nameOf(u),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: u == g.ownerUid
                                        ? Text(
                                            'Created the group',
                                            style: TextStyle(color: c.muted),
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.lg),
                          TextButton.icon(
                            onPressed: () => _leave(context, g),
                            icon: Icon(
                              Icons.logout_rounded,
                              color: c.kumkum,
                              size: 18,
                            ),
                            label: Text(
                              'Leave group',
                              style: TextStyle(color: c.kumkum),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _newGame(BuildContext context, Group g, GameMode mode) async {
    final s = Services.read(context);
    final r = await _guard(
      context,
      (s) => s.repo.createRoom(
        _playerName(s),
        mode: mode,
        avatar: s.prefs.avatar,
        groupId: g.id,
      ),
    );
    if (r == null || !context.mounted) return;
    s.prefs.activeRoomId = r.roomId;
    Navigator.push(
      context,
      gameRoute(RoomScreen(roomId: r.roomId), name: RoomScreen.routeName),
    );
  }

  Future<void> _leave(BuildContext context, Group g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${g.name}?'),
        content: const Text(
          'Your past seasons stay. You can join again with the group code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _guard(context, (s) => s.repo.leaveGroup(g.id));
    if (context.mounted) Navigator.pop(context);
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Panel(
      color: c.surfaceHigh,
      child: Column(
        children: [
          Text(
            'GROUP CODE',
            style: TextStyle(
              color: c.muted,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          Text(
            group.code,
            style: context.text.headlineMedium?.copyWith(
              color: c.marigold,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.sm,
            children: [
              FilledButton.icon(
                onPressed: withClick(
                  context,
                  () => SharePlus.instance
                      .share(
                        ShareParams(
                          text: InviteLinks.groupMessage(
                            group.name,
                            group.code,
                          ),
                        ),
                      )
                      .catchError((_) => ShareResult.unavailable),
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Invite'),
              ),
              TextButton.icon(
                onPressed: withClick(context, () {
                  Clipboard.setData(
                    ClipboardData(
                      text: InviteLinks.groupMessage(group.name, group.code),
                    ),
                  );
                  showGameSnack(context, 'Group invite copied');
                }),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.group,
    required this.season,
    required this.title,
  });
  final Group group;
  final String season;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return StreamBuilder<Season>(
      stream: Services.of(context).repo.watchSeason(group.id, season),
      builder: (context, snap) {
        final s = snap.data ?? Season(id: season);
        final ranking = s.ranking;
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: context.text.titleMedium),
              const SizedBox(height: Space.sm),
              if (ranking.isEmpty)
                Text(
                  'No games yet this month. Start one below — every game '
                  'counts!',
                  style: TextStyle(color: c.muted, height: 1.35),
                )
              else
                for (final (i, u) in ranking.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        PlayerAvatar(name: group.nameOf(u), size: 32),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.nameOf(u),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${s.games[u] ?? 0} games · '
                                '👑 ${s.kings[u] ?? 0}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Text(
                          '${s.points[u] ?? 0}',
                          style: context.text.titleMedium?.copyWith(
                            color: c.leaf,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Champion extends StatelessWidget {
  const _Champion({required this.group, required this.season});
  final Group group;
  final String season;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Season>(
      stream: Services.of(context).repo.watchSeason(group.id, season),
      builder: (context, snap) {
        final ranking = snap.data?.ranking ?? const [];
        if (ranking.isEmpty) return const SizedBox.shrink();
        final champ = ranking.first;
        return Panel(
          color: context.colors.marigold.withValues(alpha: 0.14),
          child: Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 32)),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  '${group.nameOf(champ)} was champion of '
                  '${Season.label(season)} with '
                  '${snap.data!.points[champ] ?? 0} points!',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
