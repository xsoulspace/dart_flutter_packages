// ignore_for_file: avoid_print, lines_longer_as_80_chars

/// Stress CLI entrypoint (ADR 0026 §4) — provider-less composition root.
///
/// `list` works out of the box; `run` needs a backend — supply it from a
/// composition root (e.g. `xsoulspace_inference_apple_foundation`) or an
/// app that registers a router.
library;

import 'package:xsoulspace_agentic_harness/src/cli/stress_cli.dart';

Future<void> main(final List<String> args) => runStressCli(
  args,
  buildRouter: () async => null, // no provider registered here
);
