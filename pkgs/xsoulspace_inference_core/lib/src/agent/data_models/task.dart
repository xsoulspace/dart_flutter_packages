import 'dart:async';

import 'package:meta/meta.dart';

/// Identity for an in-flight async task (generation, tool call, human
/// input). Tasks are correlated across the world via [TaskRegistryResource].
@immutable
class TaskId {
  const TaskId(this.value);
  factory TaskId.create() => TaskId('${DateTime.now().microsecondsSinceEpoch}');
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TaskId && value == other.value);

  @override
  int get hashCode => value.hashCode;
}

/// Cold handle to an in-flight task.
///
/// Holds the [Completer] that resumes the awaiting caller (e.g. a native
/// tool bridge or a host awaiting an actor response). Completers live here —
/// in a cold resource — never in a component, keeping the ECS hot path
/// future-free.
class TaskHandle {
  TaskHandle({Completer<dynamic>? completer})
    : completer = completer ?? Completer<dynamic>();
  final Completer<dynamic> completer;
}
