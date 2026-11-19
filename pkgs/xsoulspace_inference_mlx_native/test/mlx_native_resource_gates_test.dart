import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The resource gates (ADR 0059 hardening, 2026-11-14): the memory
/// parser pins recorded sensor output, the load gate refuses on the
/// incident floor and allows on unknown facts, and the lane bounds how
/// many requests a caller may pile onto one engine.
void main() {
  group('MemoryFacts.parse', () {
    // Recorded verbatim from the owner's 16GB machine (2026-11-18,
    // v3.3 calibration) — the MODERN vm_stat rows: the decomposition
    // that matches Activity Monitor to the decimal (Cached Files =
    // File-backed pages; App + Wired + Compressed = Anonymous + wired
    // down + compressor-occupied).
    const modernVmStat = '''
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                    42571.
Pages active:                                 218502.
Pages inactive:                               212484.
Pages speculative:                              4907.
Pages throttled:                                   0.
Pages wired down:                             192432.
Pages purgeable:                               10372.
File-backed pages:                            113546.
Anonymous pages:                              322347.
Pages occupied by compressor:                 342053.
''';
    test('pins the calibrated Activity-Monitor decomposition', () {
      final facts = MemoryFacts.parse(
        vmStat: modernVmStat,
        memSize: 'hw.memsize: 17179869184',
        swap: 'total = 8192.00M  used = 7401.81M  free = 790.19M  (encrypted)',
      );
      expect(facts, isNotNull);
      // (42571 free + 4907 speculative) x 16384 bytes, floored: 741.
      expect(facts!.freeMegabytes, 741);
      // File-backed pages: 113546 x 16384, floored: 1774 — the owner's
      // screenshot showed this bucket as "Cached Files 2.01 GB".
      expect(facts.cachedMegabytes, 1774);
      // Anonymous (322347) + wired (192432) + compressor-occupied
      // (342053) x 16384, floored: 13388 — Activity Monitor's App +
      // Wired + Compressed working set.
      expect(facts.usedMegabytes, 13388);
      expect(facts.compressorMegabytes, 5344);
      // The gate basis: reclaimable cache + free = 1774 + 741.
      expect(facts.availableMegabytes, 2515);
      expect(facts.swapUsedMegabytes, 7402);
      expect(facts.totalMegabytes, 16384);
    });

    // Recorded verbatim from the incident machine (16GB, freshly
    // booted, 2026-11-14): a vm_stat WITHOUT the modern anonymous /
    // file-backed rows — the legacy fallback (free + inactive +
    // speculative + purgeable), so old sensors keep working.
    const vmStat = '''
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                    71332.
Pages active:                                 272969.
Pages inactive:                               269705.
Pages speculative:                              2538.
Pages throttled:                                   0.
Pages wired down:                             115792.
Pages purgeable:                                6765.
"Translation faults":                       27368063.
Pages copy-on-write:                          903969.
''';
    test('pins the legacy fallback (no anonymous/file-backed rows)', () {
      final facts = MemoryFacts.parse(
        vmStat: vmStat,
        memSize: 'hw.memsize: 17179869184',
      );
      expect(facts, isNotNull);
      // (71332 + 2538) x 16384 bytes, floored: 1154.
      expect(facts!.freeMegabytes, 1154);
      // (71332 + 269705 + 2538 + 6765) x 16384 bytes, one floor: 5474.
      expect(facts.availableMegabytes, 5474);
      expect(facts.usedMegabytes, isNull);
      expect(facts.cachedMegabytes, isNull);
      expect(facts.totalMegabytes, 16384);
    });

    test('parses without a total (vm_stat only)', () {
      final facts = MemoryFacts.parse(vmStat: vmStat);
      expect(facts, isNotNull);
      expect(facts!.totalMegabytes, isNull);
    });

    test('absent sensor output yields null, never throws', () {
      expect(MemoryFacts.parse(vmStat: ''), isNull);
      expect(MemoryFacts.parse(), isNull);
    });

    test('the Intel page size parses too', () {
      final facts = MemoryFacts.parse(
        vmStat:
            'Mach Virtual Memory Statistics: (page size of 4096 bytes)\n'
            'Pages free:                                 4096.\n',
      );
      expect(facts!.freeMegabytes, 16);
      expect(facts.availableMegabytes, 16);
    });
  });

  group('MlxLoadGate.evaluate', () {
    test('refuses below the floor with the numbers attached', () async {
      final gate = MlxLoadGate(
        minFreeMegabytes: 4096,
        readMemory: () async => const MemoryFacts(
          availableMegabytes: 1024,
          freeMegabytes: 64,
          totalMegabytes: 16384,
        ),
      );
      final refusal = await gate.evaluate();
      expect(refusal, isNotNull);
      expect(refusal!.requiredAvailableMegabytes, 4096);
      expect(refusal.availableMegabytes, 1024);
      expect('$refusal', contains('4096'));
    });

    test('allows at and above the floor', () async {
      final gate = MlxLoadGate(
        minFreeMegabytes: 4096,
        readMemory: () async => const MemoryFacts(
          availableMegabytes: 4096,
          freeMegabytes: 1024,
          totalMegabytes: 16384,
        ),
      );
      expect(await gate.evaluate(), isNull);
    });

    test('unknown facts allow (the sensor never blocks a healthy machine)',
        () async {
      final gate = MlxLoadGate(
        minFreeMegabytes: 4096,
        readMemory: () async => null,
      );
      expect(await gate.evaluate(), isNull);
    });
  });

  group('MxlLane', () {
    test('runs jobs serially in arrival order', () async {
      final lane = MxlLane(maxLaneDepth: 3);
      final log = <int>[];
      final release = Completer<void>();
      Future<int> job(int id, {Completer<void>? gate}) => lane.run(() async {
        log.add(id);
        if (gate != null) await gate.future;
        return id * 10;
      });
      final first = job(1, gate: release);
      final second = job(2);
      final third = job(3);
      // The lane starts each job one microtask after the previous
      // completes; let the first actually begin.
      await Future<void>.delayed(Duration.zero);
      expect(log, <int>[1], reason: 'only the running job has started');
      release.complete();
      expect(await first, 10);
      expect(await second, 20);
      expect(await third, 30);
      expect(log, <int>[1, 2, 3], reason: 'serial order holds');
    });

    test('refuses beyond the lane depth with the depth attached', () async {
      final lane = MxlLane(maxLaneDepth: 2);
      final release = Completer<void>();
      final held = <Future<int>>[
        lane.run(() async {
          await release.future;
          return 1;
        }),
        lane.run(() async => 2),
      ];
      MxlLaneBusy? busy;
      try {
        await lane.run(() async => 3);
      } on MxlLaneBusy catch (error) {
        busy = error;
      }
      expect(busy, isNotNull, reason: 'the third request is refused NOW');
      expect(busy!.laneDepth, 2);
      expect('$busy', contains('2 request(s)'));
      release.complete();
      await Future.wait(held);
    });

    test('a failing job releases its lane slot and propagates', () async {
      final lane = MxlLane(maxLaneDepth: 1);
      await expectLater(
        lane.run<int>(() async => throw StateError('decode failed')),
        throwsStateError,
      );
      expect(lane.laneDepth, 0, reason: 'the failure released the slot');
      final result = await lane.run(() async => 'recovered');
      expect(result, 'recovered');
    });
  });
}
