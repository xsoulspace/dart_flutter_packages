/// Thread & Beat ontology for the agent harness.
///
/// Split by responsibility:
/// - [components] — Thread/Beat components and enums
/// - [graph_ops] — spawn/append/complete transforms
/// - [thread_systems] — score/prune/merge systems
/// - [facet_index] — keyword + thread-membership index resource
library;

export 'components.dart';
export 'facet_index.dart';
export 'graph_ops.dart';
export 'thread_systems.dart';
