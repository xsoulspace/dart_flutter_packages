// ignore_for_file: lines_longer_than_80_chars

/// Headless harness test: proves the agent routing + coding-agent tools work
/// end-to-end WITHOUT an LLM.
///
/// This is the "even without llm, the routing, basic tools for coding agents
/// (read, write, etc..) works as expected" proof. It drives the ECS world
/// through the schedules, injects an [OpenDecision], and verifies that a
/// tool call (read/write) dispatched by a [GenerationHandler] is executed by
/// the world's [toolExecutionSystem] and the result lands in the actor's
/// memory — with no real model involved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A [GenerationHandler] that simulates an LLM emitting a tool call.
///
/// Instead of calling a real model, it reads the [ActorGenerateRequest]'s
/// tool registry, emits a single [ToolCall] (read or write), and sends the
/// response back to the world. This proves the harness routing works without
/// any LLM backend.
class _ToolEmittingHandler implements GenerationHandler {
  _ToolEmittingHandler({required this.toolName, required this.arguments});

  final String toolName;
  final Map<String, dynamic> arguments;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': 'tool dispatched'},
      rawOutput: 'tool dispatched',
      toolCalls: [ToolCall(name: ToolName(toolName), arguments: arguments)],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// A [GenerationHandler] that records which handler it is and returns a plain
/// text response. Used to prove per-agent handler routing.
class _TaggedHandler implements GenerationHandler {
  _TaggedHandler(this.tag);

  final String tag;
  final List<AgentId> handled = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    handled.add(request.agentId);
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': 'from $tag'},
      rawOutput: 'from $tag',
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// A [GenerationHandler] that returns a STRUCTURED tool call on the response
/// (no tag round-trip) — mirroring what OpenRouter's native tool calling now
/// produces via [InferenceResponse.toolCalls].
class _StructuredToolHandler implements GenerationHandler {
  _StructuredToolHandler({required this.name, required this.arguments});

  final String name;
  final Map<String, dynamic> arguments;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': 'structured tool dispatched'},
      rawOutput: 'structured tool dispatched',
      toolCalls: [ToolCall(name: ToolName(name), arguments: arguments)],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// A [GenerationHandler] that records which model it served. Used to prove
/// that swapping an actor's [ActorModel] at runtime routes to a different
/// backend (Apple Foundation vs OpenRouter) via the [ModelRouter].
class _ModelTaggedHandler implements GenerationHandler {
  _ModelTaggedHandler(this.tag);

  final String tag;
  final List<ModelId> served = [];

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    served.add(request.modelId);
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuralOutput: {'text': 'from $tag'},
      rawOutput: 'from $tag',
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

/// Build a world with the agent plugin and a coding-agent tool registry.
Future<World> _buildWorld(ToolRegistry registry) async {
  final world = World()..addPlugin(AgentPlugin());
  final toolResource = ToolRegistryResource();
  toolResource.register('default', registry);
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(toolResource)
    ..flush();
  return world;
}

/// Spawn a scene + actor with an [OpenDecision] and the 'default' tool registry.
Entity _spawnActor(World world, String decision) {
  final scene = world.spawnComponents([const Scene(), SceneFrame()]);
  final actor = world.spawnComponents([
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: ModelId.create()),
    ActorRuntimeMemories(),
    PresentInScene(sceneEntity: scene),
    OpenDecision(prompt: decision),
    const ActorTools(registryName: 'default'),
  ]);
  world.flush();
  return actor;
}

/// Run the full schedule cycle once and drain responses.
Future<void> _runCycle(World world) async {
  world.runSchedule('AgencyGrant');
  world.flush();
  world.runSchedule('Project');
  world.flush();
  await world.runScheduleAsync('ActorAct');
  world.flush();
  world.runSchedule('ProcessResponses');
  world.flush();
  world.runSchedule('Mechanical');
  world.flush();
  // Let async tool execution complete.
  await Future.delayed(const Duration(milliseconds: 50));
  world.runSchedule('Mechanical');
  world.flush();
}

void main() {
  group('headless coding-agent harness (no LLM)', () {
    test('read tool executes and result lands in actor memory', () async {
      final temp = await Directory.systemTemp.createTemp('xsoulspace_harness_');
      addTearDown(() => temp.delete(recursive: true));
      final filePath = '${temp.path}/notes.txt';
      File(filePath).writeAsStringSync('hello world');

      // A read tool that reads a file from disk.
      final registry = ToolRegistry();
      registry.register(
        ToolDef.structured(
          name: ToolName('read'),
          description: 'Read a file',
          parameters: SchemaBundle(
            root: FM.object(
              'read',
              properties: () => [FM.prop('path', FM.string())],
            ),
          ),
          execute: (args) async {
            final params = jsonDecodeMapAs(args);
            final path = jsonDecodeString(params['path']);
            return await File(path).readAsString();
          },
        ),
      );

      final world = await _buildWorld(registry);
      world.getResource<GenerationHandlerResource>().registerDefault(
        _ToolEmittingHandler(toolName: 'read', arguments: {'path': filePath}),
      );
      final actor = _spawnActor(
        world,
        'Read the file and report its contents.',
      );

      await _runCycle(world);

      final memories = world.maybeGetComponent<ActorRuntimeMemories>(actor);
      expect(memories, isNotNull);

      // The tool result must be stored as a toolMessage fragment.
      final toolFragments = memories!.fragments
          .where((f) => f.type == ContextFragmentType.toolMessage)
          .toList();
      expect(toolFragments, isNotEmpty);
      final toolBeat = world.getEntity(toolFragments.first.beat).$1;
      final text = toolBeat.get<TextContent>();
      expect(text, isNotNull);
      expect(text!.text, contains('hello world'));
    });

    test('write tool creates a file through the world', () async {
      final temp = await Directory.systemTemp.createTemp('xsoulspace_harness_');
      addTearDown(() => temp.delete(recursive: true));
      final filePath = '${temp.path}/output.txt';

      final registry = ToolRegistry();
      registry.register(
        ToolDef.structured(
          name: ToolName('write'),
          description: 'Write a file',
          parameters: SchemaBundle(
            root: FM.object(
              'write',
              properties: () => [
                FM.prop('path', FM.string()),
                FM.prop('content', FM.string()),
              ],
            ),
          ),
          execute: (args) async {
            final params = jsonDecodeMapAs(args);
            final path = jsonDecodeString(params['path']);
            final content = jsonDecodeString(params['content']);
            await File(path).writeAsString(content);
            return 'wrote $path';
          },
        ),
      );

      final world = await _buildWorld(registry);
      world.getResource<GenerationHandlerResource>().registerDefault(
        _ToolEmittingHandler(
          toolName: 'write',
          arguments: {'path': filePath, 'content': 'agent wrote this'},
        ),
      );
      final actor = _spawnActor(world, 'Write a file.');

      await _runCycle(world);

      // The file must exist on disk.
      expect(File(filePath).existsSync(), isTrue);
      expect(File(filePath).readAsStringSync(), 'agent wrote this');

      // And the tool result must be in actor memory.
      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
      expect(memories, isNotNull);
      final toolFragments = memories!.fragments
          .where((f) => f.type == ContextFragmentType.toolMessage)
          .toList();
      expect(toolFragments, isNotEmpty);
    });

    test('list_dir tool lists a directory through the world', () async {
      final temp = await Directory.systemTemp.createTemp('xsoulspace_harness_');
      addTearDown(() => temp.delete(recursive: true));
      // Seed two files so the listing has content.
      File('${temp.path}/a.txt').writeAsStringSync('a');
      File('${temp.path}/b.txt').writeAsStringSync('b');

      final registry = ToolRegistry();
      registry.register(
        ToolDef.structured(
          name: ToolName('list_dir'),
          description: 'List a directory',
          parameters: SchemaBundle(
            root: FM.object(
              'list_dir',
              properties: () => [FM.prop('path', FM.string())],
            ),
          ),
          execute: (args) async {
            final params = jsonDecodeMapAs(args);
            final path = jsonDecodeString(params['path']);
            final entries = Directory(
              path,
            ).listSync().map((e) => e.path).toList();
            return jsonEncode(entries);
          },
        ),
      );

      final world = await _buildWorld(registry);
      world.getResource<GenerationHandlerResource>().registerDefault(
        _ToolEmittingHandler(
          toolName: 'list_dir',
          arguments: {'path': temp.path},
        ),
      );
      final actor = _spawnActor(world, 'List the directory.');

      await _runCycle(world);

      // The tool result must be in actor memory and contain both files.
      final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
      expect(memories, isNotNull);
      final toolFragments = memories!.fragments
          .where((f) => f.type == ContextFragmentType.toolMessage)
          .toList();
      expect(toolFragments, isNotEmpty);
      final toolBeat = world.getEntity(toolFragments.first.beat).$1;
      final text = toolBeat.get<TextContent>();
      expect(text, isNotNull);
      expect(text!.text, contains('a.txt'));
      expect(text!.text, contains('b.txt'));
    });

    test('routes each agent to its own GenerationHandler', () async {
      final world = await _buildWorld(ToolRegistry());

      // Two handlers — simulates Apple Foundation + OpenRouter (or any two
      // backends). Each is registered per-agent.
      final appleHandler = _TaggedHandler('apple');
      final openRouterHandler = _TaggedHandler('openrouter');
      final handlerResource = world.getResource<GenerationHandlerResource>();

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actorA = world.spawnComponents([
        Actor(agentId: const AgentId('agent-apple')),
        ActorModel(modelId: ModelId.create()),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
        OpenDecision(prompt: 'Apple decision'),
      ]);
      final actorB = world.spawnComponents([
        Actor(agentId: const AgentId('agent-openrouter')),
        ActorModel(modelId: ModelId.create()),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
        OpenDecision(prompt: 'OpenRouter decision'),
      ]);
      world.flush();

      // Route by agent id — this is the multi-handler proof.
      handlerResource.registerForAgent(
        const AgentId('agent-apple'),
        appleHandler,
      );
      handlerResource.registerForAgent(
        const AgentId('agent-openrouter'),
        openRouterHandler,
      );

      // Run one full cycle — both actors act concurrently.
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();
      world.runSchedule('ProcessResponses');
      world.flush();

      // Each handler handled exactly its own agent.
      expect(appleHandler.handled, [const AgentId('agent-apple')]);
      expect(openRouterHandler.handled, [const AgentId('agent-openrouter')]);

      // Each actor's memory holds the response from its own handler.
      final memoriesA = world.getEntity(actorA).$1.get<ActorRuntimeMemories>();
      final memoriesB = world.getEntity(actorB).$1.get<ActorRuntimeMemories>();
      expect(memoriesA, isNotNull);
      expect(memoriesB, isNotNull);
      final lastA = memoriesA!.fragments.last;
      final lastB = memoriesB!.fragments.last;
      final textA = world.getEntity(lastA.beat).$1.get<TextContent>();
      final textB = world.getEntity(lastB.beat).$1.get<TextContent>();
      expect(textA!.text, contains('apple'));
      expect(textB!.text, contains('openrouter'));
    });

    test(
      'structured tool calls route through the world toolExecutionSystem',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'xsoulspace_harness_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final filePath = '${temp.path}/structured.txt';

        final registry = ToolRegistry();
        registry.register(
          ToolDef.structured(
            name: ToolName('write'),
            description: 'Write a file',
            parameters: SchemaBundle(
              root: FM.object(
                'write',
                properties: () => [
                  FM.prop('path', FM.string()),
                  FM.prop('content', FM.string()),
                ],
              ),
            ),
            execute: (args) async {
              final params = jsonDecodeMapAs(args);
              await File(
                jsonDecodeString(params['path']),
              ).writeAsString(jsonDecodeString(params['content']));
              return 'wrote';
            },
          ),
        );

        final world = await _buildWorld(registry);

        // A handler that returns a STRUCTURED tool call on the response —
        // exactly what OpenRouter now does (no tag round-trip).
        world.getResource<GenerationHandlerResource>().registerDefault(
          _StructuredToolHandler(
            name: 'write',
            arguments: {'path': filePath, 'content': 'structured call'},
          ),
        );
        final actor = _spawnActor(world, 'Write via structured tool call.');

        await _runCycle(world);

        // The world executed the structured tool call and wrote the file.
        expect(File(filePath).existsSync(), isTrue);
        expect(File(filePath).readAsStringSync(), 'structured call');

        // And the tool result landed in actor memory.
        final memories = world.getEntity(actor).$1.get<ActorRuntimeMemories>();
        expect(memories, isNotNull);
        final toolFragments = memories!.fragments
            .where((f) => f.type == ContextFragmentType.toolMessage)
            .toList();
        expect(toolFragments, isNotEmpty);
      },
    );

    test('swaps inference backend at runtime by changing ActorModel', () async {
      final world = await _buildWorld(ToolRegistry());

      // Two handlers registered by model id — simulates Apple Foundation and
      // OpenRouter both being first-class models in the router.
      final appleModelId = const ModelId('model-apple');
      final openRouterModelId = const ModelId('model-openrouter');
      final appleHandler = _ModelTaggedHandler('apple');
      final openRouterHandler = _ModelTaggedHandler('openrouter');
      final handlerResource = world.getResource<GenerationHandlerResource>();
      handlerResource.registerForModel(appleModelId, appleHandler);
      handlerResource.registerForModel(openRouterModelId, openRouterHandler);

      final scene = world.spawnComponents([const Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: appleModelId),
        ActorRuntimeMemories(),
        PresentInScene(sceneEntity: scene),
        OpenDecision(prompt: 'First decision'),
      ]);
      world.flush();

      // First cycle — routes to Apple (model-apple).
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();
      world.runSchedule('ProcessResponses');
      world.flush();
      expect(appleHandler.served, [appleModelId]);
      expect(openRouterHandler.served, isEmpty);

      // Swap the actor's model to OpenRouter at runtime.
      world.upsertComponent(actor, ActorModel(modelId: openRouterModelId));
      world.upsertComponent(actor, OpenDecision(prompt: 'Second decision'));
      world.flush();

      // Second cycle — routes to OpenRouter (model-openrouter).
      world.runSchedule('AgencyGrant');
      world.flush();
      world.runSchedule('Project');
      world.flush();
      await world.runScheduleAsync('ActorAct');
      world.flush();
      world.runSchedule('ProcessResponses');
      world.flush();

      expect(appleHandler.served, [appleModelId]);
      expect(openRouterHandler.served, [openRouterModelId]);
    });
  });
}
