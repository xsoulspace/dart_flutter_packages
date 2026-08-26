/// Agent harness systems, split by responsibility.
///
/// - [identity_systems] — seed actor identity beats (cold-start)
/// - [agency_systems] — agency granting + timeout sweeping
/// - projection — cinematic cut: ray-trace, rank, budget-fit
/// - [actor_act_system] — dispatch generation requests
/// - [generation_systems] — stream events + response processing
/// - [tool_systems] — tool execution + result beats
/// - [summary] — deliberate summarizeThread transform
library;

export 'actor_act_system.dart';
export 'agency_systems.dart';
export 'decision_flow_system.dart';
export 'generation_systems.dart';
export 'identity_systems.dart';
export 'loop_breaker_system.dart'
    show loopBreakerSystem, kLoopGuardKind;
export 'projection/projection_systems.dart';
export 'projection/relevance.dart' show keywordsOf;
export 'summary.dart';
export 'tool_systems.dart';
