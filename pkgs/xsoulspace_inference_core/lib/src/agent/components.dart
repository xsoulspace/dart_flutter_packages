import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

import 'agent.dart';
import 'narrative.dart';

// ─────────────────────────────────────────────
// Components
// ─────────────────────────────────────────────

/// Identity component for an actor entity.
///
/// An Actor entity represents an agent identity (LLM, human, or other).
/// The [agentId] is a stable domain key; the entity itself is the
/// runtime handle.
class Actor implements Component {
  const Actor({required this.agentId});
  final AgentId agentId;
}

/// Current model binding for an actor.
///
/// Swapping this component at runtime changes which model the actor
/// uses on its next generation. The [modelId] resolves through
/// [ModelRouterResource].
class ActorModel implements Component {
  const ActorModel({required this.modelId});
  final ModelId modelId;
}

/// System prompt for an actor.
class ActorSystemPrompt implements Component {
  const ActorSystemPrompt({required this.text});
  final String text;
}

/// Name of the tool registry this actor can use.
///
/// Resolved through [ToolRegistryResource] at generation time.
class ActorTools implements Component {
  const ActorTools({required this.registryName});
  final String registryName;
}

/// Marks which threads an actor participates in.
///
/// This replaces the old memory-cache reference. It is NOT a memory cache —
/// it only records which threads the actor is "in". Projection reads the
/// thread graph + facet index functionally; this component just marks
/// membership so the ray-trace can include the actor's own threads.
class ActorThreads implements Component {
  ActorThreads({List<Entity>? threads}) : threads = threads ?? <Entity>[];

  /// The threads this actor participates in.
  List<Entity> threads;
}

/// Tag component: this actor currently has autonomy and must act.
///
/// Granted by [grantAgencySystem] when an [OpenDecision] exists.
/// Consumed by [processResponsesSystem] after the actor responds.
class Agency implements Component {
  const Agency();
}

/// Tag component: this actor has dispatched an async request and is waiting
/// for a response.
///
/// Added by [actorActSystem] when the request is dispatched. Consumed by
/// [processResponsesSystem] after the response is processed.
/// Prevents re-granting Agency until the response arrives.
///
/// [taskId] correlates the actor to the in-flight task in
/// [TaskRegistryResource], so one actor can await an LLM, a tool, and a
/// human input simultaneously.
class AwaitingResponse implements Component {
  const AwaitingResponse({this.taskId});
  final TaskId? taskId;
}

/// Explicit signal that agency is required.
///
/// An entity with both [Actor] and [OpenDecision] (and no [Agency] yet)
/// triggers the agency-granting system. The [schema] describes the
/// expected structured output; empty schema means free text.
///
/// [priority] ranks competing decisions (higher = more urgent). [escalate]
/// requests a stronger model for this decision (Phase 3).
class OpenDecision implements Component {
  const OpenDecision({
    this.schema = SchemaBundle.empty,
    this.prompt = '',
    this.priority = 0,
    this.escalate = false,
  });
  final SchemaBundle schema;
  final String prompt;
  final int priority;
  final bool escalate;
}

/// Tag component: this actor has requested escalation to a stronger model.
///
/// Written by a mechanical system when an [OpenDecision] has
/// [OpenDecision.escalate] set (or the local model signals low confidence).
/// The agency system routes this actor's next generation to a different
/// (larger) model, then folds the result back into the narrative state.
class EscalationRequest implements Component {
  const EscalationRequest({this.reason = ''});
  final String reason;
}

/// Tag component: this entity is a Scene (the current stage).
class Scene implements Component {
  const Scene();
}

/// Frame counter for the current scene.
class SceneFrame implements Component {
  SceneFrame({this.frame = 0});
  int frame;
}

/// Relationship: an actor is present in a scene.
///
/// [sceneEntity] points to the Scene entity.
class PresentInScene implements Component {
  const PresentInScene({required this.sceneEntity});
  final Entity sceneEntity;
}

/// Relationship: a prop is present in a scene.
class PresentProp implements Component {
  const PresentProp({required this.sceneEntity});
  final Entity sceneEntity;
}

/// A prop is any mutable stateful object (file, memory, tool result, etc.).
class Prop implements Component {
  const Prop({required this.name});
  final String name;
}

/// Transient minimal projection prepared for one actor.
///
/// A cinematic cut, not a summary: only the props in frame, co-present
/// actors, the local question, the projected (budget-limited) context beats,
/// and explicit absences. Built by [projectSituationSystem] and consumed by
/// [actorActSystem].
class Situation implements Component {
  Situation({
    this.prompt = '',
    this.schema = SchemaBundle.empty,
    this.inFramePropIds = const [],
    this.coPresentActorIds = const [],
    this.projectedBeats = const [],
    this.explicitAbsences = const [],
    this.toolRegistryName,
    this.tokensUsed = 0,
    this.tokenBudget = 4000,
    this.truncated = false,
  });
  String prompt;
  SchemaBundle schema;
  List<String> inFramePropIds;
  List<AgentId> coPresentActorIds;

  /// The projected, relevance-ranked, budget-limited beat entities the model
  /// will actually see. This is the cinematic cut — plain beat handles, not
  /// a stored per-actor fragment list.
  List<Entity> projectedBeats;

  /// Green-screen: explicit statements of what the model does NOT see.
  List<String> explicitAbsences;

  /// The tool registry in frame for this actor (if any).
  String? toolRegistryName;

  /// Tokens consumed by this projection (for measurement / budget audit).
  int tokensUsed;

  /// The token budget this projection was built against.
  int tokenBudget;

  /// True when relevant context was omitted to fit the budget.
  bool truncated;
}

/// A goal assigned to an actor.
class Goal implements Component {
  Goal({this.text = ''});
  String text;
}

/// Partial streaming buffer for an actor's in-progress generation.
///
/// Chunks are appended by [processStreamEventsSystem] as the handler
/// streams them. UI can read this component to render partials live;
/// the final response is stored as a Beat by [processResponsesSystem].
class StreamingBeat implements Component {
  StreamingBeat({List<String>? chunks}) : chunks = chunks ?? <String>[];
  final List<String> chunks;
}

/// A memory summary: a first-class beat kind, like text/thought/toolCall.
///
/// A summary is only ever produced by a deliberate, requested transform
/// ([summarizeThread]) — never by automatic compaction. It stays in its
/// thread (via [BelongsToThread]) and links back to its source beats (via
/// [SummarizesBeats]). The summary is a Prop — it can be observed, shared,
/// and referenced by other actors.
class MemorySummary implements Component {
  MemorySummary(this.text);
  String text;
}

/// The actor this memory summary belongs to.
class SummaryOwner implements Component {
  const SummaryOwner(this.actor);
  final Entity actor;
}

/// The thread this summary was derived from (if any).
class SummaryThread implements Component {
  const SummaryThread(this.thread);
  final Entity? thread;
}

/// Structured result of a tool call, stored on the tool-result beat.
///
/// Unlike a stringified `<result|...>` blob, this keeps the tool name and its
/// typed output so projection and metrics can read the structure instead of
/// re-parsing text. The beat also carries a short [TextContent] for keyword
/// indexing / projection; [ToolResultContent] is the source of truth.
class ToolResultContent implements Component {
  ToolResultContent({required this.name, required this.output});
  final String name;
  final dynamic output;
}

// ─────────────────────────────────────────────
// Task surface
// ─────────────────────────────────────────────
//
// Co-located here because [TaskId] / [TaskHandle] / [TaskRegistryResource]
// are referenced from components, events, and resources alike; keeping them
// together makes the import graph acyclic (components is a leaf above
// agent.dart).

/// Identity for an in-flight async task (generation, tool call, human
/// input). Tasks are correlated across the world via [TaskRegistryResource].
@immutable
class TaskId {
  const TaskId(this.value);
  factory TaskId.create() => TaskId('${DateTime.now().microsecondsSinceEpoch}');
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TaskId && value == other.value);

  @override
  int get hashCode => value.hashCode;
}

/// Cold handle to an in-flight task.
///
/// Holds the [Completer] that resumes the awaiting caller (e.g. a native
/// tool bridge or a host awaiting an actor response). Completers live here —
/// in a cold resource — never in a component, keeping the ECS hot path
/// future-free.
class TaskHandle {
  TaskHandle({Completer<dynamic>? completer})
    : completer = completer ?? Completer<dynamic>();
  final Completer<dynamic> completer;
}

/// World resource tracking in-flight async tasks.
///
/// This is the single source of truth for "is there pending async work".
/// [HarnessLoop.canSleep] checks it; systems resolve tasks by completing
/// the associated [TaskHandle.completer].
class TaskRegistryResource extends Resource {
  final Map<TaskId, TaskHandle> tasks = {};

  void register(TaskId id, TaskHandle handle) => tasks[id] = handle;

  TaskHandle? take(TaskId id) => tasks.remove(id);

  TaskHandle? peek(TaskId id) => tasks[id];

  bool has(TaskId id) => tasks.containsKey(id);

  int get length => tasks.length;

  bool get isEmpty => tasks.isEmpty;
}
