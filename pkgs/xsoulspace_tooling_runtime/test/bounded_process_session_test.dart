@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  for (final closePipes in [false, true]) {
    test(
      'deadline owns descendants after root exits closePipes=$closePipes',
      () async {
        final redirect = closePipes ? '>/dev/null 2>&1' : '';
        final result = await runBounded(
          'sh',
          ['-c', 'sleep 30 $redirect & echo \$!; exit 0'],
          deadline: const Duration(milliseconds: 300),
          grace: const Duration(milliseconds: 300),
        );
        final child = int.parse(result.stdout.trim());
        expect(result.exitCode, 0, reason: 'the root exited normally');
        expect(result.cause, BoundedProcessCause.killedOnDeadline);
        expect(result.ok, isFalse);
        // Group signalling includes children forked after the pre-signal
        // snapshot; physical death is checked independently of that trace.
        expect(
          (await Process.run('kill', ['-0', '$child'])).exitCode,
          isNot(0),
        );
        expect(result.signaledPids, isNotEmpty);
        expect(result.survivors, isEmpty);
        expect(result.settlementProblem, isNull);
        expect(
          (await Process.run('kill', ['-0', '$child'])).exitCode,
          isNot(0),
        );
      },
      skip: Platform.isWindows ? 'POSIX session ownership' : null,
    );
  }

  test(
    'external cancellation after root exit preserves unrelated process',
    () async {
      final unrelated = await Process.start('sleep', ['30']);
      addTearDown(() async {
        unrelated.kill();
        await unrelated.exitCode;
      });
      final started = Completer<int>();
      final running = runBounded(
        'sh',
        ['-c', r'sleep 30 & echo $!; exit 0'],
        deadline: const Duration(seconds: 20),
        onStarted: started.complete,
      );
      final root = await started.future;
      // Observe actual root death rather than treating a delay as settlement.
      while ((await Process.run('kill', ['-0', '$root'])).exitCode == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final stopped = await stopProcessTree(
        root,
        grace: const Duration(milliseconds: 300),
      );
      final result = await running;
      final child = int.parse(result.stdout.trim());
      expect(stopped, contains(child));
      expect(result.cause, BoundedProcessCause.signaled);
      expect(result.ok, isFalse);
      expect(result.survivors, isEmpty);
      expect(result.settlementProblem, isNull);
      expect((await Process.run('kill', ['-0', '$child'])).exitCode, isNot(0));
      expect(
        (await Process.run('kill', ['-0', '${unrelated.pid}'])).exitCode,
        0,
      );
    },
    skip: Platform.isWindows ? 'POSIX session ownership' : null,
  );

  test('session handshake does not alter target argv or stderr', () async {
    final result = await runBounded('/bin/sh', [
      '-c',
      r'printf "%s" "$1"; printf "%s" "$2" >&2',
      'argv0',
      r'quoted $value with spaces',
      'stderr-tail',
    ], deadline: const Duration(seconds: 10));
    expect(result.ok, isTrue);
    expect(result.stdout, r'quoted $value with spaces');
    expect(result.stderr, 'stderr-tail');
  }, skip: Platform.isWindows ? 'POSIX session ownership' : null);
}
