/// Benchmark + tooling API for `xsoulspace_agentic_harness`.
///
/// Import this to drive the 20-task coding suite, ADR 0009 experiment
/// arms, or reuse world builders / decorators / estimators in your own
/// harness benchmarks. Provider packages use this surface instead of
/// reaching into `src/` or across packages with relative imports.
library;

// ---- coding suite ---------------------------------------------------------
export 'src/benchmark/coding_suite/checkers.dart';
export 'src/benchmark/coding_suite/report.dart';
export 'src/benchmark/coding_suite/runner.dart';
export 'src/benchmark/coding_suite/scripted_handler.dart';
export 'src/benchmark/coding_suite/task_spec.dart';

// ---- experiment arms (ADR 0009) ------------------------------------------
export 'src/benchmark/experiment_arms.dart';
export 'src/benchmark/profile.dart';

// ---- tooling --------------------------------------------------------------
export 'src/tooling/logging_handler.dart';
export 'src/tooling/token_estimate.dart';
export 'src/tooling/ae_bridge.dart';
export 'src/tooling/attribution.dart';
export 'src/tooling/locate_index.dart';
export 'src/tooling/world_builder.dart';
export 'src/tooling/build_gates.dart';
export 'src/tooling/act_with_project.dart';
