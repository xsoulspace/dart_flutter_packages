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

/// `{availableMegabytes, freeMegabytes, totalMegabytes, …}` — the load
/// gate's input facts, in Activity Monitor's own categories
/// (2026-11-18 v3.3 recalibration, the owner's "the memory is still
/// incorrect": the previous basis — free + inactive + speculative +
/// purgeable — read 587 MB available on the owner's 16 GB machine
/// where Activity Monitor showed 2.01 GB of reclaimable Cached Files).
///
/// The calibrated identity, pinned against a real screenshot (Physical
/// 16.00 = Used 14.06 + Cached Files 2.01, Compressed 5.06, Wired
/// 2.36, App 5.93) and live `vm_stat`:
///
/// * `Cached Files` = **File-backed pages** — matched to the decimal.
/// * `App Memory` = **Anonymous pages**; `Compressed` = **Pages
///   occupied by compressor**; `Wired` = `Pages wired down`.
/// * the whole machine: total = anonymous + wired + compressor +
///   file-backed + free + speculative (±1% slack).
///
/// So [availableMegabytes] — the gate basis — is now the RECLAIMABLE
/// signal: cached (file-backed) + free pages. That is what the OS can
/// hand a new allocation without squeezing running apps, and it is the
/// number the owner cross-checks against Activity Monitor.
///
/// Read fresh on every gate evaluation: available memory is exactly the
/// fact that changes between a refused retry and the one that passes,
/// so caching would hide the recovery. Sensor failure or non-macOS
/// degrades to null — the caller allows with a warning, never blocks a
/// machine it cannot see.
final class MemoryFacts {
  /// Cached (file-backed) + free pages, in MB — what the OS could hand
  /// a new allocation by reclaiming the file cache, without squeezing
  /// running apps. The load gate's basis. On a vm_stat too old to
  /// report the file-backed row this degrades to the legacy composite
  /// (free + inactive + speculative + purgeable).
  final int availableMegabytes;

  /// Free + speculative pages, in MB — truly unallocated.
  final int freeMegabytes;

  /// Null when the total could not be sensed (the vm_stat path does not
  /// need it; `sysctl hw.memsize` fills it when available).
  final int? totalMegabytes;

  /// The machine's working set, in MB: anonymous + wired +
  /// compressor-occupied pages — Activity Monitor's App + Wired +
  /// Compressed panels. Null when the vm_stat is too old to report the
  /// anonymous row (the legacy composite is used instead).
  final int? usedMegabytes;

  /// File-backed pages, in MB — Activity Monitor's "Cached Files":
  /// recently used file cache, reclaimable on demand. Null on the
  /// legacy parse (treated as 0 by the UI).
  final int? cachedMegabytes;

  /// Resident pages held by the memory compressor, in MB (2026-11-18
  /// honesty law — the owner's "the measure is incorrect"): memory the
  /// machine has ALREADY over-subscribed and squeezed. A big compressor
  /// (or a swapping machine) means the nominal [availableMegabytes] is
  /// optimistic — reclaiming it costs work and the machine is paging.
  /// Null when the row was unreadable.
  final int? compressorMegabytes;

  /// Swap currently ON DISK, in MB (`sysctl vm.swapusage`). Non-null
  /// and > 0 = the machine has already spilled. The load gate stays
  /// floor-based (policy), but the UI discloses this so "available"
  /// is never read as "uncongested". Null when unreadable.
  final int? swapUsedMegabytes;

  const MemoryFacts({
    required this.availableMegabytes,
    required this.freeMegabytes,
    this.totalMegabytes,
    this.usedMegabytes,
    this.cachedMegabytes,
    this.compressorMegabytes,
    this.swapUsedMegabytes,
  });

  /// Reads the facts fresh. Non-macOS (or any sensor failure) yields
  /// null — never an exception.
  static Future<MemoryFacts?> current() async {
    if (!Platform.isMacOS) return null;
    String? vmStat;
    String? memSize;
    String? swap;
    try {
      final r = await Process.run('vm_stat', const <String>[]);
      if (r.exitCode == 0) vmStat = r.stdout as String;
      final s = await Process.run('sysctl', const <String>['hw.memsize']);
      if (s.exitCode == 0) memSize = s.stdout as String;
      final w = await Process.run('sysctl', const <String>['vm.swapusage']);
      if (w.exitCode == 0) swap = w.stdout as String;
    } on ProcessException {
      return null;
    }
    return MemoryFacts.parse(vmStat: vmStat, memSize: memSize, swap: swap);
  }

  /// Pure parser — pin-tested against recorded `vm_stat`/`sysctl`
  /// outputs. Returns null when the page accounting cannot be read.
  static MemoryFacts? parse({String? vmStat, String? memSize, String? swap}) {
    final pages = vmStat ?? '';
    final pageSize = _parsePageSize(pages);
    if (pageSize == null) return null;
    final free = _parseLabeledPages(pages, 'Pages free:');
    if (free == null) return null;
    int mb(int pages) => (pages * pageSize) ~/ (1024 * 1024);
    final inactive = _parseLabeledPages(pages, 'Pages inactive:') ?? 0;
    final speculative = _parseLabeledPages(pages, 'Pages speculative:') ?? 0;
    final purgeable = _parseLabeledPages(pages, 'Pages purgeable:') ?? 0;
    // "Pages occupied by compressor" (not "stored in" — the occupied
    // row is the RESIDENT footprint; the stored row is the pre-squeeze
    // size and would double-count nothing but would mislead).
    final compressor = _parseLabeledPages(
      pages,
      'Pages occupied by compressor:',
    );
    final anonymous = _parseLabeledPages(pages, 'Anonymous pages:');
    final fileBacked = _parseLabeledPages(pages, 'File-backed pages:');
    final freeMb = mb(free + speculative);
    // The calibrated decomposition (v3.3): anonymous + wired +
    // compressor is the working set; file-backed is the reclaimable
    // cache; the gate basis is cache + free. A vm_stat without the
    // modern rows (anonymous/file-backed — pre-macOS 13) falls back to
    // the legacy available composite and leaves used/cached unnamed.
    final int? usedMb;
    final int? cachedMb;
    final int availableMb;
    if (anonymous != null) {
      final wired = _parseLabeledPages(pages, 'Pages wired down:') ?? 0;
      usedMb = mb(anonymous + wired + (compressor ?? 0));
      cachedMb = fileBacked != null ? mb(fileBacked) : 0;
      availableMb = freeMb + cachedMb;
    } else {
      usedMb = null;
      cachedMb = null;
      availableMb = mb(free + inactive + speculative + purgeable);
    }
    final totalMb = _parseMemSize(memSize ?? '');
    final swapMb = _parseSwapUsed(swap ?? '');
    final compressorMb = compressor != null ? mb(compressor) : null;
    return MemoryFacts(
      availableMegabytes: availableMb,
      freeMegabytes: freeMb,
      totalMegabytes: totalMb,
      usedMegabytes: usedMb,
      cachedMegabytes: cachedMb,
      compressorMegabytes: compressorMb,
      swapUsedMegabytes: swapMb,
    );
  }

  /// `total = 8192.00M  used = 7135.00M  free = 1057.00M  (encrypted)`
  /// — the USED figure, in whole MB.
  static int? _parseSwapUsed(String swapusage) {
    final match = RegExp(r'used\s*=\s*([0-9.]+)M').firstMatch(swapusage);
    return switch (match) {
      null => null,
      final m => double.tryParse(m.group(1)!)?.round(),
    };
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
      'MemoryFacts(available ${availableMegabytes}MB (cache+free)'
      '${usedMegabytes == null ? '' : ', used $usedMegabytes MB'}'
      '${cachedMegabytes == null ? '' : ', cached $cachedMegabytes MB'}'
      ', free $freeMegabytes MB'
      '${totalMegabytes == null ? '' : ' of $totalMegabytes MB'}'
      '${compressorMegabytes == null ? '' : ', compressor $compressorMegabytes MB'}'
      '${swapUsedMegabytes == null ? '' : ', swap $swapUsedMegabytes MB'})';
}

/// The typed load refusal: why the weights were not loaded, with the
/// numbers that drove it. Recorded as the client's load error so the
/// next `infer` answers the named `engine_load_refused` failure with
/// these details — never a bare `unavailable`.
final class MlxLoadRefusal implements Exception {
  const MlxLoadRefusal({
    required this.requiredAvailableMegabytes,
    required this.availableMegabytes,
    this.weightsRequiredMegabytes,
    this.pressurePointMegabytes,
  });

  /// The AVAILABLE memory the gate needed in total (for the
  /// size-aware shape: the weights requirement + the pressure point).
  final int requiredAvailableMegabytes;

  /// The AVAILABLE memory the machine had.
  final int availableMegabytes;

  /// The MODEL's own requirement (weights + KV/runtime slack), when the
  /// size-aware shape refused — never carrying the pressure point (the
  /// 2026-11-20 owner law: the reserve is the machine's, not the
  /// model's rent).
  final int? weightsRequiredMegabytes;

  /// The machine's post-load headroom floor (the pressure point) the
  /// load would have violated, when the size-aware shape refused.
  final int? pressurePointMegabytes;

  String get message => weightsRequiredMegabytes == null
      ? 'weight load refused: ${availableMegabytes}MB available is below the '
          '${requiredAvailableMegabytes}MB floor; free memory or load '
          'anyway with explicit consent'
      : 'weight load refused: the weights need '
          '${weightsRequiredMegabytes}MB but only ${availableMegabytes}MB '
          'is reclaimable — loading would leave '
          '${availableMegabytes - weightsRequiredMegabytes!}MB under the '
          '${pressurePointMegabytes}MB pressure point; free memory or '
          'load anyway with explicit consent';

  @override
  String toString() => message;
}

/// The load gate: refuse a weight load when the machine cannot hold it.
///
/// TWO evaluation shapes (2026-11-20, the one-math law — the UI's fit
/// verdict and this gate are the same function, so a Load button can
/// never claim a refusal the runtime would not make):
///
/// * SIZE-AWARE (weights known): the MODEL's requirement is the weights
///   rounded up + the KV/runtime slack. The 1 GB RESERVE is NOT the
///   model's rent — it is the MACHINE'S PRESSURE POINT (the owner's
///   2026-11-20 correction): one shared post-load headroom floor for
///   all models, checked against the machine's current reclaimable
///   memory, never multiplied per model and never baked into what a
///   model "requires". Refuse iff `available − weightsRequirement <
///   reserve`.
/// * FLOOR (weights unknown): callers that cannot size the snapshot
///   (the chat clients' lazy loads) keep the calibrated flat
///   `minFreeMegabytes` floor — the 2026-11-14 incident law, env-tunable
///   upstream (`HARNESS_MLX_MIN_FREE_MB`).
///
/// `MlxLoadGate.defaults` (4096 MB floor, 25% slack, 1024 MB pressure
/// point) is the policy default, never a monopoly: an explicit caller
/// may pass `force`/`gate: null` (benches, consented UI overrides).
final class MlxLoadGate {
  final int minFreeMegabytes;

  /// The KV-cache / runtime slack over the weights (a fraction): the
  /// incident note names the KV cache and the host app as reasons a
  /// bare weights-size budget lies.
  final double slackFraction;

  /// The machine's pressure point, in MB: the post-load headroom every
  /// size-aware load must leave free — ONE shared floor for all models
  /// (the host app, the OS's own headroom), not a per-model cost.
  final int reserveMegabytes;

  /// The facts source (injectable for tests; production reads fresh).
  final Future<MemoryFacts?> Function() readMemory;

  const MlxLoadGate({
    required this.minFreeMegabytes,
    this.slackFraction = defaultSlackFraction,
    this.reserveMegabytes = defaultReserveMegabytes,
    this.readMemory = MemoryFacts.current,
  });

  /// The incident floor: refuse a weights-unknown load below 4 GB
  /// AVAILABLE (v3.3 basis: reclaimable file cache + free pages — never
  /// the always-tiny bare free count; the legacy composite on old
  /// vm_stat).
  static const MlxLoadGate defaults = MlxLoadGate(minFreeMegabytes: 4096);

  /// The KV/runtime slack fraction (25% of the weights) the size-aware
  /// requirement adds — single-sourced here; the UI reads this, never a
  /// re-stated number.
  static const double defaultSlackFraction = 0.25;

  /// The machine's pressure point (1 GB of post-load headroom) — the
  /// shared floor, never per-model rent.
  static const int defaultReserveMegabytes = 1024;

  /// The MODEL's requirement, in MB: the weights rounded UP (a partial
  /// megabyte still occupies a whole one once resident) and the
  /// KV/runtime slack over them. Deliberately WITHOUT the reserve —
  /// the pressure point is the machine's (the UI renders this as what
  /// the model needs, and names the pressure point separately). THE
  /// one arithmetic — the UI's fit verdict delegates here so "fits"
  /// and "the gate allows" are provably the same fact.
  int requiredMegabytes(int weightsBytes) {
    final weightsMb = (weightsBytes / (1024 * 1024)).ceil();
    return (weightsMb * (1 + slackFraction)).ceil();
  }

  /// Evaluates the gate on fresh facts. Returns the refusal when the
  /// machine cannot hold the load, null when the load may proceed.
  /// Unknown facts (sensor absent) allow — the caller may warn.
  /// [weightsBytes] switches to the size-aware shape (the model's
  /// requirement against the machine's pressure point); without it the
  /// flat [minFreeMegabytes] floor governs (weights-unknown callers).
  Future<MlxLoadRefusal?> evaluate({int? weightsBytes}) async {
    final facts = await readMemory();
    if (facts == null) return null;
    if (weightsBytes == null) {
      if (facts.availableMegabytes >= minFreeMegabytes) return null;
      return MlxLoadRefusal(
        requiredAvailableMegabytes: minFreeMegabytes,
        availableMegabytes: facts.availableMegabytes,
      );
    }
    final weightsRequired = requiredMegabytes(weightsBytes);
    final headroom = facts.availableMegabytes - weightsRequired;
    if (headroom >= reserveMegabytes) return null;
    return MlxLoadRefusal(
      requiredAvailableMegabytes: weightsRequired + reserveMegabytes,
      availableMegabytes: facts.availableMegabytes,
      weightsRequiredMegabytes: weightsRequired,
      pressurePointMegabytes: reserveMegabytes,
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
