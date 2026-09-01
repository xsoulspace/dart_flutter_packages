/// xsoulspace_agentic_harness_flutter_profiler — the Flutter profiler for the
/// agent harness (PLAN J1.5.4).
///
/// `HarnessProfilerView` renders the live [HarnessPulse] — the whole current
/// stack of the agentic harness: open decisions, ReAct round budgets,
/// attempt/retry counts, verification verdicts, loop warnings, and (via a
/// host-supplied builder) the meaning cut the model currently sees.
///
/// Usage:
/// ```dart
/// HarnessProfilerView(
///   world: world,                       // OR pulseLoader: () => ...
///   recorder: flightRecorder,           // optional: records each poll
///   meaningCutBuilder: () => meaningCut(world, query: '', maxNodes: 24),
/// )
/// ```
library;

export 'src/harness_profiler_view.dart';
