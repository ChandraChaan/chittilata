import 'dart:math';

import 'package:chittilata/core/theme/app_theme.dart';
import 'package:chittilata/ui/widgets/chits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: the last chits on the table must respond anywhere on their
/// visible (tilted) paper, and never hand the tap to a neighbour or to an
/// invisible, already-picked chit.
void main() {
  for (final players in [3, 4, 6, 8, 10]) {
    for (final size in const [Size(360, 420), Size(400, 520), Size(360, 300)]) {
      testWidgets('every free chit responds: $players players, '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final ids = [for (var i = 0; i < players * 4; i++) 'c$i'];
        final picks = <String, String>{};
        final rnd = Random(players);
        // Others have picked most chits; I picked 2; 5 remain free.
        final shuffled = [...ids]..shuffle(rnd);
        for (var i = 0; i < ids.length - 5; i++) {
          picks[shuffled[i]] = i < 2 ? 'me' : 'p${i % (players - 1)}';
        }
        String? tapped;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: ChitTable(
                    seed: 'room-r$players',
                    ids: ids,
                    picks: picks,
                    myUid: 'me',
                    players: {
                      'me': 'Me',
                      for (var p = 0; p < players - 1; p++) 'p$p': 'P$p',
                    },
                    pending: const {},
                    canPick: true,
                    onPick: (id) => tapped = id,
                    ceremonyLabels: const ['A'],
                    opensAt: null,
                    now: DateTime.now,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final table = tester.getTopLeft(find.byType(ChitTable));
        final w = size.width;
        final matH = max(80.0, size.height - 64);
        final spots = chitLayout('room-r$players', ids, w / matH);
        final cols = max(1, sqrt(ids.length * w / matH).ceil());
        final chitW = (w / cols * 0.7).clamp(40.0, 84.0);
        final chitH = chitW * 0.72;
        final free = shuffled.skip(ids.length - 5).toSet();
        // Which free chit is visually on top at a point (paint order = ids order).
        String? visibleAt(Offset g) {
          String? top;
          for (final id in ids.where(free.contains)) {
            final s = spots[id]!;
            final c = chitCentre(s, w, 64, matH, chitW);
            final d = g - c;
            final lx = d.dx * cos(-s.angle) - d.dy * sin(-s.angle);
            final ly = d.dx * sin(-s.angle) + d.dy * cos(-s.angle);
            if (lx.abs() <= chitW / 2 && ly.abs() <= chitH / 2) top = id;
          }
          return top;
        }

        var probes = 0;
        final dead = <String>[];
        final wrong = <String>[];
        for (final id in free) {
          final s = spots[id]!;
          final c = chitCentre(s, w, 64, matH, chitW);
          for (final u in [-0.42, 0.0, 0.42]) {
            for (final v in [-0.4, 0.0, 0.4]) {
              final lx = u * chitW, ly = v * chitH;
              final g =
                  c +
                  Offset(
                    lx * cos(s.angle) - ly * sin(s.angle),
                    lx * sin(s.angle) + ly * cos(s.angle),
                  );
              final expectId = visibleAt(g);
              if (expectId != id) continue; // covered by another chit
              expect(
                g.dx >= 0 && g.dx <= w && g.dy >= 0 && g.dy <= size.height,
                isTrue,
                reason: '$id pokes off the table at $g',
              );
              probes++;
              tapped = null;
              await tester.tapAt(table + g);
              await tester.pump();
              if (tapped == null) {
                dead.add('$id($u,$v)');
              } else if (tapped != id) {
                wrong.add('$id($u,$v)->$tapped');
              }
            }
          }
        }
        expect(probes, greaterThan(30));
        expect(dead, isEmpty, reason: 'taps that picked nothing');
        expect(wrong, isEmpty, reason: 'taps that picked another chit');
      });
    }
  }

  testWidgets('a tap just beside a chit still picks it', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 420,
              child: ChitTable(
                seed: 'near',
                ids: const ['a', 'b', 'c', 'd'],
                picks: const {'b': 'p1', 'c': 'p1', 'd': 'p1'},
                myUid: 'me',
                players: const {'me': 'Me', 'p1': 'P1'},
                pending: const {},
                canPick: true,
                onPick: (id) => tapped = id,
                ceremonyLabels: const ['A'],
                opensAt: null,
                now: DateTime.now,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final matH = 420.0 - 64;
    final s = chitLayout('near', const ['a', 'b', 'c', 'd'], 360 / matH)['a']!;
    final chitW = (360 / 2 * 0.7).clamp(40.0, 84.0);
    final centre =
        tester.getTopLeft(find.byType(ChitTable)) +
        chitCentre(s, 360, 64, matH, chitW);
    await tester.tapAt(centre + Offset(0, chitW * 0.75));
    await tester.pump();
    expect(tapped, 'a');
  });
}
