/// The live memory-facts probe (2026-11-19, the v3.3 calibration):
/// prints the sensed facts in the bar's own language so a human can
/// cross-check them against Activity Monitor side by side — the
/// identity the dfp parse test pins (Cached Files = file-backed pages,
/// App+Wired+Compressed = anonymous+wired+compressor-occupied).
///
/// Run from this package: `fvm dart run tool/memory_facts_probe.dart`.
library;

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

String gb(int mb) => (mb / 1024).toStringAsFixed(1);

Future<void> main() async {
  final facts = await MemoryFacts.current();
  if (facts == null) {
    print('PROBE: no memory facts (non-macOS / sensor failure)');
    return;
  }
  print('PROBE: $facts');
  final total = facts.totalMegabytes;
  print('total:            ${total == null ? '?' : gb(total)} GB');
  print('in use:           ${gb(facts.usedMegabytes ?? 0)} GB');
  print('reclaimable cache:${gb(facts.cachedMegabytes ?? 0)} GB');
  print('free:             ${gb(facts.freeMegabytes)} GB');
  print(
    'available basis:  ${gb(facts.availableMegabytes)} GB (cache + free)',
  );
  print('swap on disk:     ${gb(facts.swapUsedMegabytes ?? 0)} GB');
  print('compressor:       ${gb(facts.compressorMegabytes ?? 0)} GB');
}
