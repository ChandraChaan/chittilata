import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../game/room_controller.dart';
import '../widgets/common.dart';
import 'onboarding_screen.dart';

const categoryLabels = {
  Category.telugu: 'Telugu movies',
  Category.indian: 'All Indian movies',
  Category.hollywood: 'Hollywood movies',
  Category.mixed: 'Mixed categories',
  Category.custom: 'Custom names',
};

const difficultyLabels = {
  Difficulty.easy: 'Easy',
  Difficulty.normal: 'Normal',
  Difficulty.challenging: 'Challenging',
};

String timerLabel(int s) => s == 0 ? 'No timer' : '${s}s';

class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.ctrl, required this.onLeave});
  final RoomController ctrl;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final room = ctrl.room!;
    final c = context.colors;
    final me = room.players[ctrl.uid];
    final players = room.activePlayers;
    final count = players.length;
    final minPlayers = room.isKq ? 4 : 3;
    final canStart = count >= minPlayers && count <= 10 && room.everyoneReady();

    return Column(
      children: [
        _TopBar(
          title: room.isKq ? '👑 King & Queen lobby' : '🎬 Movie Chits lobby',
          onLeave: onLeave,
          mode: room.mode,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            children: [
              _CodeCard(code: room.code),
              const SizedBox(height: Space.lg),
              Row(
                children: [
                  Text('Players', style: context.text.titleMedium),
                  const SizedBox(width: Space.sm),
                  Text(
                    '$count / 10',
                    style: TextStyle(
                      color: c.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (count < minPlayers)
                    Text(
                      'Need ${minPlayers - count} more',
                      style: TextStyle(
                        color: c.kumkum,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Panel(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(
                  children: [
                    for (final p in players)
                      ListTile(
                        leading: PlayerAvatar(
                          name: p.name,
                          online: ctrl.isOnline(p.uid),
                        ),
                        title: Text(
                          p.uid == ctrl.uid ? '${p.name} (you)' : p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          p.uid == room.hostUid
                              ? 'Host'
                              : ctrl.isAway(p.uid)
                              ? 'App in background'
                              : ctrl.isOnline(p.uid)
                              ? 'Online'
                              : 'Offline',
                          style: TextStyle(color: c.muted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ReadyChip(ready: p.ready || p.uid == room.hostUid),
                            if (ctrl.isHost && p.uid != ctrl.uid)
                              IconButton(
                                tooltip: 'Remove ${p.name}',
                                icon: Icon(Icons.close_rounded, color: c.muted),
                                onPressed: () => _confirmKick(context, p),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              if (room.isKq)
                _KqSettingsSummary(ctrl: ctrl)
              else
                _SettingsSummary(ctrl: ctrl),
              const SizedBox(height: Space.xl),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: ctrl.isHost
              ? Column(
                  children: [
                    if (!canStart)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(
                          count < minPlayers
                              ? 'Share the code. $minPlayers–10 players can play.'
                              : 'Waiting for everyone to tap Ready…',
                          style: TextStyle(color: c.muted),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: BigButton(
                        label: 'Start game',
                        icon: Icons.play_arrow_rounded,
                        busy: ctrl.busy,
                        onPressed: canStart ? ctrl.startGame : null,
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: BigButton(
                    label: me?.ready == true
                        ? "I'm ready ✓  (tap to undo)"
                        : "I'm ready",
                    icon: me?.ready == true ? null : Icons.check_circle_rounded,
                    secondary: me?.ready == true,
                    busy: ctrl.busy,
                    onPressed: () => ctrl.setReady(!(me?.ready ?? false)),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmKick(BuildContext context, PlayerInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: const Text('They will not be able to rejoin this room.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) ctrl.kick(p.uid);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onLeave,
    required this.mode,
  });
  final String title;
  final VoidCallback onLeave;
  final GameMode mode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.sm,
      vertical: Space.xs,
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Leave room',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onLeave,
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Rules',
          icon: const Icon(Icons.menu_book_rounded),
          onPressed: () =>
              Navigator.push(context, gameRoute(OnboardingScreen(mode: mode))),
        ),
      ],
    ),
  );
}

/// King & Queen settings shown in the lobby.
class _KqSettingsSummary extends StatelessWidget {
  const _KqSettingsSummary({required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final room = ctrl.room!;
    final s = room.kqSettings!;
    final n = room.memberUids.length.clamp(4, 10);
    final chain = s.chainFor(n);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Game settings', style: context.text.titleMedium),
              const Spacer(),
              if (ctrl.isHost)
                FilledButton.tonalIcon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => KqSettingsSheet(ctrl: ctrl),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            '${s.rounds} rounds · ${timerLabel(s.turnSeconds)} per guess',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Roles for $n players (in finding order)',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in chain)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${r.name} ${r.points}'),
                ),
            ],
          ),
          if (!ctrl.isHost)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Only the host can change settings.',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Host-only King & Queen settings: rounds, guess timer, role points and
/// names of optional roles. Validated again on the server.
class KqSettingsSheet extends StatefulWidget {
  const KqSettingsSheet({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  State<KqSettingsSheet> createState() => _KqSettingsSheetState();
}

class _KqSettingsSheetState extends State<KqSettingsSheet> {
  late final KqSettings s = widget.ctrl.room!.kqSettings!;
  late int rounds = s.rounds;
  late int turnSeconds = s.turnSeconds;
  late final _roundsCtl = TextEditingController(text: '$rounds');
  late final roles = [
    for (final r in s.roles)
      (
        r,
        TextEditingController(text: r.name),
        TextEditingController(text: '${r.points}'),
      ),
  ];

  @override
  void dispose() {
    _roundsCtl.dispose();
    for (final r in roles) {
      r.$2.dispose();
      r.$3.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.ctrl.updateKqSettings({
      'rounds': rounds,
      'turnSeconds': turnSeconds,
      'roles': [
        for (final r in roles)
          {
            'key': r.$1.key,
            if (!r.$1.core) 'name': r.$2.text.trim(),
            'points': int.tryParse(r.$3.text.trim()) ?? r.$1.points,
          },
      ],
    });
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
      child: Text(
        t,
        style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              children: [
                Text('King & Queen settings', style: context.text.titleLarge),
                label('Rounds'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final r in KqSettings.roundOptions)
                      ChoiceChip(
                        label: Text('$r'),
                        selected: rounds == r,
                        onSelected: (_) => setState(() {
                          rounds = r;
                          _roundsCtl.text = '$r';
                        }),
                      ),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _roundsCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Custom',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n >= 1 && n <= 30) {
                            setState(() => rounds = n);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                label('Time per guess'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final t in GameSettings.turnOptions)
                      ChoiceChip(
                        label: Text(timerLabel(t)),
                        selected: turnSeconds == t,
                        onSelected: (_) => setState(() => turnSeconds = t),
                      ),
                  ],
                ),
                label('Roles and points'),
                Text(
                  'King, Queen, Police and Thief are always used. Optional '
                  'roles join from the top as more players play.',
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                const SizedBox(height: Space.sm),
                for (final r in roles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: r.$2,
                            enabled: !r.$1.core,
                            maxLength: 16,
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              labelText: r.$1.core ? 'Core role' : 'Optional',
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: r.$3,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Points',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.xl,
              Space.sm,
              Space.xl,
              Space.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ListenableBuilder(
                listenable: widget.ctrl,
                builder: (_, _) => BigButton(
                  label: 'Save settings',
                  busy: widget.ctrl.busy,
                  onPressed: _save,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Panel(
      color: c.surfaceHigh,
      child: Column(
        children: [
          Text(
            'ROOM CODE',
            style: TextStyle(
              color: c.muted,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: Space.xs),
          Semantics(
            label: 'Room code ${code.split('').join(' ')}',
            excludeSemantics: true,
            child: Text(
              code,
              style: context.text.displaySmall?.copyWith(
                color: c.marigold,
                letterSpacing: 8,
                fontFeatures: const [],
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: 'Join my Chittilata game! Room code: $code',
                ),
              );
              showGameSnack(
                context,
                'Invite copied — paste it in your group chat',
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy invite'),
          ),
        ],
      ),
    );
  }
}

class _ReadyChip extends StatelessWidget {
  const _ReadyChip({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ready ? c.leaf.withValues(alpha: 0.2) : c.outline,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'Ready' : 'Not ready',
        style: TextStyle(
          color: ready ? c.leaf : c.muted,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SettingsSummary extends StatelessWidget {
  const _SettingsSummary({required this.ctrl});
  final RoomController ctrl;

  @override
  Widget build(BuildContext context) {
    final s = ctrl.room!.settings;
    final c = context.colors;
    final rows = [
      (Icons.movie_rounded, 'Category', categoryLabels[s.category]!),
      (Icons.speed_rounded, 'Difficulty', difficultyLabels[s.difficulty]!),
      (Icons.timer_rounded, 'Turn timer', timerLabel(s.turnSeconds)),
      (Icons.repeat_rounded, 'Rounds', '${s.rounds}'),
      (Icons.emoji_events_rounded, 'Win points', '${s.winPoints}'),
      (
        Icons.theater_comedy_rounded,
        'Characters',
        s.characters
            .take((ctrl.room!.memberUids.length - 1).clamp(2, 9))
            .map((c) => '${c.name} ${c.points}')
            .join(' · '),
      ),
    ];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Game settings', style: context.text.titleMedium),
              const Spacer(),
              if (ctrl.isHost)
                FilledButton.tonalIcon(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SettingsSheet(ctrl: ctrl),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(r.$1, size: 18, color: c.muted),
                  const SizedBox(width: Space.sm),
                  SizedBox(
                    width: 92,
                    child: Text(r.$2, style: TextStyle(color: c.muted)),
                  ),
                  Expanded(
                    child: Text(
                      r.$3,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (!ctrl.isHost)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Only the host can change settings.',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

const _customPresets = {
  'Countries': [
    'India',
    'Japan',
    'Brazil',
    'Canada',
    'Egypt',
    'France',
    'Kenya',
    'Mexico',
    'Norway',
    'Peru',
  ],
  'Cities': [
    'Hyderabad',
    'Vizag',
    'Vijayawada',
    'Tirupati',
    'Warangal',
    'Chennai',
    'Bengaluru',
    'Mumbai',
    'Delhi',
    'Guntur',
  ],
  'Fruits': [
    'Mango',
    'Banana',
    'Guava',
    'Jackfruit',
    'Papaya',
    'Grapes',
    'Orange',
    'Pomegranate',
    'Watermelon',
    'Sapota',
  ],
};

/// Host-only settings editor. Changes are validated again on the server.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.ctrl});
  final RoomController ctrl;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late GameSettings s = widget.ctrl.room!.settings;
  late Category category = s.category;
  late Difficulty difficulty = s.difficulty;
  late int turnSeconds = s.turnSeconds;
  late int rounds = s.rounds;
  late TimeoutPolicy policy = s.timeoutPolicy;
  late int winPoints = s.winPoints;
  late final _custom = TextEditingController(text: s.customNames.join('\n'));
  late final _roundsCtl = TextEditingController(text: '$rounds');
  late List<(TextEditingController, TextEditingController)> chars = [
    for (final c in s.characters)
      (
        TextEditingController(text: c.name),
        TextEditingController(text: '${c.points}'),
      ),
  ];

  @override
  void dispose() {
    _custom.dispose();
    _roundsCtl.dispose();
    for (final c in chars) {
      c.$1.dispose();
      c.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final customNames = _custom.text
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final players = widget.ctrl.room!.memberUids.length;
    if (category == Category.custom &&
        customNames.length < players.clamp(3, 10)) {
      showGameSnack(
        context,
        'Add at least ${players.clamp(3, 10)} custom names (one per player).',
      );
      return;
    }
    final characters = [
      for (final c in chars)
        if (c.$1.text.trim().isNotEmpty)
          {
            'name': c.$1.text.trim(),
            'points': int.tryParse(c.$2.text.trim()) ?? 0,
          },
    ];
    final ok = await widget.ctrl.updateSettings({
      'category': category.name,
      'difficulty': difficulty.name,
      'turnSeconds': turnSeconds,
      'rounds': rounds,
      'timeoutPolicy': policy.name,
      'winPoints': winPoints,
      'customNames': customNames,
      'characters': characters,
    });
    if (ok && mounted) Navigator.pop(context);
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
    child: Text(
      t,
      style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              children: [
                Text('Game settings', style: context.text.titleLarge),
                _label('Category'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final cat in Category.values)
                      ChoiceChip(
                        label: Text(categoryLabels[cat]!),
                        selected: category == cat,
                        onSelected: (_) => setState(() => category = cat),
                      ),
                  ],
                ),
                if (category == Category.custom) ...[
                  _label('Custom names (one per line)'),
                  Wrap(
                    spacing: Space.sm,
                    children: [
                      for (final e in _customPresets.entries)
                        ActionChip(
                          label: Text('Use ${e.key}'),
                          onPressed: () =>
                              setState(() => _custom.text = e.value.join('\n')),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: _custom,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'Names, cities, celebrities…',
                    ),
                  ),
                ],
                _label('Difficulty'),
                SegmentedButton<Difficulty>(
                  segments: [
                    for (final d in Difficulty.values)
                      ButtonSegment(
                        value: d,
                        label: Text(difficultyLabels[d]!),
                      ),
                  ],
                  selected: {difficulty},
                  onSelectionChanged: (v) => setState(() {
                    difficulty = v.first;
                    turnSeconds =
                        GameSettings.difficultyTurnSeconds[difficulty]!;
                  }),
                ),
                const SizedBox(height: Space.xs),
                Text(switch (difficulty) {
                  Difficulty.easy =>
                    'Well-known titles and a relaxed 30s timer.',
                  Difficulty.normal =>
                    'Well-known plus recent titles, 20s timer.',
                  Difficulty.challenging =>
                    'The full catalogue and a quick 10s timer.',
                }, style: TextStyle(color: c.muted, fontSize: 13)),
                _label('Turn timer'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final t in GameSettings.turnOptions)
                      ChoiceChip(
                        label: Text(timerLabel(t)),
                        selected: turnSeconds == t,
                        onSelected: (_) => setState(() => turnSeconds = t),
                      ),
                  ],
                ),
                _label('If the table plays for a late player'),
                RadioGroup<TimeoutPolicy>(
                  groupValue: policy,
                  onChanged: (v) => setState(() => policy = v!),
                  child: const Column(
                    children: [
                      RadioListTile(
                        contentPadding: EdgeInsets.zero,
                        value: TimeoutPolicy.passIncoming,
                        title: Text('Pass the slip I just received'),
                      ),
                      RadioListTile(
                        contentPadding: EdgeInsets.zero,
                        value: TimeoutPolicy.passRandom,
                        title: Text('Pass a random slip'),
                      ),
                    ],
                  ),
                ),
                _label('Rounds'),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final r in GameSettings.roundOptions)
                      ChoiceChip(
                        label: Text('$r'),
                        selected: rounds == r,
                        onSelected: (_) => setState(() {
                          rounds = r;
                          _roundsCtl.text = '$r';
                        }),
                      ),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _roundsCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Custom',
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n >= 1 && n <= 30) {
                            setState(() => rounds = n);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                _label('Movie win points: $winPoints'),
                Slider(
                  value: winPoints.toDouble(),
                  min: 500,
                  max: 3000,
                  divisions: 25,
                  label: '$winPoints',
                  onChanged: (v) => setState(() => winPoints = v.round()),
                ),
                _label('Special characters'),
                Text(
                  'Used from the top: a game with N players uses the first N−1. '
                  'You need at least one fewer than the number of players.',
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                const SizedBox(height: Space.sm),
                for (var i = 0; i < chars.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: chars[i].$1,
                            maxLength: 16,
                            decoration: InputDecoration(
                              isDense: true,
                              counterText: '',
                              labelText: 'Character ${i + 1}',
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: chars[i].$2,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Points',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove character',
                          onPressed: chars.length <= 2
                              ? null
                              : () => setState(() => chars.removeAt(i)),
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                      ],
                    ),
                  ),
                if (chars.length < 9)
                  TextButton.icon(
                    onPressed: () => setState(
                      () => chars.add((
                        TextEditingController(),
                        TextEditingController(text: '100'),
                      )),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add character'),
                  ),
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.xl,
              Space.sm,
              Space.xl,
              Space.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              width: double.infinity,
              child: ListenableBuilder(
                listenable: widget.ctrl,
                builder: (_, _) => BigButton(
                  label: 'Save settings',
                  busy: widget.ctrl.busy,
                  onPressed: _save,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
