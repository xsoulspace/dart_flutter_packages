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
  });
}
