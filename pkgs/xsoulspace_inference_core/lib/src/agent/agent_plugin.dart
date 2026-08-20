/// Agent harness — sub-libraries split from the former monolithic
/// `agent_plugin.dart`.
///
/// This barrel re-exports the component, resource, event, system, handler,
/// and plugin definitions. Kept so `export
/// 'src/agent/agent_plugin.dart';` in the package root works unchanged.
library;

export 'components.dart';
export 'events.dart';
export 'handler.dart';
export 'plugin.dart';
export 'resources.dart';
export 'systems.dart';
export 'tools.dart';
