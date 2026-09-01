/// Persistent-identity world snapshot codec (A8).
///
/// Runtime `Entity` handles are world-local and regenerated every run, so
/// they never cross the serialization boundary: persisted entities carry a
/// ecsly_serialization [PersistentId], and every `Entity` reference inside
/// an object component is encoded as its persistent id and translated back
/// to a fresh handle on restore. Capture stamps missing ids onto persisted
/// entities at capture time; runtime spawn paths are untouched.
///
/// Structure travels as component type names; values travel through
/// per-type codecs registered with the ecsly serialization plugin. Restore
// ignore_for_file: lines_longer_than_80_chars
/// delegates to `restoreWorldSnapshot` into a fresh plugin-installed world,
/// after which derived state (the facet index) is rebuilt from restored
/// beats — derived state is never source-of-truth.
library;

import 'dart:convert';

import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'data_models/data_models.dart';
import 'meaning/meaning_tree.dart'
    show MeaningEdge, MeaningIndex, MeaningNode, MeaningProps, meaningKeywords;
import 'model_router.dart';
import 'narrative/narrative.dart';
import 'plugin.dart';
import 'resources/resources.dart';
import 'systems/identity_systems.dart' show IdentitySeeded;
import 'systems/projection/projection_systems.dart' show toolResultText;
import 'systems/projection/relevance.dart' show keywordsOf;

/// Envelope marker for the PersistentId-based payload format.
const String kSnapshotFormat = 'ecsly-persistent-id';

/// Codec envelope version (bump on format changes).
const int _snapshotFormatVersion = 1;

/// Derived projections and transient loop state: never captured, never
/// spawned back, even if a source entity carried them. P5 (persistent
/// sessions): a restored actor is IDLE-RESUMABLE — open decisions, agency
/// grants, in-flight awaits, stale verdicts, loop-smoke streaks and the
/// transient escalation baton do NOT cross a restart. AttemptCount and
/// ToolRoundCount DO (monotonic budgets survive), as does the durable
/// GoalAttemptsExhausted terminal record.
const Set<String> _excludedComponents = {
  'Situation',
  'StreamingBeat',
  'ToolResultPendingMarker',
  'DecisionOrigin',
  'DeferredThinking',
  'OpenDecision',
  'Agency',
  'AwaitingResponse',
  'LoopStuck',
  'EscalationRequest',
  'GoalVerified',
};

/// The world a codec currently reads from (capture) or writes into
/// (restore). Codecs resolve references through it; restore sets it to the
/// target world only after every carrier has been spawned.
World? _ctx;

int _ref(Entity entity) {
  final pid = persistentIdOf(_ctx!, entity);
  if (pid == null) {
    throw StateError(
      'Cannot serialize reference to $entity: target carries no PersistentId.',
    );
  }
  return pid.value;
}

Entity _deref(Object? value) {
  if (value is! int) {
    throw ArgumentError.value(value, 'value', 'not a persistent id');
  }
  for (final (entity, pid) in _ctx!.query<PersistentId>()) {
    if (pid.value == value) return entity.entity;
  }
  throw StateError('Snapshot references unknown persistent id $value.');
}

Entity? _refOrNull(Object? value) => value == null ? null : _deref(value);

List<Entity> _derefList(Object? values) => [
  for (final v in values as List? ?? const []) _deref(v),
];

List<int> _refList(Iterable<Entity> entities) => [
  for (final e in entities) _ref(e),
];

class _Spec<T extends Component> extends ObjectComponentCodec<T> {
  _Spec(this.sample, this.to, this.from);
  Type get type => T;

  /// Structural placeholder used at spawn time; real values are written
  /// from column data afterwards.
  final T Function() sample;
  final Object? Function(T) to;
  final T Function(Object? value) from;

  String get typeName => T.toString();

  void registerIn(ObjectComponentCodecRegistry registry) =>
      registry.register<T>(this);

  @override
  Object? toJson(T component) => to(component);
  @override
  T fromJson(Object? value) => from(value);
}

final List<_Spec> _specs = [
  _Spec<Actor>(
    () => Actor(agentId: AgentId.create()),
    (c) => {'agentId': c.agentId.value},
    (v) => Actor(agentId: AgentId((v! as Map)['agentId'] as String)),
  ),
  _Spec<ActorModel>(
    () => ActorModel(modelId: ModelId.create()),
    (c) => {'modelId': c.modelId},
    (v) => ActorModel(modelId: ModelId((v! as Map)['modelId'] as String)),
  ),
  _Spec<ActorSystemPrompt>(
    () => const ActorSystemPrompt(text: ''),
    (c) => {'text': c.text},
    (v) => ActorSystemPrompt(text: (v! as Map)['text'] as String),
  ),
  _Spec<ActorTools>(
    () => const ActorTools(registryName: 'default'),
    (c) => {'registryName': c.registryName},
    (v) => ActorTools(
      registryName: (v! as Map)['registryName'] as String? ?? 'default',
    ),
  ),
  _Spec<ActorThreads>(
    () => ActorThreads(threads: const []),
    (c) => {'threads': _refList(c.threads)},
    (v) => ActorThreads(threads: _derefList((v! as Map)['threads'])),
  ),
  _Spec<MeaningNode>(
    () => const MeaningNode(id: '', kind: '', label: ''),
    (c) => {'id': c.id, 'kind': c.kind, 'label': c.label},
    (v) {
      final m = v! as Map;
      return MeaningNode(
        id: m['id'] as String,
        kind: m['kind'] as String,
        label: m['label'] as String,
      );
    },
  ),
  _Spec<MeaningProps>(
    () => const MeaningProps(),
    (c) => {'props': c.props},
    (v) => MeaningProps(
      ((v! as Map)['props'] as Map?)?.cast<String, dynamic>(),
    ),
  ),
  _Spec<MeaningEdge>(
    () => MeaningEdge(
      from: Entity.create(),
      relation: '',
      to: Entity.create(),
    ),
    (c) => {'from': _ref(c.from), 'relation': c.relation, 'to': _ref(c.to)},
    (v) {
      final m = v! as Map;
      return MeaningEdge(
        from: _deref(m['from']),
        relation: m['relation'] as String,
        to: _deref(m['to']),
      );
    },
  ),

  _Spec<Agency>(() => const Agency(), (_) => const {}, (_) => const Agency()),
  _Spec<AwaitingResponse>(
    () => const AwaitingResponse(),
    (c) => {'taskId': c.taskId?.value},
    (v) {
      final m = v! as Map;
      return AwaitingResponse(
        taskId: m['taskId'] == null ? null : TaskId(m['taskId'] as String),
      );
    },
  ),
  _Spec<OpenDecision>(
    () => const OpenDecision(),
    (c) => {
      'schema': c.schema.toJson(),
      'prompt': c.prompt,
      'priority': c.priority,
      'escalate': c.escalate,
      'threadId': c.threadId == null ? null : _ref(c.threadId!),
      'stepId': c.stepId == null ? null : _ref(c.stepId!),
    },
    (v) {
      final m = v! as Map;
      final schema = m['schema'];
      return OpenDecision(
        schema: schema is! Map || schema.isEmpty
            ? SchemaBundle.empty
            : SchemaBundle.fromJson(schema.cast<String, dynamic>()),
        prompt: m['prompt'] as String? ?? '',
        priority: m['priority'] as int? ?? 0,
        escalate: m['escalate'] as bool? ?? false,
        threadId: _refOrNull(m['threadId']),
        stepId: _refOrNull(m['stepId']),
      );
    },
  ),
  _Spec<EscalationRequest>(
    () => const EscalationRequest(),
    (c) => {'reason': c.reason},
    (v) => EscalationRequest(reason: (v! as Map)['reason'] as String? ?? ''),
  ),
  _Spec<LoopStuck>(
    () => const LoopStuck(0),
    (c) => {'streak': c.streak},
    (v) => LoopStuck((v! as Map)['streak'] as int? ?? 0),
  ),
  _Spec<Scene>(() => const Scene(), (_) => const {}, (_) => const Scene()),
  _Spec<SceneFrame>(
    SceneFrame.new,
    (c) => {'frame': c.frame},
    (v) => SceneFrame(frame: (v! as Map)['frame'] as int? ?? 0),
  ),
  _Spec<PresentInScene>(
    () => PresentInScene(sceneEntity: Entity.create()),
    (c) => {'scene': _ref(c.sceneEntity)},
    (v) => PresentInScene(sceneEntity: _deref((v! as Map)['scene'])),
  ),
  _Spec<PresentProp>(
    () => PresentProp(sceneEntity: Entity.create()),
    (c) => {'scene': _ref(c.sceneEntity)},
    (v) => PresentProp(sceneEntity: _deref((v! as Map)['scene'])),
  ),
  _Spec<Prop>(
    () => const Prop(name: ''),
    (c) => {'name': c.name},
    (v) => Prop(name: (v! as Map)['name'] as String),
  ),
  _Spec<Goal>(
    Goal.new,
    (c) => {
      'text': c.text,
      'successCriteria': c.successCriteria,
      'status': c.status,
    },
    (v) {
      final m = v! as Map;
      return Goal(
        text: m['text'] as String? ?? '',
        successCriteria: List<String>.from(m['successCriteria'] as List? ?? []),
        status: m['status'] as String? ?? 'active',
      );
    },
  ),
  _Spec<Thread>(
    () => const Thread(),
    (c) => {
      'parentThreadId': c.parentThreadId == null
          ? null
          : _ref(c.parentThreadId!),
    },
    (v) => Thread(parentThreadId: _refOrNull((v! as Map)['parentThreadId'])),
  ),
  _Spec<ThreadScore>(
    () => ThreadScore(0),
    (c) => {'value': c.value},
    (v) => ThreadScore(((v! as Map)['value'] as num?)?.toDouble() ?? 0),
  ),
  _Spec<ThreadId>(
    () => const ThreadId(''),
    (c) => {'value': c.value},
    (v) => ThreadId((v! as Map)['value'] as String),
  ),
  _Spec<ThreadStatus>(
    () => ThreadStatus(ThreadStatusEnum.active),
    (c) => {'value': c.value.name},
    (v) => ThreadStatus(
      ThreadStatusEnum.values.byName((v! as Map)['value'] as String),
    ),
  ),
  _Spec<ParentScene>(
    () => ParentScene(Entity.create()),
    (c) => {'scene': _ref(c.scene)},
    (v) => ParentScene(_deref((v! as Map)['scene'])),
  ),
  _Spec<OriginActor>(
    () => OriginActor(Entity.create()),
    (c) => {'actor': _ref(c.actor)},
    (v) => OriginActor(_deref((v! as Map)['actor'])),
  ),
  _Spec<GoalLink>(
    () => const GoalLink(null),
    (c) => {'goal': c.goal == null ? null : _ref(c.goal!)},
    (v) => GoalLink(_refOrNull((v! as Map)['goal'])),
  ),
  _Spec<DependsOnStep>(
    () => const DependsOnStep(),
    (c) => {'dependencies': _refList(c.dependencies)},
    (v) => DependsOnStep(_derefList((v! as Map)['dependencies'])),
  ),
  _Spec<Step>(
    () => Step(claim: '', verificationKind: StepVerificationKind.mechanical),
    (c) => {
      'claim': c.claim,
      'verificationKind': c.verificationKind.name,
      'status': c.status.name,
      'confidence': c.confidence,
      'criterionArgs': c.criterionArgs,
    },
    (v) {
      final m = v! as Map;
      return Step(
        claim: m['claim'] as String? ?? '',
        verificationKind: StepVerificationKind.values.byName(
          m['verificationKind'] as String? ?? 'mechanical',
        ),
        status: StepLifecycle.values.byName(m['status'] as String? ?? 'open'),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        criterionArgs: (m['criterionArgs'] as Map? ?? {})
            .cast<String, dynamic>(),
      );
    },
  ),
  _Spec<DerivedFromThread>(
    () => DerivedFromThread(Entity.create()),
    (c) => {'thread': _ref(c.thread)},
    (v) => DerivedFromThread(_deref((v! as Map)['thread'])),
  ),
  _Spec<ThreadVisibility>(
    () => ThreadVisibility(const <AgentId>{}),
    (c) => {
      'visibleTo': [for (final a in c.visibleTo) a.value],
    },
    (v) => ThreadVisibility(
      ((v! as Map)['visibleTo'] as List? ?? [])
          .map((a) => AgentId(a as String))
          .toSet(),
    ),
  ),
  _Spec<BeatId>(
    () => const BeatId(''),
    (c) => {'value': c.value},
    (v) => BeatId((v! as Map)['value'] as String),
  ),
  _Spec<BelongsToThread>(
    () => BelongsToThread(Entity.create()),
    (c) => {'thread': _ref(c.thread)},
    (v) => BelongsToThread(_deref((v! as Map)['thread'])),
  ),
  _Spec<SummarizesBeats>(
    () => SummarizesBeats(sources: const []),
    (c) => {'sources': _refList(c.sources)},
    (v) => SummarizesBeats(sources: _derefList((v! as Map)['sources'])),
  ),
  _Spec<BeatSequence>(
    () => BeatSequence(0),
    (c) => {'value': c.value},
    (v) => BeatSequence((v! as Map)['value'] as int? ?? 0),
  ),
  _Spec<Speaker>(
    () => Speaker(Entity.create()),
    (c) => {'actor': _ref(c.actor)},
    (v) => Speaker(_deref((v! as Map)['actor'])),
  ),
  _Spec<AddressedTo>(
    () => const AddressedTo(null),
    (c) => {'actor': c.actor == null ? null : _ref(c.actor!)},
    (v) => AddressedTo(_refOrNull((v! as Map)['actor'])),
  ),
  _Spec<BeatModality>(
    () => BeatModality(BeatModalityEnum.text),
    (c) => {'value': c.value.name},
    (v) => BeatModality(
      BeatModalityEnum.values.byName((v! as Map)['value'] as String),
    ),
  ),
  _Spec<BeatStatus>(
    () => BeatStatus(BeatStatusEnum.complete),
    (c) => {'value': c.value.name},
    (v) =>
        BeatStatus(BeatStatusEnum.values.byName((v! as Map)['value'] as String)),
  ),
  _Spec<ReplyToBeat>(
    () => ReplyToBeat(Entity.create()),
    (c) => {'beat': _ref(c.beat)},
    (v) => ReplyToBeat(_deref((v! as Map)['beat'])),
  ),
  _Spec<ObservesProp>(
    () => ObservesProp(Entity.create()),
    (c) => {'prop': _ref(c.prop)},
    (v) => ObservesProp(_deref((v! as Map)['prop'])),
  ),
  _Spec<PrivateToActor>(
    () => PrivateToActor(Entity.create()),
    (c) => {'actor': _ref(c.actor)},
    (v) => PrivateToActor(_deref((v! as Map)['actor'])),
  ),
  _Spec<TextContent>(
    () => TextContent(''),
    (c) => {'text': c.text},
    (v) => TextContent((v! as Map)['text'] as String),
  ),
  _Spec<TextStream>(
    () => TextStream(chunks: const []),
    (c) => {'chunks': c.chunks, 'cursor': c.cursor},
    (v) {
      final m = v! as Map;
      return TextStream(
        chunks: List<String>.from(m['chunks'] as List? ?? []),
        cursor: m['cursor'] as int? ?? 0,
      );
    },
  ),
  _Spec<AudioStream>(
    () => AudioStream(chunks: const []),
    (c) => {
      'chunks': [for (final chunk in c.chunks) base64Encode(chunk)],
    },
    (v) => AudioStream(
      chunks: [
        for (final encoded in (v! as Map)['chunks'] as List? ?? [])
          base64Decode(encoded as String),
      ],
    ),
  ),
  _Spec<ActionPayload>(
    () => ActionPayload(const {}),
    (c) => {'data': c.data},
    (v) => ActionPayload((v! as Map)['data']),
  ),
  _Spec<BeatToolCall>(
    () => BeatToolCall('', const {}),
    (c) => {'name': c.name, 'args': c.args},
    (v) {
      final m = v! as Map;
      return BeatToolCall(
        m['name'] as String,
        (m['args'] as Map? ?? {}).cast<String, dynamic>(),
      );
    },
  ),
  _Spec<ToolResult>(
    () => ToolResult(null),
    (c) => {'result': c.result},
    (v) => ToolResult((v! as Map)['result']),
  ),
  _Spec<ThoughtContent>(
    () => ThoughtContent(''),
    (c) => {'text': c.text},
    (v) => ThoughtContent((v! as Map)['text'] as String),
  ),
  _Spec<ObservationData>(
    () => ObservationData(null),
    (c) => {'data': c.data},
    (v) => ObservationData((v! as Map)['data']),
  ),
  _Spec<MemorySummary>(
    () => MemorySummary(''),
    (c) => {'text': c.text},
    (v) => MemorySummary((v! as Map)['text'] as String),
  ),
  _Spec<SummaryOwner>(
    () => SummaryOwner(Entity.create()),
    (c) => {'actor': _ref(c.actor)},
    (v) => SummaryOwner(_deref((v! as Map)['actor'])),
  ),
  _Spec<SummaryThread>(
    () => const SummaryThread(null),
    (c) => {'thread': c.thread == null ? null : _ref(c.thread!)},
    (v) => SummaryThread(_refOrNull((v! as Map)['thread'])),
  ),
  _Spec<ToolResultContent>(
    () => ToolResultContent(name: '', output: null),
    (c) => {'name': c.name, 'output': c.output},
    (v) {
      final m = v! as Map;
      return ToolResultContent(name: m['name'] as String, output: m['output']);
    },
  ),
  _Spec<IdentityBeat>(
    () => const IdentityBeat(),
    (_) => const {},
    (_) => const IdentityBeat(),
  ),
  _Spec<RetryCount>(
    () => RetryCount(0),
    (c) => {'value': c.value},
    (v) => RetryCount((v! as Map)['value'] as int? ?? 0),
  ),
  _Spec<ToolRoundCount>(
    () => ToolRoundCount(0),
    (c) => {'value': c.value},
    (v) => ToolRoundCount((v! as Map)['value'] as int? ?? 0),
  ),
  _Spec<TotalRoundCount>(
    () => TotalRoundCount(0),
    (c) => {'value': c.value},
    (v) => TotalRoundCount((v! as Map)['value'] as int? ?? 0),
  ),
  _Spec<AttemptCount>(
    () => AttemptCount(0),
    (c) => {'value': c.value},
    (v) => AttemptCount((v! as Map)['value'] as int? ?? 0),
  ),
  _Spec<GoalAttemptsExhausted>(
    () => const GoalAttemptsExhausted(''),
    (c) => {'reason': c.reason},
    (v) => GoalAttemptsExhausted((v! as Map)['reason'] as String? ?? ''),
  ),
  _Spec<IdentitySeeded>(
    () => const IdentitySeeded(),
    (_) => const {},
    (_) => const IdentitySeeded(),
  ),
];

Map<String, Component Function()> get _componentFactories => {
  for (final spec in _specs) spec.typeName: spec.sample,
};

ObjectComponentCodecRegistry get _codecRegistry {
  final registry = ObjectComponentCodecRegistry();
  for (final spec in _specs) {
    spec.registerIn(registry);
  }
  return registry;
}

Set<ComponentId> _persistedComponentIds(World world) {
  final ids = <ComponentId>{};
  for (final spec in _specs) {
    final id = world.components.getComponentIdByType(_typeOf(spec));
    if (id != null) ids.add(id);
  }
  return ids;
}

Type _typeOf(_Spec spec) => spec.type;

/// Stamps missing [PersistentId]s onto every entity carrying a persisted
/// component. Existing ids are preserved; new ones are unique within the
/// run. Mutates the captured world by attaching identity tags.
void _stampPersistentIds(World world) {
  registerPersistentId(world);
  var next = 1;
  for (final (_, pid) in world.query<PersistentId>()) {
    if (pid.value >= next) next = pid.value + 1;
  }
  // Collect carriers first: upserts are queued, so an entity holding two
  // persisted components would be seen twice before either stamp lands.
  final carriers = <String, Entity>{};
  for (final componentId in _persistedComponentIds(world)) {
    for (final archetype in world.archetypes.all.toList()) {
      if (!archetype.signature.has(componentId)) continue;
      for (final entity in archetype.entities.toList()) {
        carriers[entity.toJson()] = entity;
      }
    }
  }
  for (final entity in carriers.values) {
    if (persistentIdOf(world, entity) != null) continue;
    world.upsertComponent(entity, PersistentId(next++));
  }
  world.flush();
}

/// Captures [world] into the envelope format handled by [restoreWorld].
///
/// Entities carrying persisted components receive a [PersistentId] if they
/// do not already have one; the world graph itself is not modified beyond
/// these identity tags. The facet index's per-thread insertion order is
/// recorded alongside the payload — projection's recency tie-break depends
/// on it, and it cannot be derived from component data alone.
Map<String, dynamic> snapshotWorld(World world) {
  world.flush();
  _stampPersistentIds(world);
  _ctx = world;
  try {
    final snapshot = captureWorldSnapshot(
      world,
      options: WorldSnapshotOptions(
        includeOnly: _persistedComponentIds(world),
        codecs: _codecRegistry,
      ),
    );
    final index = world.getResource<FacetIndex>();
    final indexOrder = <String, int>{};
    var position = 0;
    for (final (thread, _) in world.query<Thread>()) {
      for (final beat in index.beatsOfThread(thread.entity)) {
        final pid = persistentIdOf(world, beat);
        if (pid != null) indexOrder['${pid.value}'] = position++;
      }
    }
    return {
      'format': kSnapshotFormat,
      'version': _snapshotFormatVersion,
      'payload': snapshot.toJson(),
      'indexOrder': indexOrder,
    };
  } finally {
    _ctx = null;
  }
}

/// Restores a fresh world from a [snapshotWorld] envelope: plugin installed,
/// default router attached, entities respawned under their persistent ids,
/// facet index rebuilt from restored beats.
World restoreWorld(Map<String, dynamic> snapshot) {
  if (snapshot['format'] != kSnapshotFormat) {
    throw ArgumentError.value(
      snapshot['format'],
      'format',
      'expected "$kSnapshotFormat"',
    );
  }
  if (snapshot['version'] != _snapshotFormatVersion) {
    throw ArgumentError.value(snapshot['version'], 'version', 'unsupported');
  }
  final decoded = WorldSnapshot.fromJson(
    (snapshot['payload'] as Map).cast<String, Object?>(),
  );
  final indexOrder = <int, int>{
    for (final entry in ((snapshot['indexOrder'] as Map?) ?? const {}).entries)
      int.parse(entry.key as String): entry.value as int,
  };

  // Structural filter: derived/transient components must never materialize
  // in the restored world even when the source entity carried them.
  final filtered = WorldSnapshot(
    version: decoded.version,
    schemaVersion: decoded.schemaVersion,
    componentIds: decoded.componentIds,
    resources: decoded.resources,
    entities: [
      for (final entry in decoded.entities)
        EntityEntry(
          persistentId: entry.persistentId,
          components: entry.components
              .where((name) => !_excludedComponents.contains(name))
              .toList(growable: false),
          columns: entry.columns,
        ),
    ],
  );

  final world = World()..addPlugin(AgentPlugin());
  world
    ..upsertResource(ModelRouterResource(ModelRouter()))
    ..upsertResource(ToolRegistryResource());
  world.flush();

  _ctx = world;
  try {
    restoreWorldSnapshot(
      world,
      filtered,
      componentFactories: _componentFactories,
      options: WorldSnapshotOptions(codecs: _codecRegistry),
    );
  } finally {
    _ctx = null;
  }
  world.flush();
  _rebuildFacetIndex(world, indexOrder);
  _rebuildMeaningIndex(world);
  world.flush();
  return world;
}

/// Rebuilds the derived [MeaningIndex] and re-facets meaning nodes after a
/// restore. The beat rebuild cannot see meaning nodes (they carry no
/// [TextContent]), so the tree re-indexes itself here — derived state is
/// never source-of-truth.
void _rebuildMeaningIndex(World world) {
  final index = world.getResource<MeaningIndex>();
  index.clear();
  for (final (facade, node, props) in world.query2<MeaningNode, MeaningProps>().toList()) {
    index.registerNode(node.id, facade.entity);
    // Continue per-kind id assignment past the restored ids. Only ids in
    // the `kind_N` scheme feed the counter; external stable ids (e.g. AE
    // canonical `entity.create`) keep their given ids and don't shift it.
    if (node.id.startsWith('${node.kind}_')) {
      final n = int.tryParse(node.id.substring(node.kind.length + 1));
      if (n != null) {
        index.kindCounts[node.kind] = n;
      }
    }
    world.getResource<FacetIndex>().indexBeat(
      facade.entity,
      meaningKeywords(node.kind, node.label, props.props),
    );
  }
  for (final (_, edge) in world.query<MeaningEdge>().toList()) {
    index.registerEdge(edge.from, edge.relation, edge.to);
  }
}

void _rebuildFacetIndex(World world, Map<int, int> indexOrder) {
  final index = world.getResource<FacetIndex>();
  index.clear();
  // Re-insert in the source index's insertion order: projection's recency
  // tie-break consumes this order, so parity requires reproducing it.
  // Beats absent from the captured order (unindexed at capture time) go
  // last, preserving their query order.
  var fallback = 1 << 30;
  final beats = [
    for (final (facade, text, thread)
        in world.query2<TextContent, BelongsToThread>())
      (
        facade,
        text,
        thread.thread,
        indexOrder[persistentIdOf(world, facade.entity)?.value] ?? fallback++,
      ),
  ]..sort((a, b) => a.$4.compareTo(b.$4));
  for (final (facade, text, thread, _) in beats) {
    final structured = facade.get<ToolResultContent>();
    final indexedText = structured == null
        ? text.text
        : toolResultText(
            ToolExecutionResult(
              name: structured.name,
              output: structured.output,
            ),
          );
    index.indexBeat(facade.entity, keywordsOf(indexedText), thread: thread);
  }
}
