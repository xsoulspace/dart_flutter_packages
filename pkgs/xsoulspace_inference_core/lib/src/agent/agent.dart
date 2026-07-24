import 'package:equatable/equatable.dart';

/// Any ML model
class Model {}

/// orginized and contiuos information
/// about agent goals, plans, history etc..
class ModelContextWindow {
  const ModelContextWindow();
  static const empty = ModelContextWindow();
}

/// the chooser of models
class ModelRouter {
  ModelRouter({required this.model});
  Model model;
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

abstract class AgentMemory {
  const AgentMemory({this.storage = const VoidAgentMemoryStorage()});
  final AgentMemoryStorage storage;
}

/// persits only per runtime agent (not shared between)
class AgentRuntimeMemory extends AgentMemory {
  const AgentRuntimeMemory({super.storage});
}

/// persists across multiple runtimes
class SharedMemory extends AgentMemory {
  const SharedMemory({super.storage});
}

extension type const AgentId(String value) {
  //TODO(arenukvern): add uuid
  factory AgentId.create() => AgentId('${DateTime.now()}');
  static const empty = AgentId('');
}

/// aka thread aka lead aka main aka orchestrator
///
/// controls [ModelLoop]s and through that - [ModelRuntime]
class Agent with Equatable {
  const Agent({
    this.runtimeMemory = const AgentRuntimeMemory(),
    this.id = AgentId.empty,
  });
  final AgentRuntimeMemory runtimeMemory;
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
