import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_app/ecsly_app.dart';
import 'package:ecsly_flutter/ecsly_flutter.dart';

import 'agent.dart';

/// 1 [Goal] can be assigned to 1 [Agent].
/// 1 [Agent] can have several Goals.
class Agent implements Component {
  const Agent({required this.agentId});
  final AgentId agentId;
}

class AssignedToAgent implements Component {
  const AssignedToAgent({required this.agentId});
  final AgentId agentId;
}

class Goal implements Component {
  Goal({this.text = ''});
  String text;
}

typedef AgentTool = (Agent, ToolName);

class Tool extends ToolName implements Component {
  Tool(super.value, {required this.systemType});
  final ToolSystemType systemType;
}

enum ToolSystemType {
  /// we can safely try to propagate to call a system inside world
  inWorld,

  /// we should call external system / function via event system.
  external,
}

class ToolCallArgs implements Component {
  ToolCallArgs({this.args});
  final Object? args;
}

class AgentPlugin extends Plugin {
  @override
  void install(World world) {
    world.components
      ..registerObjectComponent<Goal>()
      ..registerObjectComponent<Prompt>()
      ..registerObjectComponent<PromptState>()
      ..registerObjectComponent<Tool>()
      ..registerObjectComponent<Agent>();
  }

  @override
  String get name => 'agent-plugin';
}

Future<void> storeToolCalls(World world) async {
  final channel = world.events.channel<QueueToolCallEvent>();
  final events = channel.toReader().drain();

  for (final event in events) {
    world.spawnComponentBundle(
      .fromLists([event.agent, event.args, event.tool]),
    );
  }
}

Future<void> executeToolCalls(World world) async {
  final extEvents = world.events.channel<ExternalToolCallRequestEvent>();
  final intEvents = world.events.channel<InternalToolCallRequestEvent>();
  final all = world.query3<Agent, Tool, ToolCallArgs>();

  for (final (entity, agent, tool, args) in all) {
    // TODO: add limiter
    switch (tool.systemType) {
      case .external:
        extEvents.send(.new(agent: agent, tool: tool, args: args));
      case .inWorld:
        intEvents.send(.new(agent: agent, tool: tool, args: args));
    }
    entity.despawn();
  }
}

class Prompt implements Component {}

class PromptState implements Component {
  PromptState({this.status = PromptStatus.scheduled});
  PromptStatus status;
}

enum PromptStatus { scheduled, inProgress, completed }

Future<void> generate(World world) async {
  final promptsToHandle = world.queryMut3<Prompt, Agent, PromptState>();
  final generationEvents = world.events.channel<AgentGenerateEvent>();
  // TODO: add limiter
  for (final (entity, prompt, agent, state) in promptsToHandle) {
    if (state.status == .inProgress) continue;
    if (state.status == .completed) {
      // TODO: compress, deconstruct and place into memories
      entity.toEntity().despawn();
    }
    generationEvents.send(.new(agent: agent, prompt: prompt));
    state.status = .inProgress;
  }
}

abstract class AgentEvent implements EcsEvent {
  AgentEvent({required this.agent});
  final Agent agent;
}

class AgentGenerateEvent extends AgentEvent {
  AgentGenerateEvent({required this.prompt, required super.agent});
  final Prompt prompt;
}

class QueueToolCallEvent extends AgentEvent {
  QueueToolCallEvent({
    required this.tool,
    required super.agent,
    required this.args,
  });
  final Tool tool;
  final ToolCallArgs args;
}

class ExternalToolCallRequestEvent extends QueueToolCallEvent {
  ExternalToolCallRequestEvent({
    required super.tool,
    required super.agent,
    required super.args,
  });
}

class InternalToolCallRequestEvent extends QueueToolCallEvent {
  InternalToolCallRequestEvent({
    required super.tool,
    required super.agent,
    required super.args,
  });
}

class AIWorld {}
