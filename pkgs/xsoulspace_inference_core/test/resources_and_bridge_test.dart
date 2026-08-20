// ignore_for_file: lines_longer_than_80_chars

/// World resources & cold-value types used by the harness.
///
/// Pure object-level assertions (no ECS schedules): resource storage, the
/// [ActorGenerateRequest]/[ActorGenerateResponse]/[ToolCall] wire shapes, and
/// the [WorldToolBridge] native-routing path.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'support/agent_harness_support.dart';

void main() {
  group('ModelRouterResource', () {
    test('wraps a ModelRouter and is retrievable', () {
      final world = World()..addPlugin(AgentPlugin());
      final router = ModelRouter();
      world.upsertResource(ModelRouterResource(router));
      world.flush();

      final resource = world.getResource<ModelRouterResource>();
      expect(resource.router, same(router));
    });
  });

  group('ToolRegistryResource', () {
    test('registers and retrieves named tool registries', () {
      final resource = ToolRegistryResource();
      final registry = ToolRegistry();
      resource.register('default', registry);

      expect(resource.get('default'), same(registry));
      expect(resource.get('nonexistent'), isNull);
    });
  });

  group('ActorGenerateRequest', () {
    test('carries all fields needed for LLM generation', () {
      final entity = Entity.create(1);
      final request = ActorGenerateRequest(
        actorEntity: entity,
        agentId: const AgentId('agent-1'),
        modelId: const ModelId('model-1'),
        prompt: 'What is 2+2?',
        systemPrompt: 'You are a calculator.',
        contextFragments: ['systemPrompt:You are a calculator.'],
        schema: SchemaBundle.empty,
        toolRegistry: null,
        task: InferenceTask.text,
        taskId: const TaskId('task-1'),
      );

      expect(request.actorEntity, entity);
      expect(request.agentId.value, 'agent-1');
      expect(request.modelId.value, 'model-1');
      expect(request.prompt, 'What is 2+2?');
      expect(request.systemPrompt, 'You are a calculator.');
      expect(request.contextFragments, ['systemPrompt:You are a calculator.']);
      expect(request.schema, SchemaBundle.empty);
      expect(request.toolRegistry, isNull);
      expect(request.task, InferenceTask.text);
    });
  });

  group('ActorGenerateResponse', () {
    test('carries output, rawOutput, and toolCalls', () {
      final entity = Entity.create(1);
      final response = ActorGenerateResponse(
        actorEntity: entity,
        structuralOutput: {'text': '4'},
        rawOutput: '4',
        toolCalls: [
          ToolCall(name: ToolName('calc'), arguments: {'expr': '2+2'}),
        ],
      );

      expect(response.actorEntity, entity);
      expect(response.structuralOutput, {'text': '4'});
      expect(response.rawOutput, '4');
      expect(response.toolCalls.length, 1);
      expect(response.toolCalls.first.name.value, 'calc');
      expect(response.toolCalls.first.arguments, {'expr': '2+2'});
    });
  });

  group('ToolCall', () {
    test('holds name and arguments', () {
      final call = ToolCall(
        name: ToolName('search'),
        arguments: {'query': 'weather'},
      );
      expect(call.name.value, 'search');
      expect(call.arguments, {'query': 'weather'});
    });
  });

  group('WorldToolBridge (native tool routing)', () {
    test(
      'routes a native tool call through the world and resolves the task',
      () async {
        final toolRegistry = ToolRegistry();
        final toolDef = ToolDef(
          name: ToolName('echo'),
          description: 'Echoes the input',
          parameters: const {},
          execute: (args) async => {'echoed': args},
        );
        toolRegistry.register(toolDef);

        final toolResource = ToolRegistryResource();
        toolResource.register('default', toolRegistry);

        final world = await buildTestWorld(toolRegistryResource: toolResource);
        final scene = spawnScene(world);
        final actor = spawnActor(world, scene);
        world.upsertComponent(actor, const ActorTools(registryName: 'default'));
        world.flush();

        // Build a bridged registry — simulates the backend executing a native
        // tool call through the world (Apple Foundation native path).
        final bridge = WorldToolBridge(
          world: world,
          actorEntity: actor,
          source: toolRegistry,
        );
        final bridged = bridge.buildRegistry();

        // Invoke — suspends until the world resolves the task.
        final future = bridged.execute(ToolName('echo'), {'message': 'hi'});

        final reader = world.events.reader<ToolCallEvent>();
        expect(reader.isNotEmpty, isTrue);
        expect(reader.length, 1);
        expect(reader.readAt(0).call.name.value, 'echo');
        expect(reader.readAt(0).taskId, isNotNull);

        world.runSchedule('Mechanical');
        world.flush();
        await Future.delayed(const Duration(milliseconds: 50));

        final result = await future;
        expect(result, isNotNull);
        expect((result as ToolExecutionResult).name, 'echo');
        expect(result.output, {
          'echoed': {'message': 'hi'},
        });

        // The task was resolved and removed from the registry.
        expect(world.getResource<TaskRegistryResource>().isEmpty, isTrue);
      },
    );
  });
}
