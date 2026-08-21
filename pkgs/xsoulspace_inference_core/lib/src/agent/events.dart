import 'dart:async';
import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:from_json_to_json/from_json_to_json.dart';

import '../models/inference_models.dart';
import 'agent.dart';
import 'agent_low_api.dart';
import 'data_models/data_models.dart';

// ─────────────────────────────────────────────
// Events
// ─────────────────────────────────────────────

/// A handler that performs an async generation for an actor.
///
/// Implementations live outside the core (Flutter isolate, CLI, another
/// agent, a human channel). The world dispatches to them via
/// [GenerationHandlerResource]; they send results back as
/// [ActorGenerateResponse] events.
///
/// This replaces the old polled [ActorGenerateHandler]. Handlers are now
/// resources the world *uses*, not objects the world is polled by.
// ignore: one_member_abstracts
abstract class GenerationHandler {
  /// Perform the generation and send an [ActorGenerateResponse] back to
  /// [world]'s event channel. May send [ActorGenerateStreamEvent]s first.
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  );
}

/// Request to generate LLM output for an agent.
///
/// Dispatched by [actorActSystem] to a [GenerationHandler] resolved via
/// [GenerationHandlerResource]. [taskId] correlates the request to the
/// in-flight task in [TaskRegistryResource].
class ActorGenerateRequest implements EcsEvent {
  const ActorGenerateRequest({
    required this.actorEntity,
    required this.agentId,
    required this.modelId,
    required this.prompt,
    required this.systemPrompt,
    required this.contextFragments,
    required this.schema,
    required this.toolRegistry,
    required this.task,
    required this.taskId,
  });

  final Entity actorEntity;
  final AgentId agentId;
  final ModelId modelId;
  final String prompt;
  final String systemPrompt;
  final List<Object> contextFragments;
  final SchemaBundle schema;
  final ToolRegistry? toolRegistry;
  final InferenceTask task;
  final TaskId taskId;
}

/// Response from a [GenerationHandler] back to the ECS world.
///
/// [toolCalls] contains parsed tool calls if the model emitted any.
/// [toolResults] contains results of tool calls that were already executed
/// natively (e.g. Apple Foundation). [taskId] matches the originating
/// [ActorGenerateRequest].
class ActorGenerateResponse implements EcsEvent {
  const ActorGenerateResponse({
    required this.actorEntity,
    required this.structuralOutput,
    required this.rawOutput,
    this.toolCalls = const [],
    this.toolResults = const [],
    this.taskId,
  });

  final Entity actorEntity;
  final Map<String, dynamic> structuralOutput;
  final String rawOutput;
  final List<ToolCall> toolCalls;
  final List<ToolExecutionResult> toolResults;
  final TaskId? taskId;
}

/// Streaming chunk from the handler during generation.
///
/// Appended to the actor's [StreamingBeat] by [processStreamEventsSystem].
class ActorGenerateStreamEvent implements EcsEvent {
  const ActorGenerateStreamEvent({
    required this.actorEntity,
    required this.taskId,
    required this.chunk,
  });

  final Entity actorEntity;
  final TaskId taskId;
  final String chunk;
}

/// A parsed tool call from an LLM response.
class ToolCall {
  const ToolCall({required this.name, required this.arguments});
  final ToolName name;
  final Map<String, dynamic> arguments;
}

/// Result of a tool call execution.
class ToolExecutionResult {
  const ToolExecutionResult({required this.name, required this.output});
  factory ToolExecutionResult.encode({
    required String name,
    required Map<String, dynamic>? output,
  }) => ToolExecutionResult(
    name: name,
    output: output == null ? null : jsonEncode(output),
  );

  factory ToolExecutionResult.fromJson(Map<String, dynamic> json) =>
      ToolExecutionResult(
        name: jsonDecodeString(json['name']),
        output: jsonDecodeString(json['output']),
      );
  final String name;
  final String? output;

  Map<String, dynamic> toJson() => {'name': name, 'output': output};
}

/// Event: a tool call that needs to be executed by the ECS world.
///
/// Sent by [processResponsesSystem] (for parsed tool calls) or by
/// [WorldToolBridge] (for native tool calls during generation).
/// Processed by [toolExecutionSystem] in the Mechanical schedule.
///
/// When [taskId] is present, [toolExecutionSystem] resolves the associated
/// [TaskHandle] after execution — this is how native tool calls suspend and
/// resume through the world.
class ToolCallEvent implements EcsEvent {
  const ToolCallEvent({
    required this.actorEntity,
    required this.call,
    this.taskId,
  });
  final Entity actorEntity;
  final ToolCall call;
  final TaskId? taskId;
}

/// Event: a tool call result that has been executed.
///
/// Sent by [toolExecutionSystem] after executing a [ToolCallEvent].
/// Consumed by [processToolResultsSystem] to store as a Beat.
class ToolResultEvent implements EcsEvent {
  const ToolResultEvent({required this.actorEntity, required this.result});
  final Entity actorEntity;
  final ToolExecutionResult result;
}

// ─────────────────────────────────────────────
// World tool bridge (Bevy-style task)
// ─────────────────────────────────────────────

/// Routes every tool call through the ECS world.
///
/// Wraps a [ToolRegistry] so that when a backend executes a tool natively
/// (e.g. Apple Foundation), the call is sent to the world as a
/// [ToolCallEvent], the caller suspends on a [Completer], and resumes when
/// [toolExecutionSystem] resolves the task. This unifies native and raw
/// tool lifecycles — the world is the backbone, not the backend.
class WorldToolBridge {
  WorldToolBridge({
    required this.world,
    required this.actorEntity,
    required this.source,
  });

  final World world;
  final Entity actorEntity;
  final ToolRegistry source;

  /// Build a [ToolRegistry] whose tool executions route through the world.
  ToolRegistry buildRegistry() {
    final bridged = ToolRegistry();
    for (final tool in source.tools.values) {
      bridged.register(
        ToolDef(
          name: tool.name,
          description: tool.description,
          argsSchema: tool.argsSchema,
          execute: (args) => _routeToolCall(tool, args),
        ),
      );
    }
    return bridged;
  }

  Future<String> _routeToolCall(ToolDef tool, Object? args) {
    final taskId = TaskId.create();
    final innerCompleter = Completer<ToolExecutionResult>();
    final outsideCompleter = Completer<String>();

    world.getResource<TaskRegistryResource>().register(
      taskId,
      TaskHandle(completer: innerCompleter),
    );

    world.events.writer<ToolCallEvent>().send(
      ToolCallEvent(
        actorEntity: actorEntity,
        call: ToolCall(name: tool.name, arguments: _asMap(args)),
        taskId: taskId,
      ),
    );

    unawaited(
      innerCompleter.future.then((result) {
        outsideCompleter.complete(result.output);
      }),
    );

    return outsideCompleter.future;
  }

  static Map<String, dynamic> _asMap(Object? args) {
    if (args is Map<String, dynamic>) return args;
    if (args is Map) {
      return args.map((k, v) => MapEntry('$k', v));
    }
    return {'value': args};
  }
}
