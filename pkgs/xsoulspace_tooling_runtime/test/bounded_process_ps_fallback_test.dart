@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  test('stopOwnedGroup refuses without a live owned registration', () async {
    expect(await stopOwnedGroup(999999999), isEmpty);
  });

  group('owned group ps observation fallback', () {
    test(
      'ps failure after snapshot uses fallback SIGKILL while root is stopped',
      () async {
        var reads = 0;
        boundedProcessGroupRowsOverride = () async {
          reads++;
          if (reads <= 2) return probeBoundedProcessGroupRows();
          return null;
        };

        final directory = Directory.systemTemp.createTempSync('ps-fallback-');
        final started = Completer<int>();
        final running = runBounded(
          'sh',
          [
            '-c',
            r'exec >/dev/null 2>&1; trap "" TERM; sleep 30 & echo $! > member.pid; sleep 30; wait',
          ],
          workingDirectory: directory.path,
          deadline: const Duration(milliseconds: 600),
          grace: const Duration(milliseconds: 400),
          onStarted: started.complete,
        );
        final root = await started.future;
        addTearDown(() async {
          boundedProcessGroupRowsOverride = null;
          final member = File('${directory.path}/member.pid');
          if (member.existsSync()) {
            try {
              await Process.run('kill', [
                '-CONT',
                member.readAsStringSync().trim(),
              ]);
            } on Object {
              // Member may already be dead after SIGKILL.
            }
          }
          await stopProcessTree(root, grace: const Duration(seconds: 2));
          directory.deleteSync(recursive: true);
        });

        await Future<void>.delayed(const Duration(milliseconds: 150));
        final memberPid = int.parse(
          File('${directory.path}/member.pid').readAsStringSync().trim(),
        );
        expect((await Process.run('kill', ['-STOP', '$memberPid'])).exitCode, 0);

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
      },
      skip: Platform.isWindows ? 'POSIX session ownership' : null,
    );

    test(
      'cleared snapshot: empty ps observation then ps failure (ADR 0066)',
      () async {
        final directory = Directory.systemTemp.createTempSync('ps-cleared-');
        final started = Completer<int>();
        final running = runBounded(
          'sh',
          [
            '-c',
            r'sleep 30 & echo $! > member.pid; sleep 30; wait',
          ],
          workingDirectory: directory.path,
          deadline: const Duration(seconds: 30),
          grace: const Duration(milliseconds: 200),
          onStarted: started.complete,
        );
        final root = await started.future;
        addTearDown(() async {
          boundedProcessGroupRowsOverride = null;
          final member = File('${directory.path}/member.pid');
          if (member.existsSync()) {
            await Process.run('kill', [
              '-CONT',
              member.readAsStringSync().trim(),
            ]);
          }
          await stopProcessTree(root, grace: const Duration(seconds: 1));
          await running;
          directory.deleteSync(recursive: true);
        });

        final memberPid = int.parse(
          File('${directory.path}/member.pid').readAsStringSync().trim(),
        );
        expect((await Process.run('kill', ['-STOP', '$memberPid'])).exitCode, 0);

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
      },
      skip: Platform.isWindows ? 'POSIX session ownership' : null,
    );
  });
}
