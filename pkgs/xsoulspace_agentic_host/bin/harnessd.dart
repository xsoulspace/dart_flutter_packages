// ignore_for_file: avoid_print

/// `harnessd` — the provider-less daemon entrypoint (ADR 0025).
///
/// Runs the harnessd daemon with NO provider bindings: usable out of the
/// box in `--scripted` (LLM-free gates) and `--remote-mover` (the client
/// — pi — decides) modes, which need no mover model. Provider-backed
/// modes (`--backend <name>`) come from a composition root that registers
/// `HarnessBackendBinding` entries — see
/// `xsoulspace_inference_apple_foundation/bin/harnessd.dart`.
library;

import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

Future<void> main(final List<String> args) =>
    runHarnessdCli(args, bindings: const {});
