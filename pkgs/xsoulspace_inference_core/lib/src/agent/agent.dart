import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:equatable/equatable.dart';

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
  ModelRouter({
    required this.inferenceClientsBuilders,
    this.models = const {},
    this.runtimes = const {},
  });
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

  Future<String> generateText(String content) async {
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
        metadata: {},
      ),
    );

    return jsonEncode(response.data?.output);
  }
}

/// there is two loops:
/// 1. [ModelMessageLoop]
/// 2. [ModelRuntimeLoop]
abstract class ModelLoop {}

/// user / tool result -> increase context window -> response -> etc..
class ModelMessageLoop implements ModelLoop {}

/// manages ability to keep runtime agent, while
/// controlling its context, context compression, agent restarts and
/// knowledge passings..
class ModelRuntimeLoop implements ModelLoop {}

abstract class AgentMemoryStorage {}

class VoidAgentMemoryStorage implements AgentMemoryStorage {
  const VoidAgentMemoryStorage();
}

abstract class AgentMemories {
  const AgentMemories({this.storage = const VoidAgentMemoryStorage()});
  final AgentMemoryStorage storage;
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
  const AgentConfig({this.model = Model.empty});
  final Model model;
}

/// aka thread aka lead aka main aka orchestrator
///
/// controls [ModelLoop]s and through that - [ModelRuntime]
class Agent with Equatable {
  const Agent({
    required this.context,
    this.runtimeMemories = const AgentRuntimeMemories(),
    this.sharedMemories = const AgentSharedMemories(),
    this.config = const AgentConfig(),
    this.id = AgentId.empty,
  });
  final AgentRuntimeMemories runtimeMemories;
  final AgentSharedMemories sharedMemories;
  final AgentConfig config;
  final AgentId id;
  final AIRuntimeContext context;

  Future<TResponse> generate<TContent, TResponse>(
    TContent content, {
    required String Function(TContent content) contentToJson,
    required TResponse Function(String json) responseFromJson,
  }) async {
    final str = contentToJson(content);
    final modelRuntime = await context.modelRouter.waitAndGetRuntimeModel(
      config.model,
    );
    final json = await modelRuntime.generateText(str);
    final response = responseFromJson(json);
    return response;
  }

  @override
  List<Object?> get props => [id];
  static void disposeStatic(Agent agent) {}
}

/// context (di) for [AIRuntime]
class AIRuntimeContext {
  AIRuntimeContext({ModelRouter? modelRouter})
    : modelRouter = modelRouter ?? ModelRouter(inferenceClientsBuilders: {});
  factory AIRuntimeContext.fromConfigs({
    InferenceClientsBuilders? inferenceClientsBuilders,
  }) => AIRuntimeContext(
    modelRouter: ModelRouter(
      inferenceClientsBuilders: inferenceClientsBuilders ?? {},
      models: {},
      runtimes: {},
    ),
  );

  final agentsPool = <Agent>{};
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
          AIRuntimeContext.fromConfigs(
            inferenceClientsBuilders: config.inferenceClientBuilders,
          );
  final AIRuntimeConfig config;
  AIRuntimeContext context;

  Agent createAgent() {
    final agent = Agent(context: context);
    context.agentsPool.add(agent);
    return agent;
  }

  Future<TResponse> generateContent<TContent, TResponse>(
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
  final world = World();
  final AIRuntime runtime;

  Future<String> sendTextMessage(final String message) async {
    final agent = runtime.createAgent();
    final response = await runtime.generateContent(
      agent,
      message,
      contentToJson: (content) => content,
      responseFromJson: (json) => json,
    );
    return response;
  }

  void dispose() {
    runtime.dispose();
  }
}
