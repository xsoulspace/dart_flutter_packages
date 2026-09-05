// ignore_for_file: lines_longer_as_80_chars

/// `harnessd` — the canonical ACP daemon, COMPOSED here (ADR 0025).
///
/// The daemon CLI + ACP backend live in `xsoulspace_agentic_host`; this
/// thin composition root only registers the backends this package can
/// supply (the AFM FFI bridge, plus OpenRouter as the explicit escalation
/// rung) and hands off:
///
/// ```sh
/// dart run bin/harnessd.dart [--backend apple_foundation_afm|open_router]
///                            [--model <id>] [--profile meaning]
///                            [--scripted] [--remote-mover]
///                            [--workspace <path>] [--idle-exit-minutes <n>]
/// ```
///
/// Default: `apple_foundation_afm` (AFM-first North Star); hosted
/// OpenRouter is the explicit escalation choice (`--backend open_router`,
/// needs OPENROUTER_API_KEY). Apps and pi extensions should NOT go through
/// this bin — embed `package:xsoulspace_agentic_host` directly (in-process
/// `HarnessAcpBackend` with the same bindings, or the ACP stdio daemon).
library;

import 'dart:io';

import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';

Future<void> main(final List<String> args) async {
  // The AFM client is RETAINED so session cancel reaches `xs_fm_cancel`.
  final afm = appleFoundationBinding();
  final orKey = Platform.environment['OPENROUTER_API_KEY'];
  ModelRouter? orRouter;
  if (orKey != null && orKey.isNotEmpty) {
    orRouter = ModelRouter(
      inferenceClientsBuilders: {
        OpenRouterModelNames.openRouter: () => OpenRouterInferenceClient(
              apiKey: orKey,
              defaultModel: 'deepseek/deepseek-v4-flash-0731',
            ),
      },
    )
      ..models[const ModelId('harnessd')] = Model(
        id: const ModelId('harnessd'),
        name: OpenRouterModelNames.openRouter,
      );
  }

  await runHarnessdCli(
    args,
    defaultBackend: 'apple_foundation_afm',
    bindings: {
      'apple_foundation_afm': afm.binding,
      'open_router': HarnessBackendBinding(
        defaultModel: 'deepseek/deepseek-v4-flash-0731',
        buildRouter: ({required model, apiKey}) => orRouter,
      ),
    },
  );
}
