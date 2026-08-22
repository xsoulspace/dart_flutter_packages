import 'package:ecsly/ecsly.dart';

import '../../xsoulspace_inference_core.dart';
import 'model_router.dart';
import 'events.dart';
import 'resources/resources.dart';

// ─────────────────────────────────────────────
// Default generation handler
// ─────────────────────────────────────────────

/// Default handler that uses [ModelRouterResource] to resolve models
/// and call the inference client directly.
///
/// ## Backend-agnostic tool handling
///
/// All tool calls route through the world. The handler wraps the actor's
/// [ToolRegistry] in a [WorldToolBridge] before passing it to the model:
///
/// - **Apple Foundation (native)**: The model executes tools during
///   generation. Each call fires the bridge, which sends a [ToolCallEvent]
///   to the world and suspends until [toolExecutionSystem] resolves it.
/// - **Raw LLM backends**: The model emits tool tags in text; the handler
///   parses them into [toolCalls] for the world's [toolExecutionSystem].
///
/// The handler NEVER executes tools itself — that's the ECS layer's job.
class DefaultGenerationHandler implements GenerationHandler {
  DefaultGenerationHandler({ModelRouter? router}) : _router = router;

  ModelRouter? _router;

  ModelRouter? get router => _router;

  set router(ModelRouter value) {
    _router = value;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final router = _router;
    if (router == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuralOutput: {},
        rawOutput: '',
        taskId: request.taskId,
      );
    }

    // Resolve the model from the router's registered models
    final model = router.models[request.modelId] ?? Model(id: request.modelId);

    final runtime = await router.waitAndGetRuntimeModel(model);

    // Bridge tools through the world so native tool calls route through ECS.
    final bridgedRegistry = request.toolRegistry != null
        ? WorldToolBridge(
            world: world,
            actorEntity: request.actorEntity,
            source: request.toolRegistry!,
          ).buildRegistry()
        : null;

    // Stream deltas into the world when the backend supports it: each chunk
    // lands as an ActorGenerateStreamEvent (accumulated into StreamingBeat by
    // processStreamEventsSystem) and is pushed to host subscribers via
    // StreamingTapResource. Structured-output and tool-calling requests stay
    // on the blocking path — streaming is text-only.
    final canStream = request.schema.isEmpty && request.toolRegistry == null;
    final tap = world.getResource<StreamingTapResource>();

    final response = await runtime.generate(
      prompt: request.prompt,
      systemPrompt: request.systemPrompt,
      contextFragments: request.contextFragments,
      outputSchema: request.schema,
      toolRegistry: bridgedRegistry,
      task: request.task,
      onDelta: canStream
          ? (delta) {
              world.events.writer<ActorGenerateStreamEvent>().send(
                ActorGenerateStreamEvent(
                  actorEntity: request.actorEntity,
                  taskId: request.taskId,
                  chunk: delta,
                ),
              );
              tap.publish(request.actorEntity, delta);
            }
          : null,
    );

    if (response == null) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuralOutput: {},
        rawOutput: '',
        taskId: request.taskId,
      );
    }

    // Tool calls. Prefer the structured calls parsed by the inference client
    // (native tool calling — OpenRouter, OpenAI, Apple Foundation). For raw/
    // legacy backends that emit `<call|...>` tags in rawOutput, fall back to
    // the tag parser. The client owns wire-format parsing; ecsly stays
    // structured + raw output. Tool execution always happens in the world
    // (toolExecutionSystem) — the handler never executes tools itself.
    final toolCalls = response.toolCalls.isNotEmpty
        ? response.toolCalls
        : parseToolCalls(response.rawOutput ?? '');

    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: response.structuredOutput,
      rawOutput: response.rawOutput ?? '',
      toolCalls: toolCalls,
      taskId: request.taskId,
    );
  }
}
