@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  group('owned group ps observation fallback', () {
    tearDown(() {
      boundedProcessGroupRowsOverride = null;
    });

    test(
      'TERM-ignoring group: ps failure after observation uses snapshot while '
      'root lives, then settles when ps returns',
      () async {
        int? rootPid;
        Set<int>? observedAtLastLivePs;
        boundedProcessGroupRowsOverride = () async {
          if (rootPid != null) {
            final snap = boundedProcessObservedMembersForRoot(rootPid!);
            if (snap != null && snap.isNotEmpty) {
              observedAtLastLivePs = snap;
              return null;
            }
          }
          return probeBoundedProcessGroupRows();
        };

        final started = Completer<int>();
        final running = runBounded(
          'sh',
          [
            '-c',
            r'exec >/dev/null 2>&1; trap "" TERM; sleep 30 & sleep 30; wait',
          ],
          deadline: const Duration(milliseconds: 600),
          grace: const Duration(milliseconds: 400),
          onStarted: (pid) {
            rootPid = pid;
            started.complete(pid);
          },
        );
        final root = await started.future;
        final result = await running;

        expect(observedAtLastLivePs, isNotNull);
        expect(observedAtLastLivePs, isNotEmpty);

        expect(result.cause, BoundedProcessCause.killedOnDeadline);
        expect(
          result.settlementProblem,
          'owned session observation unavailable',
        );
        expect(result.survivors, isNotEmpty);
        expect(result.signaledPids.toSet(), observedAtLastLivePs);

        boundedProcessGroupRowsOverride = null;
        final cleanup = await stopProcessTree(
          root,
          grace: const Duration(seconds: 2),
        );
        expect(cleanup, isNotEmpty);
        for (final pid in result.survivors) {
          expect((await Process.run('kill', ['-0', '$pid'])).exitCode, isNot(0));
        }
      },
      skip: Platform.isWindows ? 'POSIX session ownership' : null,
    );

    test('empty ps observation then failure signals nothing', () async {
      var reads = 0;
      boundedProcessGroupRowsOverride = () async {
        reads++;
        if (reads == 1) return <(int, int, int, String)>[];
        return null;
      };

      final started = Completer<int>();
      final running = runBounded(
        'sh',
        ['-c', r'sleep 30'],
        deadline: const Duration(seconds: 30),
        grace: const Duration(milliseconds: 200),
        onStarted: started.complete,
      );
      final root = await started.future;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final signaled = await stopProcessTree(
        root,
        grace: const Duration(milliseconds: 100),
      );
      expect(signaled, isEmpty);
      boundedProcessGroupRowsOverride = null;
      await stopProcessTree(root, grace: const Duration(seconds: 1));
      await running;
    }, skip: Platform.isWindows ? 'POSIX session ownership' : null);
  });
}
