@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  test('start observation permits real external tree cancellation', () async {
    final started = Completer<int>();
    final running = runBounded(
      'sh',
      ['-c', 'sleep 30'],
      deadline: const Duration(seconds: 20),
      onStarted: started.complete,
    );
    final pid = await started.future;
    final stopped = await stopProcessTree(pid);
    await awaitProcessSettlement(stopped);
    final result = await running;
    expect(result.pid, pid);
    expect(result.cause, BoundedProcessCause.signaled);
    expect(result.survivors, isEmpty);
    for (final child in stopped) {
      expect((await Process.run('kill', ['-0', '$child'])).exitCode, isNot(0));
    }
  }, skip: Platform.isWindows ? 'POSIX process-tree control' : null);

  for (final asynchronous in [false, true]) {
    test(
      'observer failure preserves deadline ownership async=$asynchronous',
      () async {
        final result = await runBounded(
          'sh',
          ['-c', 'sleep 30'],
          deadline: const Duration(milliseconds: 250),
          grace: const Duration(milliseconds: 250),
          onStarted: (_) {
            if (asynchronous) {
              return Future<void>.error(StateError('observer failure'));
            }
            throw StateError('observer failure');
          },
        );
        expect(result.cause, BoundedProcessCause.killedOnDeadline);
        expect(result.signaledPids, isNotEmpty);
        expect(result.survivors, isEmpty);
        for (final child in result.signaledPids) {
          expect(
            (await Process.run('kill', ['-0', '$child'])).exitCode,
            isNot(0),
          );
        }
      },
      skip: Platform.isWindows ? 'POSIX process-tree control' : null,
    );
  }

  test('failed spawn never observes a PID', () async {
    var observed = false;
    final result = await runBounded(
      'missing-deferred-observer-fixture-binary',
      [],
      deadline: const Duration(seconds: 1),
      onStarted: (_) => observed = true,
    );
    expect(result.cause, BoundedProcessCause.spawnFailed);
    expect(observed, isFalse);
  });
}
