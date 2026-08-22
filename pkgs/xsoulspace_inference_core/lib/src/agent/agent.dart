/// Agent harness — sub-libraries split from the former monolithic
/// `agent_plugin.dart`.
///
/// This barrel re-exports the component, resource, event, system, handler,
/// and plugin definitions. Kept so `export
/// 'src/agent/agent_plugin.dart';` in the package root works unchanged.
library;

export 'model_router.dart';
export 'data_models/data_models.dart';
export 'events.dart';
export 'handler.dart';
export 'harness_loop.dart';
export 'narrative.dart';
export 'observation/observation.dart';
export 'plugin.dart';
export 'resources/resources.dart';
export 'systems/systems.dart';
export 'testing/testing.dart';
export 'tools/tools.dart';
