// ignore_for_file: avoid_print, lines_longer_as_80_chars

/// AFM stress CLI — the thin composition root (ADR 0025/0026): injects the
/// AFM router factory into the harness's provider-agnostic stress CLI.
///
/// ```sh
/// dart run bin/stress_cli.dart list [--json]
/// dart run bin/stress_cli.dart run --scenario=multi_actor [--json]
/// ```
library;

import 'package:xsoulspace_agentic_harness/src/cli/stress_cli.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';

Future<void> main(final List<String> args) => runStressCli(
  args,
  buildRouter: () async {
    final binding = appleFoundationBinding();
    final router = binding.binding.buildRouter(model: '', apiKey: null);
    final client = binding.client();
    if (client != null) {
      await client.load();
      if (!await client.refreshAvailability()) return null;
    }
    return router;
  },
);
