/// A minimal embeddable host for the agent harness.
///
/// The host owns no terminal and no input loop. Applications call [feed] when
/// the user submits text, listen to [output] for model deltas, and can cancel
/// the current turn explicitly.
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';

import 'data_models/data_models.dart';
import 'events.dart';
import 'harness_loop.dart';
import 'resources/resources.dart';
import 'tools/tool_registry.dart';

typedef ToolConfirmationCallback =
    Future<bool> Function(ToolName name, Object? arguments);

class CliHostConfig {
  const CliHostConfig({
    this.toolRegistryName = 'default',
    this.confirmationRequiredTools = const {},
  });

  final String toolRegistryName;
  final Set<String> confirmationRequiredTools;
}

class CliHost {
  CliHost({
    required this.world,
    required this.requestToolConfirmation,
    this.config = const CliHostConfig(),
  }) : _loop = HarnessLoop(world: world) {
    _installConfirmationRegistry();
  }

  final World world;
  final CliHostConfig config;
  final ToolConfirmationCallback requestToolConfirmation;

  final HarnessLoop _loop;
  final StreamController<String> _output = StreamController.broadcast();
  Timer? _eventTimer;
  Completer<void>? _idleTurn;

  bool get isRunning => _running;
  var _running = false;

  /// Stop the background harness loop without cancelling in-flight tasks.
  ///
  /// Intended for embedding applications and integration tests that own the
  /// process lifecycle; user cancellation remains [cancel].
  Future<void> stop() async {
    _loop.stop();
    _loop.wakeup();
    while (isRunning) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Deltas from every actor. Hosts may filter by actor if they render
  /// multiple conversations; the everyday single-actor case does not need to.
  Stream<String> get output => _output.stream;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _subscribeToStreamEvents();
    try {
      await _loop.start();
    } finally {
      _running = false;
      _eventTimer?.cancel();
      _eventTimer = null;
      if (!_output.isClosed) {
        await _output.close();
      }
    }
  }

  /// Insert user text as an [OpenDecision] on the first idle actor.
  ///
  /// Returns false when every actor already has agency or work in flight.
  bool feed(String input) {
    if (input.trim().isEmpty) return false;

    for (final (entity, _, _) in world.query2<Actor, OpenDecision>().toList()) {
      if (entity.has<Agency>() || entity.has<AwaitingResponse>()) continue;
      entity.insert(OpenDecision(prompt: input));
      world.flush();
      _loop.wakeup();
      return true;
    }

    final idleActors = world.query2<Actor, ActorModel>().toList();
    if (idleActors.isEmpty) return false;

    idleActors.first.$1.insert(OpenDecision(prompt: input));
    world.flush();
    _loop.wakeup();
    return true;
  }

  /// Cancel in-flight generation and release actor agency.
  ///
  /// Pending tasks are completed with a cancellation error, then removed.
  /// The next harness tick sees no agency and no awaiting response.
  void cancel() {
    final taskRegistry = world.getResource<TaskRegistryResource>();
    for (final taskId in taskRegistry.tasks.keys.toList()) {
      final handle = taskRegistry.take(taskId);
      if (handle == null) continue;
      handle.completer.future.ignore();
      if (!handle.completer.isCompleted) {
        handle.completer.completeError(StateError('Cancelled by host'));
      }
    }

    for (final (entity, _, _) in world.query2<Actor, Agency>().toList()) {
      entity.remove<Agency>();
    }
    for (final (entity, _, _)
        in world.query2<Actor, AwaitingResponse>().toList()) {
      entity.remove<AwaitingResponse>();
    }
    world.flush();
    _loop.wakeup();
    _completeIdleTurn();
  }

  Map<Entity, Situation> inspectSituation() {
    final situations = <Entity, Situation>{};
    for (final (entity, _, _, situation)
        in world.query3<Actor, Agency, Situation>().toList()) {
      situations[entity.entity] = situation;
    }
    return situations;
  }

  void _subscribeToStreamEvents() {
    for (final (entity, _, _) in world.query2<Actor, ActorModel>().toList()) {
      world
          .getResource<StreamingTapResource>()
          .subscribe(entity.entity)
          .listen(_output.add, onError: _output.addError);
    }
  }

  Future<void> waitForIdle() {
    if (_loop.canSleep()) return Future.value();
    return (_idleTurn ??= Completer<void>()).future;
  }

  void _completeIdleTurn() {
    if (!_loop.canSleep()) return;
    final completer = _idleTurn;
    _idleTurn = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _installConfirmationRegistry() {
    final registries = world.getResource<ToolRegistryResource>();
    final source = registries.get(config.toolRegistryName);
    if (source == null || config.confirmationRequiredTools.isEmpty) return;

    final guarded = ToolRegistry();
    for (final tool in source.tools.values) {
      guarded.register(
        config.confirmationRequiredTools.contains(tool.name.value)
            ? ToolDef(
                name: tool.name,
                description: tool.description,
                argsSchema: tool.argsSchema,
                execute: (arguments) async {
                  final approved = await requestToolConfirmation(
                    tool.name,
                    arguments,
                  );
                  if (!approved) {
                    return '{"error":"Tool ${tool.name.value} was rejected '
                        'by the user"}';
                  }
                  return tool.execute(arguments);
                },
              )
            : tool,
      );
    }
    registries.register(config.toolRegistryName, guarded);
  }
}
