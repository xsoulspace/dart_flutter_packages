@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

/// Mirrors harness `process_settlement_test` driver: owned session, ps fails
/// after enumerating the target tree, TERM-ignoring shell with a sleep child.
void main() {
  test(
    'ps outage after snapshot still deadline-kills retained group members',
    () async {
      var armed = false;
      var reads = 0;
      boundedProcessGroupRowsOverride = () async {
        if (!armed) return probeBoundedProcessGroupRows();
        reads++;
        if (reads <= 2) return probeBoundedProcessGroupRows();
        return null;
      };

      final started = Completer<int>();
      final running = runBounded(
        '/bin/sh',
        [
          '-c',
          r'''trap '' TERM
sleep 30 &
printf '%s\n%s\n' "$$" "$!" > /dev/null
wait''',
        ],
        deadline: const Duration(seconds: 1),
        grace: const Duration(milliseconds: 100),
        onStarted: (pid) {
          armed = true;
          reads = 0;
          started.complete(pid);
        },
      );
      final root = await started.future;
      final result = await running;

      expect(result.signaledPids, isNotEmpty);
      expect(result.settlementProblem, 'owned session observation unavailable');

      for (final pid in result.signaledPids) {
        expect(
          (await Process.run('kill', ['-0', '$pid'])).exitCode,
          isNot(0),
          reason: 'deadline must physically kill signaled pid $pid',
        );
      }

      boundedProcessGroupRowsOverride = null;
      await stopProcessTree(root, grace: const Duration(seconds: 1));
      await running;
    },
    skip: Platform.isWindows ? 'POSIX session ownership' : null,
  );
}
