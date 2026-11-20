/// The local-model RUNTIME surface (2026-11-18, the owner's disk/memory
/// split): DOWNLOAD vs LOAD are two independent lifecycle stages, and
/// this is the LOAD half — the process-wide fact of which snapshots hold
/// their weights in RAM right now, with load/unload verbs a UI can call.
///
/// The law that makes a UI Load mean something: the DYLIB is the
/// registry. Handles are process-global and
/// `mlx_native_qwen_load` is idempotent per snapshot dir, so a model
/// preloaded here is the SAME engine the chat lanes ride — the weights
/// never sit in RAM twice, and `unload` frees exactly what `load`
/// brought in. `NativeQwenTextEngine.adoptLoaded` is the read side.
///
/// Every method is honest about the machine: a load of an absent
/// snapshot throws the named snapshot-absent error (the runtime never
/// downloads — the manager owns disk); an unload of an unknown dir is a
/// no-op, not an error.
library;

import 'laya_native_lfm2_client.dart';
import 'laya_native_qwen_client.dart';
import 'mlx_native_resource_gates.dart';

/// The qwen-family runtime: one engine per snapshot, process-wide.
final class MlxModelRuntime {
  MlxModelRuntime._();

  /// The process-wide instance (stateless — the dylib owns the truth —
  /// but a singleton keeps call sites uniform and leaves room for a
  /// loading-in-flight map).
  static final MlxModelRuntime instance = MlxModelRuntime._();

  /// The in-flight loads, keyed by snapshot dir — a second caller during
  /// a load awaits the SAME attempt (the row IS the progress).
  final Map<String, Future<NativeQwenTextEngine>> _loading =
      <String, Future<NativeQwenTextEngine>>{};

  /// The lfm-family in-flight loads (same law as [_loading]).
  final Map<String, Future<NativeLfm2TextEngine>> _loadingLfm =
      <String, Future<NativeLfm2TextEngine>>{};

  /// Whether [snapshotDir]'s weights are in RAM right now (the dylib's
  /// own registry — cheap, synchronous, never a guess).
  bool isQwenLoaded(String snapshotDir) =>
      NativeQwenTextEngine.isLoaded(snapshotDir);

  /// The lfm-family poll (2026-11-18: the `local:lfm` cast joined the
  /// lifecycle — same law, same registry, second engine family).
  bool isLfmLoaded(String snapshotDir) =>
      NativeLfm2TextEngine.isLoaded(snapshotDir);

  /// Loads [snapshotDir]'s weights into RAM (or adopts the engine
  /// another caller already loaded). Never downloads: an absent snapshot
  /// throws the named snapshot-absent error. The MEMORY GATE still
  /// governs an explicit Load (the incident law is not a chat-lane
  /// monopoly), SIZE-AWARE when the caller names the weights
  /// ([weightsBytes] — the requirement scales with the checkpoint, one
  /// arithmetic with the UI's fit verdict): a machine that cannot hold
  /// it gets the typed [MlxLoadRefusal]. [force] skips the gate — the
  /// CONSENTED override (the UI's "load anyway" dialog names the risk
  /// first; the gate is a default, never a monopoly).
  Future<void> loadQwen(
    String snapshotDir, {
    int? weightsBytes,
    bool force = false,
  }) async {
    if (isQwenLoaded(snapshotDir)) return;
    if (!force) {
      final refusal = await MlxLoadGate.defaults.evaluate(
        weightsBytes: weightsBytes,
      );
      if (refusal != null) throw refusal;
    }
    final pending =
        _loading[snapshotDir] ??= NativeQwenTextEngine.loadAsync(
          snapshotDir: snapshotDir,
        );
    try {
      await pending;
    } on Object {
      // A failed load retries on the next call — the recorded error is
      // the client's own loadError, never a poisoned shared future.
    } finally {
      if (identical(_loading[snapshotDir], pending)) {
        _loading.remove(snapshotDir);
      }
    }
  }

  /// Frees [snapshotDir]'s weights (the engine handle unloads; an
  /// in-flight generation on the old handle completes on its own Arc,
  /// the next call after an unload reloads from disk). Unknown dir: a
  /// no-op.
  void unloadQwen(String snapshotDir) {
    final engine = NativeQwenTextEngine.adoptLoaded(snapshotDir);
    engine?.dispose();
  }

  /// The lfm-family LOAD: the same size-aware gate + in-flight map law
  /// as [loadQwen] (the dirs never collide — different snapshots),
  /// riding `NativeLfm2TextEngine`'s adopt-first loadAsync. One engine
  /// per snapshot holds for lfm2 too: the chat lane's lazy client adopts
  /// what a UI preload brought in.
  Future<void> loadLfm(
    String snapshotDir, {
    int? weightsBytes,
    bool force = false,
  }) async {
    if (isLfmLoaded(snapshotDir)) return;
    if (!force) {
      final refusal = await MlxLoadGate.defaults.evaluate(
        weightsBytes: weightsBytes,
      );
      if (refusal != null) throw refusal;
    }
    final pending = _loadingLfm[snapshotDir] ??= NativeLfm2TextEngine
        .loadAsync(snapshotDir: snapshotDir);
    try {
      await pending;
    } on Object {
      // A failed load retries on the next call — the recorded error is
      // the client's own loadError, never a poisoned shared future.
    } finally {
      if (identical(_loadingLfm[snapshotDir], pending)) {
        _loadingLfm.remove(snapshotDir);
      }
    }
  }

  /// The lfm-family UNLOAD: adopt the resident engine and dispose it
  /// (the native registry entry drops; an in-flight generation's Arc
  /// keeps the weights until it finishes).
  void unloadLfm(String snapshotDir) {
    NativeLfm2TextEngine.adoptLoaded(snapshotDir)?.dispose();
  }
}
