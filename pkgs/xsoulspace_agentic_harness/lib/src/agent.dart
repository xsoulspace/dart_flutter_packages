/// Agent harness — sub-libraries split from the former monolithic
/// `agent_plugin.dart`.
///
/// This barrel re-exports the component, resource, event, system, handler,
/// and plugin definitions. Kept so `export
/// 'src/agent/agent_plugin.dart';` in the package root works unchanged.
library;

export 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart' show SchemaBundle, ToolCall, ToolDef, ToolExecutionResult, ToolName, ToolRegistry;

export 'benchmark/profile.dart';
export 'cli/agent_cli.dart';
export 'cli_host.dart';
export 'data_models/data_models.dart';
export 'decisions/decision_flow.dart';
export 'events.dart';
export 'handler.dart';
export 'handler_structured_tools.dart';
export 'harness_loop.dart';
export 'model_router.dart';
export 'narrative/narrative.dart';
export 'observation/observation.dart';
export 'plugin.dart';
export 'resources/resources.dart';
export 'schedules.dart';
export 'snapshot.dart';
export 'snapshot_store.dart';
export 'systems/systems.dart';
export 'testing/testing.dart';
export 'tooling/ae_bridge.dart';
export 'tooling/attribution.dart';
// NOTE: tools/fs_tools.dart is intentionally NOT exported here — it uses
// dart:io and would break web compilation of the core barrel. Import it
// directly on VM-only targets:
//   import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
export 'tools/meaning_query_tools.dart';
export 'tools/tool_call_parser.dart';
export 'world_setup.dart';
