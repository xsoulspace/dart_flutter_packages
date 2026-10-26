// ignore_for_file: lines_longer_than_80_chars

/// Unit gates for the bounded-run helper (the orphan-vector fix): a run
/// that hits its deadline stops the tree it spawned — and the result
/// PROVES it (signaled pids verified dead via `kill -0`), never a
/// synthetic timeout over a live child.
///
/// POSIX-only gates (`sh`, `kill`): skipped on Windows where the tree
/// probe degrades to the root pid (`taskkill /T` follow-up, named in
/// the module doc).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  group('runBounded', () {
    test(
      'clean exit: cause exited, output captured, nothing signaled',
      () async {
        final result = await runBounded('sh', [
          '-c',
          'echo bounded-ok; echo boom >&2; exit 0',
        ], deadline: const Duration(seconds: 30));
        expect(result.ok, isTrue);
        expect(result.cause, BoundedProcessCause.exited);
        expect(result.exitCode, 0);
        expect(result.stdout, contains('bounded-ok'));
        expect(result.stderr, contains('boom'));
        expect(result.signaledPids, isEmpty);
        expect(result.survivors, isEmpty);
      },
      skip: Platform.isWindows ? 'POSIX-only (sh)' : null,
    );

    test('failing exit: nonzero code and stderr surface verbatim', () async {
      final result = await runBounded('sh', [
        '-c',
        'echo the-failure >&2; exit 3',
      ], deadline: const Duration(seconds: 30));
      expect(result.ok, isFalse);
      expect(result.cause, BoundedProcessCause.exited);
      expect(result.exitCode, 3);
      expect(result.stderr, contains('the-failure'));
    }, skip: Platform.isWindows ? 'POSIX-only (sh)' : null);

    test('deadline kill: ZERO survivors — every signaled pid verified '
        'dead via kill -0', () async {
      final result = await runBounded('sh', [
        '-c',
        'sleep 30',
      ], deadline: const Duration(milliseconds: 400));
      expect(result.cause, BoundedProcessCause.killedOnDeadline);
      expect(result.ok, isFalse);
      expect(result.signaledPids, isNotEmpty);
      expect(
        result.survivors,
        isEmpty,
        reason: 'the tree must not outlive the ladder',
      );
      for (final pid in result.signaledPids) {
        final probe = await Process.run('kill', ['-0', '$pid']);
        expect(
          probe.exitCode,
          isNot(0),
          reason: 'pid $pid outlived the deadline ladder — an orphan',
        );
      }
    }, skip: Platform.isWindows ? 'POSIX-only (sh, kill)' : null);

    test(
      'a SIGTERM-ignoring child still dies: the KILL rung escalates',
      () async {
        final result = await runBounded(
          'sh',
          ['-c', 'trap "" TERM; sleep 30'],
          deadline: const Duration(milliseconds: 400),
          grace: const Duration(milliseconds: 700),
        );
        expect(result.cause, BoundedProcessCause.killedOnDeadline);
        expect(result.survivors, isEmpty);
        // The root itself is verified dead — TERM was ignored, KILL was not.
        final probe = await Process.run('kill', ['-0', '${result.pid}']);
        expect(
          probe.exitCode,
          isNot(0),
          reason: 'the TERM-ignoring root survived',
        );
      },
      skip: Platform.isWindows ? 'POSIX-only (sh, kill)' : null,
    );

    test('spawn failure is named data, never a thrown error', () async {
      final result = await runBounded(
        'definitely-not-a-binary-anywhere-oka',
        const [],
        deadline: const Duration(seconds: 5),
      );
      expect(result.cause, BoundedProcessCause.spawnFailed);
      expect(result.exitCode, -1);
      expect(result.spawnError, isNotNull);
      expect(result.ok, isFalse);
    });
  });

  group('stopProcessTree', () {
    test(
      'kills a spawned child-and-grandchild tree and verifies death',
      () async {
        final root = await Process.start('sh', [
          '-c',
          'sleep 30 & wait', // compound: sh STAYS alive under the sleep
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final signaled = await stopUnownedPosixProcessTree(root.pid);
        expect(signaled, contains(root.pid));
        expect(
          signaled.length,
          greaterThanOrEqualTo(2),
          reason: 'the sleep child was in the tree too',
        );
        for (final pid in signaled) {
          final probe = await Process.run('kill', ['-0', '$pid']);
          expect(
            probe.exitCode,
            isNot(0),
            reason: 'pid $pid survived the tree stop',
          );
        }
        root.kill();
      },
      skip: Platform.isWindows ? 'POSIX-only (sh, kill)' : null,
    );
  });
}
