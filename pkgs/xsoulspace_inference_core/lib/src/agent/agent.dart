import 'dart:developer';

import 'package:ecsly/ecsly.dart';
import 'package:equatable/equatable.dart';
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

import '../inference_client.dart';
import '../models/inference_models.dart';

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
/// - AgentTools - intents / intentcalls?
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

  Future<String> generateText({
    required String content,
    required List<Object> contextFragments,
    required String systemPrompt,
  }) async {
    final response = await client.infer(
      InferenceRequest(
        outputSchema: {
          'type': 'object',
          'properties': {
            'answer': {'type': 'string'},
          },
        },
        workingDirectory: '/tmp',
        prompt: content,
        systemPrompt: systemPrompt,
        task: InferenceTask.implicitlyStructuredText,
        contextFragments: contextFragments,
        metadata: {},
      ),
    );
    final data = response.data;
    final output = data?.output;
    final rawOutput = data?.rawOutput;

    if (output == null) {
      log('Output is null');
      return rawOutput ?? '';
    }
    try {
      final answer =
          output['answer'] ?? (output['properties'] as Map)['answer'];
      if (answer == null) {
        log('Answer is null');
        return rawOutput ?? '';
      }
      return answer;
      // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      log('wrong structure $e', stackTrace: st);
      return rawOutput ?? '';
    }
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

enum ContextFragmentType { systemPrompt, userMessage, modelResponse }

class InMemoryAgentMemoryStorage
    extends MutableOrderedMap<ContextFragmentType, Object>
    implements AgentMemoryStorage {
  @override
  void addEntry(ContextFragmentType type, Object value) =>
      upsert(value, key: type);

  @override
  List<Object> getAllOrdered() => orderedValues;
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

  Future<TResponse> generate<TContent extends Object, TResponse extends Object>(
    TContent content, {
    required String Function(TContent content) contentToJson,
    required TResponse Function(String json) responseFromJson,
  }) async {
    final str = contentToJson(content);
    final modelRuntime = await context.modelRouter.waitAndGetRuntimeModel(
      config.model,
    );
    final allContextFragments = runtimeMemories.getAll();
    final json = await modelRuntime.generateText(
      content: str,
      systemPrompt: config.systemPrompt,
      contextFragments: allContextFragments,
    );
    runtimeMemories
      ..addUserInput(str)
      ..addModelResponse(json);
    final response = responseFromJson(json);
    return response;
  }

  Future<String> sendTextMessage(
    final String message, {
    bool accumulate = false,
  }) async {
    final response = await generate(
      message,
      contentToJson: (m) => m,
      responseFromJson: (json) => json,
    );
    return response;
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

  Agent createAgent({AgentConfig config = AgentConfig.empty}) {
    final agent = Agent(
      context: context,
      config: config,
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
  }) async {
    final response = await agent.generate(
      content,
      contentToJson: contentToJson,
      responseFromJson: responseFromJson,
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
    AgentConfig config = AgentConfig.empty,
    bool disposeAfterCompletion = false,
  }) async {
    final agent = runtime.createAgent(config: config);
    final response = await runtime.generateContent(
      agent,
      message,
      contentToJson: (m) => m,
      responseFromJson: (json) => json,
    );
    if (disposeAfterCompletion) runtime.disposeAgent(agent);
    return (text: response, agent: agent);
  }

  /// message -> response
  Future<String> proceedTextForAgent({
    required final String message,
    required Agent agent,
  }) async {
    final response = await runtime.generateContent(
      agent,
      message,
      contentToJson: (m) => m,
      responseFromJson: (json) => json,
    );
    return response;
  }

  void dispose() {
    runtime.dispose();
  }
}
