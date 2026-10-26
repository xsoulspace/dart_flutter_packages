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
      'ps failure after snapshot uses fallback SIGKILL while root is stopped',
      () async {
        var reads = 0;
        boundedProcessGroupRowsOverride = () async {
          reads++;
          if (reads <= 2) return probeBoundedProcessGroupRows();
          return null;
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
            started.complete(pid);
          },
        );
        final root = await started.future;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(
          (await Process.run('kill', ['-STOP', '$root'])).exitCode,
          0,
        );

        final result = await running;
        expect(result.exitCode, -9);
        expect(result.signaledPids, isNotEmpty);
        for (final pid in result.signaledPids) {
          expect(
            (await Process.run('kill', ['-0', '$pid'])).exitCode,
            isNot(0),
            reason: 'fallback must physically kill signaled pid $pid',
          );
        }

        boundedProcessGroupRowsOverride = null;
        try {
          await Process.run('kill', ['-CONT', '$root']);
        } on Object {
          // Root may already be dead after SIGKILL.
        }
        await stopProcessTree(root, grace: const Duration(seconds: 2));
      },
      skip: Platform.isWindows ? 'POSIX session ownership' : null,
    );

    test(
      'cleared snapshot: empty ps observation then ps failure (ADR 0066)',
      () async {
        final started = Completer<int>();
        final running = runBounded(
          'sh',
          ['-c', r'sleep 30'],
          deadline: const Duration(seconds: 30),
          grace: const Duration(milliseconds: 200),
          onStarted: started.complete,
        );
        final root = await started.future;
        expect(
          (await Process.run('kill', ['-STOP', '$root'])).exitCode,
          0,
        );

        // Reads 1-2 must hit owned-group observation during stop, not the
        // pre-spawn `runBounded` probe that shares this override hook.
        var reads = 0;
        boundedProcessGroupRowsOverride = () async {
          reads++;
          if (reads <= 2) return probeBoundedProcessGroupRows();
          if (reads == 3) return <(int, int, int, String)>[];
          return null;
        };

        final first = await stopProcessTree(
          root,
          grace: const Duration(milliseconds: 100),
        );
        expect(first, isNotEmpty);

        final second = await stopProcessTree(
          root,
          grace: const Duration(milliseconds: 100),
        );
        expect(second, isEmpty);
        expect(
          (await Process.run('kill', ['-0', '$root'])).exitCode,
          0,
          reason: 'stopped root must remain alive until cleanup',
        );

        boundedProcessGroupRowsOverride = null;
        await Process.run('kill', ['-CONT', '$root']);
        await stopProcessTree(root, grace: const Duration(seconds: 1));
        await running;
      },
      skip: Platform.isWindows ? 'POSIX session ownership' : null,
    );
  });
}
