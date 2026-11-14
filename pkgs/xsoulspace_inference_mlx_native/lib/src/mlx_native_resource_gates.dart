/// Resource gates for the native engine host (ADR 0059 hardening,
/// 2026-11-14): the weight load refuses on a machine that cannot hold it,
/// the generation lane serializes with a bounded lane depth, and both
/// answer with typed, named refusals — never a hang, never a machine-wide
/// memory collapse.
///
/// The shape follows [PowerFacts] (ADR 0061): facts are sensed fresh, a
/// gate evaluates on the facts it can see, and a sensor failure degrades
/// to unknown-allow. A gate never lies about WHY it refused, and an
/// absent sensor never blocks a healthy machine.
library;

import 'dart:async';
import 'dart:io';

/// `{availableMegabytes, freeMegabytes, totalMegabytes}` — the load
/// gate's input facts.
///
/// [availableMegabytes] is the macOS-honest signal: free + inactive +
/// speculative + purgeable pages. `Pages free` alone is ALWAYS tiny on
/// macOS (the OS caches aggressively — a freshly booted 16GB machine
/// reports under 1GB free), so a free-only floor would refuse loads on
/// every healthy Mac.
///
/// Read fresh on every gate evaluation: available memory is exactly the
/// fact that changes between a refused retry and the one that passes,
/// so caching would hide the recovery. Sensor failure or non-macOS
/// degrades to null — the caller allows with a warning, never blocks a
/// machine it cannot see.
final class MemoryFacts {
  /// free + inactive + speculative + purgeable pages, in MB — what the
  /// OS could hand a new allocation without squeezing running apps.
  final int availableMegabytes;

  /// Barely-used free pages, in MB (the misleadingly-small raw number).
  final int freeMegabytes;

  /// Null when the total could not be sensed (the vm_stat path does not
  /// need it; `sysctl hw.memsize` fills it when available).
  final int? totalMegabytes;

  const MemoryFacts({
    required this.availableMegabytes,
    required this.freeMegabytes,
    this.totalMegabytes,
  });

  /// Reads the facts fresh. Non-macOS (or any sensor failure) yields
  /// null — never an exception.
  static Future<MemoryFacts?> current() async {
    if (!Platform.isMacOS) return null;
    String? vmStat;
    String? memSize;
    try {
      final r = await Process.run('vm_stat', const <String>[]);
      if (r.exitCode == 0) vmStat = r.stdout as String;
      final s = await Process.run('sysctl', const <String>['hw.memsize']);
      if (s.exitCode == 0) memSize = s.stdout as String;
    } on ProcessException {
      return null;
    }
    return MemoryFacts.parse(vmStat: vmStat, memSize: memSize);
  }

  /// Pure parser — pin-tested against recorded `vm_stat`/`sysctl`
  /// outputs. Returns null when the page accounting cannot be read.
  static MemoryFacts? parse({String? vmStat, String? memSize}) {
    final pages = vmStat ?? '';
    final pageSize = _parsePageSize(pages);
    if (pageSize == null) return null;
    final free = _parseLabeledPages(pages, 'Pages free:');
    if (free == null) return null;
    int mb(int pages) => (pages * pageSize) ~/ (1024 * 1024);
    final inactive = _parseLabeledPages(pages, 'Pages inactive:') ?? 0;
    final speculative = _parseLabeledPages(pages, 'Pages speculative:') ?? 0;
    final purgeable = _parseLabeledPages(pages, 'Pages purgeable:') ?? 0;
    final totalMb = _parseMemSize(memSize ?? '');
    return MemoryFacts(
      availableMegabytes: mb(free + inactive + speculative + purgeable),
      freeMegabytes: mb(free),
      totalMegabytes: totalMb,
    );
  }

  /// `page size of 16384 bytes` on Apple Silicon (4096 on Intel).
  static int? _parsePageSize(String vmStat) {
    final match = RegExp(r'page size of (\d+) bytes').firstMatch(vmStat);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// `Pages free:                              12345.` — the trailing
  /// dot is vm_stat's own punctuation.
  static int? _parseLabeledPages(String vmStat, String label) {
    for (final line in vmStat.split('\n')) {
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith(label)) continue;
      final value = trimmed
          .substring(label.length)
          .replaceAll('.', '')
          .replaceAll(',', '')
          .trim();
      return int.tryParse(value);
    }
    return null;
  }

  /// `hw.memsize: 17179869184` — reported in whole megabytes.
  static int? _parseMemSize(String memSize) {
    final match = RegExp(r'hw\.memsize:\s*(\d+)').firstMatch(memSize);
    final bytes = match == null ? null : int.tryParse(match.group(1)!);
    return bytes == null ? null : bytes ~/ (1024 * 1024);
  }

  @override
  String toString() =>
      'MemoryFacts(available ${availableMegabytes}MB, free $freeMegabytes MB'
      '${totalMegabytes == null ? '' : ' of $totalMegabytes MB'})';
}

/// The typed load refusal: why the weights were not loaded, with the
/// numbers that drove it. Recorded as the client's load error so the
/// next `infer` answers the named `engine_load_refused` failure with
/// these details — never a bare `unavailable`.
final class MlxLoadRefusal implements Exception {
  const MlxLoadRefusal({
    required this.requiredAvailableMegabytes,
    required this.availableMegabytes,
  });

  final int requiredAvailableMegabytes;
  final int availableMegabytes;

  String get message =>
      'weight load refused: ${availableMegabytes}MB available is below the '
      '${requiredAvailableMegabytes}MB floor (loading would push the '
      'machine into swap); free memory or pass MlxLoadGate.disabled to '
      'override';

  @override
  String toString() => message;
}

/// The load gate: refuse a weight load when the machine cannot hold it.
///
/// `MlxLoadGate.defaults` (4096 MB free) is the incident floor: the
/// cached checkpoints are sub-2GB 4-bit snapshots, but the KV cache,
/// the host app, and everything else on a 16GB machine need the rest.
/// Benches and explicit experiments pass `gate: null` (disabled) — the
/// gate is a default, never a monopoly.
final class MlxLoadGate {
  final int minFreeMegabytes;

  /// The facts source (injectable for tests; production reads fresh).
  final Future<MemoryFacts?> Function() readMemory;

  const MlxLoadGate({
    required this.minFreeMegabytes,
    this.readMemory = MemoryFacts.current,
  });

  /// The incident floor: refuse below 4 GB AVAILABLE (free + inactive +
  /// speculative + purgeable — never the always-tiny bare free count).
  static const MlxLoadGate defaults = MlxLoadGate(minFreeMegabytes: 4096);

  /// Evaluates the gate on fresh facts. Returns the refusal when the
  /// machine cannot hold the load, null when the load may proceed.
  /// Unknown facts (sensor absent) allow — the caller may warn.
  Future<MlxLoadRefusal?> evaluate() async {
    final facts = await readMemory();
    if (facts == null) return null;
    if (facts.availableMegabytes >= minFreeMegabytes) return null;
    return MlxLoadRefusal(
      requiredAvailableMegabytes: minFreeMegabytes,
      availableMegabytes: facts.availableMegabytes,
    );
  }
}

/// The typed lane saturation refusal: the lane holds [laneDepth]
/// requests already (one running, the rest queued); a deeper caller is
/// refused NOW instead of joining an unbounded treadmill.
final class MxlLaneBusy implements Exception {
  const MxlLaneBusy(this.laneDepth);

  /// How many requests the lane already holds.
  final int laneDepth;

  String get message =>
      'native engine lane saturated: $laneDepth request(s) already in '
      'the lane; retry after the current generation';

  @override
  String toString() => message;
}

/// ONE generation at a time with a bounded lane depth — the treadmill
/// bound for any caller (a bot host, a daemon router, a palette probe).
///
/// The native engine serializes decodes on its own forward lock anyway;
/// the lane makes that serialization EXPLICIT and bounded: request N+1
/// beyond the depth is refused immediately with [MxlLaneBusy] instead of
/// piling into an unbounded queue that keeps the machine hot forever.
final class MxlLane {
  MxlLane({this.maxLaneDepth = 3});

  /// At most this many requests in the lane (one running, the rest
  /// queued). `0` is meaningless (nothing could ever run) and is
  /// treated as 1.
  final int maxLaneDepth;

  Future<void> _tail = Future<void>.value();

  /// Requests currently held by the lane (running + queued).
  int get laneDepth => _held;

  var _held = 0;

  /// Runs [job] in the lane. Throws [MxlLaneBusy] when the lane already
  /// holds its depth; the refusal costs nothing and releases nothing.
  Future<T> run<T>(Future<T> Function() job) {
    final depth = maxLaneDepth < 1 ? 1 : maxLaneDepth;
    if (_held >= depth) throw MxlLaneBusy(_held);
    _held++;
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await job());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _held--;
      }
    });
    return completer.future;
  }
}
