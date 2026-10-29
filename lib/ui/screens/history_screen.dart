import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/common.dart';

/// Finished games saved on this device.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final history = Services.of(context).prefs.history;
    return Scaffold(
      appBar: AppBar(title: const Text('Match history')),
      extendBodyBehindAppBar: true,
      body: GameBackground(
        child: SafeArea(
          child: history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 64,
                          color: c.muted,
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'No finished games yet',
                          style: context.text.titleMedium,
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          'Games you finish will appear here.',
                          style: TextStyle(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(Space.lg),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) {
                    final h = history[i];
                    final d = h.playedAt;
                    final king = h.standings
                        .where((s) => s['title'] == 'King')
                        .map((s) => s['name'])
                        .join(' & ');
                    return Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                color: c.marigold,
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Text(
                                  'King: $king',
                                  style: context.text.titleMedium,
                                ),
                              ),
                              Text(
                                '${d.day} ${_months[d.month - 1]}',
                                style: TextStyle(color: c.muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            '${h.rounds} rounds · ${h.category}',
                            style: TextStyle(color: c.muted, fontSize: 13),
                          ),
                          const Divider(height: Space.xl),
                          for (final s in h.standings)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '#${s['rank']}',
                                      style: TextStyle(color: c.muted),
                                    ),
                                  ),
                                  Expanded(child: Text('${s['name']}')),
                                  Text(
                                    '${s['total']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
