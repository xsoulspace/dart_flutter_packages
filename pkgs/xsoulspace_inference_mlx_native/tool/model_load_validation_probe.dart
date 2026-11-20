/// The owner's 2026-11-20 validation probe: EVERY catalog entry's
/// verdict under the pressure-point load law, against the REAL hub
/// cache and the REAL memory sensor — then a live LOAD + GENERATE +
/// UNLOAD cycle through [MlxModelRuntime.loadQwen]/[loadLfm] with the
/// catalog's weightsBytes (the exact call path the Models surface's
/// Load verb rides, gate and all).
///
/// Exit 0 when every INSTALLED in-app entry either passes the gate or
/// is refused for a NAMED reason, and the live family cycle completes
/// with coherent text. The laya checkpoint is disk-only by law (the
/// laya-serve sidecar serves it out-of-process) — its presence is
/// reported, its RAM is its own.
library;

import 'dart:io';

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

Future<void> main(List<String> args) async {
  final installMissing = args.contains('--install-missing');
  final facts = await MemoryFacts.current();
  final gate = MlxLoadGate.defaults;
  final available = facts?.availableMegabytes;
  stdout.writeln(
    'machine: ${facts ?? 'sensor-absent (unknown allows)'}',
  );
  stdout.writeln('pressure point: ${gate.reserveMegabytes} MB');
  stdout.writeln('---');

  final installer = MlxModelInstaller();
  var failures = 0;
  MlxModelCatalogEntry? firstLoadableQwen;
  MlxModelCatalogEntry? firstLoadableLfm;
  for (final entry in mlxModelCatalog) {
    var state = installer.stateOf(entry);
    final ref = entry.repoId.split('/').last;
    if (entry.family == 'laya') {
      stdout.writeln(
        '$ref: DISK-ONLY by law (served out-of-process by the laya-serve '
        'sidecar; installed=${state.installed})',
      );
      continue;
    }
    if (!state.installed) {
      if (installMissing) {
        stdout.writeln('$ref: not on disk — installing (consented)...');
        try {
          await for (final p in installer.install(
            entry,
            userConsent: true,
          )) {
            if (p.percent != null && p.percent! % 25 == 0) {
              stdout.writeln('  ${p.phase.name} ${p.percent}%');
            }
          }
          stdout.writeln('  installed.');
        } on Object catch (error) {
          stdout.writeln('  INSTALL FAILED: $error');
          failures++;
          continue;
        }
        state = installer.stateOf(entry);
      } else {
        stdout.writeln(
          '$ref: not on disk — download first (no verdict claimed)',
        );
        continue;
      }
    }
    final required = gate.requiredMegabytes(entry.approxDownloadBytes);
    final refusal = await gate.evaluate(
      weightsBytes: entry.approxDownloadBytes,
    );
    final verdict = refusal == null
        ? 'LOADABLE (rent $required MB, headroom '
            '${available == null ? '?' : available - required} MB)'
        : 'REFUSED (${refusal.message})';
    stdout.writeln('$ref: installed at ${state.snapshotDir}');
    stdout.writeln('  → $verdict');
    if (refusal == null) {
      if (entry.family == 'lfm2.5' && firstLoadableLfm == null) {
        firstLoadableLfm = entry;
      }
      if (firstLoadableQwen == null && entry.family != 'lfm2.5') {
        firstLoadableQwen = entry;
      }
    }
  }

  stdout.writeln('---');
  final dir = installer.stateOf;
  Future<bool> cycle(
    MlxModelCatalogEntry entry,
    Future<void> Function(String, {int? weightsBytes}) load,
    bool Function(String) isLoaded,
    void Function(String) unload,
    NativeQwenTextEngine? Function(String) adoptQwen,
    NativeLfm2TextEngine? Function(String) adoptLfm,
    bool isLfm,
  ) async {
    final snapshot = dir(entry).snapshotDir;
    if (snapshot == null) return false;
    try {
      await load(snapshot, weightsBytes: entry.approxDownloadBytes);
      final loaded = isLoaded(snapshot);
      stdout.writeln(
        '${entry.repoId.split('/').last}: LOADED=$loaded '
        '(gate passed with weightsBytes=${entry.approxDownloadBytes})',
      );
      if (!loaded) return false;
      final text = isLfm
          ? adoptLfm(snapshot)!.generate(
              prompt: 'The capital of France is',
              maxTokens: 10,
            ).text
          : adoptQwen(snapshot)!.generate(
              prompt: 'The capital of France is',
              maxTokens: 10,
            ).text;
      stdout.writeln('  TEXT: ${text.trim()}');
      unload(snapshot);
      stdout.writeln(
        '  after unload isLoaded: ${isLoaded(snapshot)}',
      );
      return loaded && text.trim().isNotEmpty;
    } on Object catch (error) {
      stdout.writeln('  CYCLE FAILED: $error');
      return false;
    }
  }

  if (firstLoadableQwen != null) {
    final ok = await cycle(
      firstLoadableQwen,
      (d, {int? weightsBytes}) =>
          MlxModelRuntime.instance.loadQwen(d, weightsBytes: weightsBytes),
      MlxModelRuntime.instance.isQwenLoaded,
      MlxModelRuntime.instance.unloadQwen,
      (d) => NativeQwenTextEngine.adoptLoaded(d),
      (d) => null,
      false,
    );
    if (!ok) failures++;
  } else {
    stdout.writeln('no loadable qwen entry under today\'s memory');
  }
  if (firstLoadableLfm != null) {
    final ok = await cycle(
      firstLoadableLfm,
      (d, {int? weightsBytes}) =>
          MlxModelRuntime.instance.loadLfm(d, weightsBytes: weightsBytes),
      MlxModelRuntime.instance.isLfmLoaded,
      MlxModelRuntime.instance.unloadLfm,
      (d) => null,
      (d) => NativeLfm2TextEngine.adoptLoaded(d),
      true,
    );
    if (!ok) failures++;
  } else {
    stdout.writeln('no loadable lfm entry under today\'s memory');
  }

  final layaRoot = Directory(
    '${Platform.environment['HOME']}/.cache/xsoulspace/laya-mlx',
  );
  stdout.writeln(
    'laya checkpoint on disk: ${layaRoot.existsSync()} '
    '(~/.cache/xsoulspace/laya-mlx — the sidecar\'s, not this process\'s)',
  );

  stdout.writeln(failures == 0 ? 'VALIDATION OK' : 'VALIDATION FAILED');
  exit(failures == 0 ? 0 : 1);
}
