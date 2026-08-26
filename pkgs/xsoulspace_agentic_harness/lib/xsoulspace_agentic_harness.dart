/// xsoulspace_agentic_harness — cinematic multi-actor agent harness.
///
/// Tiny-context projection, bounded agency, LLM-free testability. The
/// engine is provider-agnostic: wire any `InferenceClient` (from
/// `xsoulspace_inference_core`) through [ModelRouter] and a
/// [GenerationHandler].
///
/// Sub-surfaces:
/// - CLI SDK: `src/cli.dart` — embeddable everyday REPL host.
/// - Benchmark/tooling API: `benchmark_api.dart` — coding-suite runner,
///   experiment arms, world builders, decorators.
library;

export 'package:ecsly/ecsly.dart';
export 'package:ecsly_app/ecsly_app.dart';

export 'src/agent.dart';
