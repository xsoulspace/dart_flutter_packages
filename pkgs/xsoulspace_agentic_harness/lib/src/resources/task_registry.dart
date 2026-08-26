// ─────────────────────────────────────────────
// Task surface
// ─────────────────────────────────────────────
//
// Co-located here because [TaskId] / [TaskHandle] / [TaskRegistryResource]
// are referenced from components, events, and resources alike; keeping them
// together makes the import graph acyclic (components is a leaf above
// agent.dart).

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart';

/// World resource tracking in-flight async tasks.
///
/// This is the single source of truth for "is there pending async work".
/// [HarnessLoop.canSleep] checks it; systems resolve tasks by completing
/// the associated [TaskHandle.completer].
class TaskRegistryResource extends Resource {
  final Map<TaskId, TaskHandle> tasks = {};

  void register(TaskId id, TaskHandle handle) => tasks[id] = handle;

  TaskHandle? take(TaskId id) => tasks.remove(id);

  TaskHandle? peek(TaskId id) => tasks[id];

  bool has(TaskId id) => tasks.containsKey(id);

  int get length => tasks.length;

  bool get isEmpty => tasks.isEmpty;
}
