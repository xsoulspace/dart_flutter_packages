import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

void main() {
  test(
    'duplex replies before EOF; owner close awaits physical settlement',
    () async {
      final ready = Completer<BoundedDuplexHandle>();
      final run = runBounded(
        '/usr/bin/perl',
        ['-e', r'$|=1; while(<STDIN>){print "ack:$_"} sleep 20;'],
        deadline: const Duration(seconds: 4),
        grace: const Duration(milliseconds: 150),
        singleProcessSession: true,
        onDuplexReady: ready.complete,
      );
      final handle = await ready.future;
      final frame = handle.output.first;
      await handle.send(utf8.encode('hello\n'));
      expect(utf8.decode(await frame), 'ack:hello\n');
      final disposed = await handle.close();
      expect(identical(disposed, await run), isTrue);
      expect(disposed.cause, BoundedProcessCause.stoppedByOwner);
      expect(disposed.physicallySettled, isTrue);
    },
  );

  test('incomplete frame is refused and process physically settles', () async {
    final result = await runBounded(
      '/usr/bin/perl',
      ['-e', r'print "partial";'],
      deadline: const Duration(seconds: 3),
      grace: const Duration(milliseconds: 150),
      onDuplexReady: (_) {},
    );
    expect(result.transportProblem, 'duplex_incomplete_frame');
    expect(result.physicallySettled, isTrue);
    expect(result.ok, isFalse);
  });

  test(
    'oversized unterminated frame stops service without unbounded parsing',
    () async {
      final result = await runBounded(
        '/usr/bin/perl',
        ['-e', r'$|=1; print "x" x 4096; sleep 20;'],
        deadline: const Duration(seconds: 3),
        grace: const Duration(milliseconds: 150),
        duplexLimits: const BoundedDuplexLimits(maxFrameBytes: 64),
        onDuplexReady: (_) {},
      );
      expect(result.transportProblem, 'duplex_frame_budget_exceeded');
      expect(result.cause, BoundedProcessCause.stoppedByOwner);
      expect(result.physicallySettled, isTrue);
    },
  );

  test('unconsumed complete frames have bounded backlog', () async {
    final result = await runBounded(
      '/usr/bin/perl',
      ['-e', r'$|=1; print "x\n" x 100; sleep 20;'],
      deadline: const Duration(seconds: 3),
      grace: const Duration(milliseconds: 150),
      duplexLimits: const BoundedDuplexLimits(maxQueuedFrames: 2),
      onDuplexReady: (_) {},
    );
    expect(result.transportProblem, 'duplex_frame_backlog_exceeded');
    expect(result.physicallySettled, isTrue);
  });

  test('write count refuses more packets and still settles', () async {
    final ready = Completer<BoundedDuplexHandle>();
    final run = runBounded(
      '/usr/bin/perl',
      ['-e', r'while(<STDIN>){} sleep 20;'],
      deadline: const Duration(seconds: 3),
      grace: const Duration(milliseconds: 150),
      duplexLimits: const BoundedDuplexLimits(maxWrites: 1),
      onDuplexReady: ready.complete,
    );
    final handle = await ready.future;
    await handle.send(utf8.encode('one\n'));
    await expectLater(handle.send(utf8.encode('two\n')), throwsStateError);
    final result = await run;
    expect(result.transportProblem, 'duplex_input_budget_exceeded');
    expect(result.physicallySettled, isTrue);
  });

  test(
    'service deadline applies with stdin open and no cooperative EOF',
    () async {
      final result = await runBounded(
        '/usr/bin/perl',
        ['-e', 'sleep 20;'],
        deadline: const Duration(milliseconds: 300),
        grace: const Duration(milliseconds: 150),
        onDuplexReady: (_) {},
      );
      expect(result.cause, BoundedProcessCause.killedOnDeadline);
      expect(result.physicallySettled, isTrue);
    },
  );
}
