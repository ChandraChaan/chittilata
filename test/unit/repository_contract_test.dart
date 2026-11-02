import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The top crash in 2.0.0: a `Future<void>` method returned `_call(...)`
  // (really a `Future<Map>`), so `.catchError((_) {})` threw whenever the
  // call failed. Fire-and-forget calls must go through `_run`.
  test('Future<void> repository methods never return _call() directly', () {
    final src = File('lib/data/game_repository.dart').readAsStringSync();
    final offenders = <String>[];
    for (final m in RegExp(
      r'Future<void>\s+(\w+)\([^)]*\)\s*=>\s*_call\(',
      dotAll: true,
    ).allMatches(src)) {
      offenders.add(m.group(1)!);
    }
    expect(offenders, isEmpty);
    expect(src, contains('Future<void> _run('));
  });

  test(
    'a failed Future<void> from an async wrapper can be caught with {}',
    () async {
      Future<Map<String, dynamic>> call() async =>
          throw StateError('lost race');
      Future<void> run() async {
        await call();
      }

      var caught = false;
      await run().catchError((_) {
        caught = true;
      });
      expect(caught, isTrue);
    },
  );

  test('the 2.0.0 pattern really throws (why _run exists)', () async {
    Future<Map<String, dynamic>> call() async => throw StateError('lost race');
    // ignore: unnecessary_lambdas
    Future<void> old() => call();

    Object? error;
    try {
      await old().catchError((_) {});
    } catch (e) {
      error = e;
    }
    expect(error, isA<ArgumentError>());
  });
}
