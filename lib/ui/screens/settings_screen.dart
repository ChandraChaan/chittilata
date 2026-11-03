import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/festivals.dart';
import '../widgets/common.dart';

/// Only builds made with --dart-define=CRASH_TEST=true show the test-crash
/// button used to verify Crashlytics end to end.
const _crashTestBuild = bool.fromEnvironment('CRASH_TEST');

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = Services.of(context).prefs;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      extendBodyBehindAppBar: true,
      body: GameBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: prefs,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up_rounded),
                        title: const Text('Sound effects'),
                        value: prefs.sound,
                        onChanged: withClickValue(
                          context,
                          (v) => prefs.sound = v,
                        ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.music_note_rounded),
                        title: const Text('Music'),
                        subtitle: const Text('Menu theme and in-game music'),
                        value: prefs.music,
                        onChanged: withClickValue(
                          context,
                          (v) => prefs.music = v,
                        ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_rounded),
                        title: const Text('Notifications'),
                        subtitle: const Text(
                          'Your turn and nudges, when the app is closed',
                        ),
                        value: prefs.notifications,
                        onChanged: withClickValue(context, (v) {
                          final push = Services.read(context).push;
                          push == null
                              ? prefs.notifications = v
                              : push.setEnabled(v);
                        }),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.vibration_rounded),
                        title: const Text('Vibration'),
                        value: prefs.haptics,
                        onChanged: withClickValue(
                          context,
                          (v) => prefs.haptics = v,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Theme',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: Space.sm),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'dark', label: Text('Night')),
                          ButtonSegment(value: 'light', label: Text('Day')),
                          ButtonSegment(value: 'system', label: Text('System')),
                        ],
                        selected: {prefs.themeMode},
                        onSelectionChanged: withClickValue(
                          context,
                          (s) => prefs.themeMode = s.first,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Festival theme',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Auto decorates the app around Sankranti, Ugadi '
                        'and Diwali.',
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                      const SizedBox(height: Space.sm),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (value, label) in [
                            ('auto', 'Auto'),
                            ('off', 'Off'),
                            for (final f in Festival.values)
                              (f.name, '${f.emoji} ${f.label}'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: prefs.festival == value,
                              onSelected: withClickValue(
                                context,
                                (_) => prefs.festival = value,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),
                if (_crashTestBuild) ...[
                  OutlinedButton(
                    onPressed: () => FirebaseCrashlytics.instance.crash(),
                    child: const Text('Send test crash (verification build)'),
                  ),
                  OutlinedButton(
                    onPressed: () =>
                        throw StateError('Crashlytics verification (Dart)'),
                    child: const Text('Throw test Dart error'),
                  ),
                  const SizedBox(height: Space.lg),
                ],
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'About',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Chittilata – ChitPlay brings the traditional Telugu '
                        'paper-chit games (చిట్టిలాట, Chittilu Aata) to every '
                        'phone, in English for everyone at the table. Movie '
                        'titles are used only as game words. Sounds are '
                        'original and made for this app.\n\n'
                        'Animations follow your system "remove animations" '
                        'setting.',
                        style: TextStyle(color: c.muted, height: 1.4),
                      ),
                      const SizedBox(height: Space.sm),
                      // So players can tell which build they have installed.
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snap) {
                          final info = snap.data;
                          return Text(
                            info == null
                                ? ''
                                : 'Version ${info.version} (${info.buildNumber})',
                            style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
