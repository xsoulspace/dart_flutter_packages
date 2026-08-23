/// Agent harness — sub-libraries split from the former monolithic
/// `agent_plugin.dart`.
///
/// This barrel re-exports the component, resource, event, system, handler,
/// and plugin definitions. Kept so `export
/// 'src/agent/agent_plugin.dart';` in the package root works unchanged.
library;

export 'model_router.dart';
export 'data_models/data_models.dart';
export 'decisions/decision_flow.dart';
export 'events.dart';
export 'handler.dart';
export 'handler_structured_tools.dart';
export 'harness_loop.dart';
export 'narrative/narrative.dart';
export 'observation/observation.dart';
export 'plugin.dart';
export 'resources/resources.dart';
export 'schedules.dart';
export 'systems/systems.dart';
export 'testing/testing.dart';
export 'world_setup.dart';
// NOTE: tools/fs_tools.dart is intentionally NOT exported here — it uses
// dart:io and would break web compilation of the core barrel. Import it
// directly on VM-only targets:
//   import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
export 'tools/tool_call_parser.dart';
export 'tools/tool_registry.dart';
