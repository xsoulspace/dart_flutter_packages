import 'dart:convert';
import 'dart:developer';

import 'package:ecsly/ecsly.dart';
import 'package:equatable/equatable.dart';
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

import '../inference_client.dart';
import '../models/inference_models.dart';
import 'structured_output/structured_output.dart';
import 'tool_call_parser.dart';

export 'structured_output/structured_output.dart';
export 'tool_call_parser.dart';

/// Any ML model
class Model {
  const Model({
    this.id = ModelId.empty,
    this.name = DefaultModelNames.appleFoundation,
  });
  static const empty = Model();
  final ModelId id;
  final ModelName name;
}

/// name of model
///
/// prefer to use deinitive enumeration like:
/// ```dart
/// enum ModelNames implements ModelName{
///
/// }
/// ```
abstract class ModelName implements Enum {}

enum DefaultModelNames implements ModelName { appleFoundation }

/// generated uuid
extension type const ModelId(String value) {
  //TODO(arenukvern): add uuid
  factory ModelId.create() => ModelId('${DateTime.now()}');
  static const empty = ModelId('');
}

/// organized and contiuos information
/// about agent goals, plans, history etc..
class ModelContextWindow {
  const ModelContextWindow();
  static const empty = ModelContextWindow();
}

typedef InferenceClientsBuilders = Map<ModelName, InferenceClientBuilder>;
typedef InferenceClientBuilder = InferenceClient Function();

/// the chooser of models
class ModelRouter {
  /// it is important to pass not const empty maps,
  /// because directly mutable
  ModelRouter({
    InferenceClientsBuilders? inferenceClientsBuilders,
    Map<ModelId, Model>? models,
    Map<ModelId, ModelRuntime>? runtimes,
  }) : inferenceClientsBuilders = inferenceClientsBuilders ?? {},
       models = models ?? {},
       runtimes = runtimes ?? {};

  final InferenceClientsBuilders inferenceClientsBuilders;
  Map<ModelId, Model> models;
  Map<ModelId, ModelRuntime> runtimes;

  Future<ModelRuntime> waitAndGetRuntimeModel(Model model) async {
    final runtime = runtimes[model.id] ??= await initRuntime(model);

    return runtime;
  }

  Future<ModelRuntime> initRuntime(Model model) async {
    final client = inferenceClientsBuilders[model.name]?.call();
    if (client == null) {
      throw ArgumentError.notNull(
        'inference client is not created for ${model.name}',
      );
    }

    final runtime = await ModelRuntime.initFromInference(
      model: model,
      client: client,
    );

    return runtime;
  }

  final ModelId _cursor = ModelId.empty;
  final int _cursorIndex = 0;

  // /// returns available model and moves cursor for next available
  // Model getAvailableModel() {
  //   final currentModel = models[_cursor] ?? Model.empty;
  //   if (currentModel.isNotAvailable) {}
  //   return currentModel;
  // }
}

/// 1 intance [ModelRuntime] holds:
/// - 1 only ML/LM [Model] and its [ModelContextWindow]
/// - orginized and contiuos information
/// about model goals, plans, history etc..
/// - AgentRegistry - intents / intentcalls?
///
/// ```markdown
/// Tool Registry (code, projections (MCP, CLI, intents))
///         ↓
/// Schema Normalizer (for Non-Native, OpenAI / Hermes / Gemma / LiteRT / …)
///         ↓
/// Prompt / Request Builder (adapts to model family + constraints)
///         ↓
/// Model Backend (Ollama, llama.cpp, LiteRT-LM, MLX, …)
///         ↓
/// Robust Parser + Recovery + Arguments coercing
/// (paired with Schema Normalizer)
///         ↓
/// Executor (sandbox, permissions, observability)
///         ↓
/// Observation → back into conversation state
/// ```
class ModelRuntime {
  ModelRuntime({
    required this.model,
    required this.client,
    this.context = ModelContextWindow.empty,
  });
  final Model model;
  final ModelContextWindow context;
  final InferenceClient client;
  bool get isRunning => client.isAvailable;

  static Future<ModelRuntime> initFromInference({
    required Model model,
    required InferenceClient client,
  }) async {
    final runtime = ModelRuntime(model: model, client: client);
    await runtime.load();
    return runtime;
  }

  Future<void> load() async {
    await client.load();
    await client.refreshAvailability();
  }

  Future<InferenceResponse?> generateStructuredText({
    required String prompt,
    required List<Object> contextFragments,
    required String systemPrompt,
    required SchemaBundle outputSchema,
  }) async {
    final response = await client.infer(
      InferenceRequest.structured(
        outputSchema: outputSchema,
        workingDirectory: '/tmp',
        prompt: prompt,
        systemPrompt: systemPrompt,
        task: InferenceTask.nativelyStructuredText,
        contextFragments: contextFragments,
        metadata: {},
      ),
    );
    final data = response.data;
    log('Output is ${data?.output}');
    return data;
  }
}

/// there is two loops:
/// 1. [ModelMessageLoop]
/// 2. [ModelRuntimeLoop]
abstract class ModelLoop {}

/// user / tool result -> increase context window -> response -> etc..
class ModelMessageLoop implements ModelLoop {
  ModelMessageLoop({required this.runtime});
  final ModelRuntime runtime;
  void flush() {}
}

/// manages ability to keep runtime agent, while
/// controlling its context, context compression, agent restarts and
/// knowledge passings..
class ModelRuntimeLoop implements ModelLoop {
  ModelRuntimeLoop({required this.runtime});
  final ModelRuntime runtime;

  void flush() {}
}

/// migrate to ecsly column storage
abstract class AgentMemoryStorage {
  const AgentMemoryStorage();
  void addEntry(ContextFragmentType type, Object value) {
    throw UnimplementedError();
  }

  List<Object> getAllOrdered() {
    throw UnimplementedError();
  }
}

class VoidAgentMemoryStorage extends AgentMemoryStorage {
  const VoidAgentMemoryStorage();
}

enum ContextFragmentType {
  systemPrompt,
  userMessage,
  modelResponse,
  toolMessage,
}

class InMemoryAgentMemoryStorage
    extends MutableOrderedList<(ContextFragmentType, Object)>
    implements AgentMemoryStorage {
  @override
  void addEntry(ContextFragmentType type, Object value) => add((type, value));

  @override
  List<Object> getAllOrdered() => map(
    (e) =>
        'role:${switch (e.$1) {
          .systemPrompt => 'system',
          .userMessage => 'user',
          .modelResponse => 'model',
          .toolMessage => 'tool',
        }}'
        '|content:${e.$2}',
  ).toList();
}

abstract class AgentMemories {
  const AgentMemories({this.storage = const VoidAgentMemoryStorage()});
  final AgentMemoryStorage storage;

  void addSystemPrompt(Object value) =>
      storage.addEntry(ContextFragmentType.systemPrompt, value);
  void addUserInput(Object value) =>
      storage.addEntry(ContextFragmentType.userMessage, value);
  void addModelResponse(Object value) =>
      storage.addEntry(ContextFragmentType.modelResponse, value);
  void addToolMessage(Object value) =>
      storage.addEntry(ContextFragmentType.toolMessage, value);

  List<Object> getAll() => storage.getAllOrdered();
}

/// persits only per runtime agent (not shared between)
class AgentRuntimeMemories extends AgentMemories {
  const AgentRuntimeMemories({super.storage});
}

/// persists across multiple runtimes
class AgentSharedMemories extends AgentMemories {
  const AgentSharedMemories({super.storage});
}

extension type const AgentId(String value) {
  //TODO(arenukvern): add uuid
  factory AgentId.create() => AgentId('${DateTime.now()}');
  static const empty = AgentId('');
}

class AgentConfig {
  const AgentConfig({this.model = Model.empty, this.systemPrompt = ''});
  static const empty = AgentConfig();
  final Model model;
  final String systemPrompt;
}

/// aka thread aka lead aka main aka orchestrator
///
/// controls [ModelLoop]s and through that - [ModelRuntime]
class Agent with Equatable {
  const Agent({
    required this.context,
    required this.toolRegistry,
    this.runtimeMemories = const AgentRuntimeMemories(),
    this.sharedMemories = const AgentSharedMemories(),
    this.config = AgentConfig.empty,
    this.id = AgentId.empty,
  });
  final AgentRuntimeMemories runtimeMemories;
  final AgentSharedMemories sharedMemories;
  final AgentConfig config;
  final AgentId id;
  final AIRuntimeContext context;
  final ToolRegistry toolRegistry;

  Future<TResponse> generate<TContent extends Object, TResponse extends Object>(
    TContent content, {
    required SchemaBundle outputSchema,
    required String Function(TContent content) contentToJson,
    required TResponse Function(String json) responseFromJson,
  }) async {
    final modelRuntime = await context.modelRouter.waitAndGetRuntimeModel(
      config.model,
    );
    final userStr = contentToJson(content);
    runtimeMemories.addUserInput(userStr);

    final state = ToolRuntimeState();
    final systemPrompt = buildSystemPrompt(toolRegistry, config.systemPrompt);

    while (true) {
      // Force termination path
      if (state.reachedLimit) {
        runtimeMemories.addModelResponse(
          'You have reached the maximum number of tool steps. '
          'Answer the user now using only the information you already have. '
          'Do not emit any more tool tags.',
        );
      }
      final memories = runtimeMemories.getAll();
      log(jsonEncode(memories));

      final json = await modelRuntime.generateStructuredText(
        prompt: userStr, // or whatever your API expects
        systemPrompt: systemPrompt,
        contextFragments: memories,
        outputSchema: outputSchema,
      );
      final output = json?.output;
      final rawOutput = json?.rawOutput;
      if (json == null || output == null || rawOutput == null) {
        log('response is empty');
        throw StateError('response is empty');
      }

      runtimeMemories.addModelResponse(output);
      state.step++;

      final tags = ToolTagParser.parse(rawOutput);
      final definitions = tags
          .where((t) => t.type == ToolTagType.getDefinition)
          .toList();
      final calls = tags.where((t) => t.type == ToolTagType.call).toList();

      // Clean final answer
      if (definitions.isEmpty && calls.isEmpty) {
        return responseFromJson(rawOutput);
      }

      // 1. Progressive schema disclosure
      for (final def in definitions) {
        if (state.knownSchemas.contains(def.toolName)) continue;

        final schema = toolRegistry.getSchema(def.toolName);
        if (schema == null) {
          runtimeMemories.addToolMessage(
            '<result|${def.toolName}|{"error":"Unknown tool"}>',
          );
          continue;
        }

        final resultTag = '<result|${def.toolName}|${jsonEncode(schema)}>';
        runtimeMemories.addToolMessage(resultTag);
        state.knownSchemas.add(def.toolName);
      }

      // 2. Execute calls (supports multiple + same tool with different args)
      for (final call in calls) {
        final args = call.payload ?? <String, dynamic>{};
        final signature = '${call.toolName}:${jsonEncode(args)}';

        // Allow legitimate re-use, but stop pure spinning
        final previous = state.history
            .where((h) => h.signature == signature)
            .length;
        if (previous >= 2) {
          runtimeMemories.addModelResponse(
            'You already called ${call.toolName} with these exact arguments twice. '
            'Use the previous result or answer the user.',
          );
          continue;
        }

        final result = await toolRegistry.execute(call.toolName, args);
        final resultTag = '<result|${call.toolName}|${jsonEncode(result)}>';
        runtimeMemories.addToolMessage(resultTag);
        state.history.add(CallRecord(signature, result));
      }

      // Gentle nudge after tools
      if (calls.isNotEmpty && !state.reachedLimit) {
        runtimeMemories.addModelResponse(
          'Tool results are available. Continue the conversation or give the final answer. '
          'Only call tools again if you still lack necessary information.',
        );
      }
    }
  }

  Map<String, dynamic> getSchemaFor(ToolTag tool) {
    log('getSchemaFor: ${tool.toolName}');
    return {};
  }

  Object? executeTool(ToolTag tool) {
    log('executeTool: ${tool.toolName}');

    return '84°F°C '
        'Precipitation: 0% '
        'Humidity: 69% '
        'Wind: 8 mph';
  }

  @override
  List<Object?> get props => [id];
  static void disposeStatic(Agent agent) {}
}

class AgentWorlds {
  /// profile later, maybe replace with sparse set of worlds
  final agentWorlds = <AgentId, World>{};

  World getWorld(AgentId agentId) => agentWorlds[agentId] ??= World();
  void removeWorld(AgentId agentId) => agentWorlds.remove(agentId);

  void dispose() {
    for (final world in agentWorlds.values) {
      world.clear();
    }
    agentWorlds.clear();
  }
}

/// context (di) for [AIRuntime]
class AIRuntimeContext {
  AIRuntimeContext({
    ModelRouter? modelRouter,
    AgentWorlds? agentWorlds,
    InferenceClientsBuilders? inferenceClientsBuilders,
  }) : modelRouter =
           modelRouter ??
           ModelRouter(
             inferenceClientsBuilders: inferenceClientsBuilders ?? {},
           ),
       agentWorlds = agentWorlds ?? AgentWorlds();

  final agentsPool = <Agent>{};
  final AgentWorlds agentWorlds;
  final ModelRouter modelRouter;

  void dispose() {
    agentsPool
      ..forEach(Agent.disposeStatic)
      ..clear();
  }
}

class AIRuntimeConfig {
  const AIRuntimeConfig({this.inferenceClientBuilders = const {}});
  final InferenceClientsBuilders inferenceClientBuilders;
}

/// starting point of managing agents runtimes
class AIRuntime {
  AIRuntime({this.config = const AIRuntimeConfig(), AIRuntimeContext? context})
    : context =
          context ??
          AIRuntimeContext(
            inferenceClientsBuilders: config.inferenceClientBuilders,
          );
  final AIRuntimeConfig config;
  AIRuntimeContext context;

  Agent createAgent({
    required ToolRegistry toolRegistry,
    AgentConfig config = AgentConfig.empty,
  }) {
    final agent = Agent(
      context: context,
      config: config,
      toolRegistry: toolRegistry,
      runtimeMemories: AgentRuntimeMemories(
        storage: InMemoryAgentMemoryStorage(),
      ),
    );
    context.agentsPool.add(agent);
    return agent;
  }

  void disposeAgent(Agent agent) {
    context.agentsPool.remove(agent);
  }

  Future<TResponse>
  generateContent<TContent extends Object, TResponse extends Object>(
    Agent agent,
    TContent content, {
    required String Function(TContent content) contentToJson,
    required TResponse Function(String json) responseFromJson,
    required SchemaBundle outputSchema,
  }) async {
    final response = await agent.generate(
      content,
      contentToJson: contentToJson,
      responseFromJson: responseFromJson,
      outputSchema: outputSchema,
    );
    return response;
  }

  void dispose() {
    context.dispose();
  }
}

class AIWorld {
  AIWorld({AIRuntime? runtime}) : runtime = runtime ?? AIRuntime();
  factory AIWorld.fromConfigs({AIRuntimeConfig? runtimeConfig}) => AIWorld(
    runtime: AIRuntime(config: runtimeConfig ?? const AIRuntimeConfig()),
  );
  final AIRuntime runtime;

  /// message -> response
  Future<({String text, Agent agent})> sendTextMessage({
    required final String message,
    SchemaBundle outputSchema = SchemaBundle.string,
    AgentConfig config = AgentConfig.empty,
    bool disposeAfterCompletion = false,
    ToolRegistry? toolRegsitry,
  }) async {
    final agent = runtime.createAgent(
      config: config,
      toolRegistry: toolRegsitry ?? ToolRegistry(),
    );
    final response = await runtime.generateContent(
      agent,
      message,
      contentToJson: (m) => m,
      responseFromJson: (json) => json,
      outputSchema: outputSchema,
    );
    if (disposeAfterCompletion) runtime.disposeAgent(agent);
    return (text: response, agent: agent);
  }

  /// message -> response
  Future<String> proceedTextForAgent({
    required final String message,
    required Agent agent,
    SchemaBundle outputSchema = SchemaBundle.string,
  }) async {
    final response = await runtime.generateContent(
      agent,
      message,
      contentToJson: (m) => m,
      responseFromJson: (json) => json,
      outputSchema: outputSchema,
    );
    return response;
  }

  void dispose() {
    runtime.dispose();
  }
}
