import 'package:ecsly/ecsly.dart';
import 'package:equatable/equatable.dart';

/// Any ML model
class Model {
  const Model();
  static const empty = Model();
}

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

/// the chooser of models
class ModelRouter {
  ModelRouter({this.models = const {}});
  Map<ModelId, Model> models;

  final ModelId _cursor = ModelId.empty;

  Model get activeModel => models[_cursor] ?? Model.empty;
}

/// 1 intance [ModelRuntime] holds:
/// - 1 only ML/LM [Model] and its [ModelContextWindow]
/// - orginized and contiuos information
/// about model goals, plans, history etc..
/// - AgentTools - intents / intentcalls?
class ModelRuntime {
  ModelRuntime({required this.model, this.context = ModelContextWindow.empty});
  final Model model;
  final ModelContextWindow context;
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
    this.runtimeMemories = const AgentRuntimeMemories(),
    this.sharedMemories = const AgentSharedMemories(),
    this.config = const AgentConfig(),
    this.id = AgentId.empty,
  });
  final AgentRuntimeMemories runtimeMemories;
  final AgentSharedMemories sharedMemories;
  final AgentConfig config;
  final AgentId id;

  @override
  List<Object?> get props => [id];
  static void disposeStatic(Agent agent) {}
}

/// context (di) for [AIRuntime]
class AIRuntimeContext {
  final agentsPool = <Agent>{};

  void dispose() {
    agentsPool
      ..forEach(Agent.disposeStatic)
      ..clear();
  }
}

/// starting point of managing agents runtimes
class AIRuntime {
  AIRuntimeContext context = AIRuntimeContext();

  Agent createAgent() {
    const agent = Agent();
    context.agentsPool.add(agent);
    return agent;
  }
}

class AIWorld {
  final world = World();

  void run() {}
}
