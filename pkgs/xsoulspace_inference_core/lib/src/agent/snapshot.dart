import 'dart:convert';
import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

import 'data_models/data_models.dart';
import 'events.dart';
import 'model_router.dart';
import 'narrative/narrative.dart';
import 'plugin.dart';
import 'resources/resources.dart';
import 'systems/identity_systems.dart' show IdentitySeeded;
import 'systems/projection/projection_systems.dart' show toolResultText;
import 'systems/projection/relevance.dart';

const int _snapshotVersion = 1;

typedef _Decode =
    Component Function(
      Map<String, dynamic> json,
      Entity Function(String) remap,
    );

final Map<Type, String> _componentTypes = {
  Actor: 'Actor',
  ActorModel: 'ActorModel',
  ActorSystemPrompt: 'ActorSystemPrompt',
  ActorTools: 'ActorTools',
  ActorThreads: 'ActorThreads',
  Agency: 'Agency',
  AwaitingResponse: 'AwaitingResponse',
  EscalationRequest: 'EscalationRequest',
  Scene: 'Scene',
  SceneFrame: 'SceneFrame',
  PresentInScene: 'PresentInScene',
  PresentProp: 'PresentProp',
  Prop: 'Prop',
  Goal: 'Goal',
  Thread: 'Thread',
  ThreadScore: 'ThreadScore',
  ThreadId: 'ThreadId',
  ThreadStatus: 'ThreadStatus',
  ParentScene: 'ParentScene',
  OriginActor: 'OriginActor',
  GoalLink: 'GoalLink',
  DependsOnStep: 'DependsOnStep',
  Step: 'Step',
  DerivedFromThread: 'DerivedFromThread',
  ThreadVisibility: 'ThreadVisibility',
  BeatId: 'BeatId',
  BelongsToThread: 'BelongsToThread',
  SummarizesBeats: 'SummarizesBeats',
  BeatSequence: 'BeatSequence',
  Speaker: 'Speaker',
  AddressedTo: 'AddressedTo',
  BeatModality: 'BeatModality',
  BeatStatus: 'BeatStatus',
  ReplyToBeat: 'ReplyToBeat',
  ObservesProp: 'ObservesProp',
  PrivateToActor: 'PrivateToActor',
  TextContent: 'TextContent',
  TextStream: 'TextStream',
  AudioStream: 'AudioStream',
  ActionPayload: 'ActionPayload',
  BeatToolCall: 'BeatToolCall',
  ToolResult: 'ToolResult',
  ThoughtContent: 'ThoughtContent',
  ObservationData: 'ObservationData',
  MemorySummary: 'MemorySummary',
  SummaryOwner: 'SummaryOwner',
  SummaryThread: 'SummaryThread',
  ToolResultContent: 'ToolResultContent',
  IdentityBeat: 'IdentityBeat',
  RetryCount: 'RetryCount',
  ToolRoundCount: 'ToolRoundCount',
  IdentitySeeded: 'IdentitySeeded',
};

List<(Entity, Component)> _collect(Type type, World world) {
  switch (type) {
    case Actor:
      return [
        for (final (entity, component) in world.query<Actor>())
          (entity.entity, component),
      ];
    case ActorModel:
      return [for (final (e, c) in world.query<ActorModel>()) (e.entity, c)];
    case ActorSystemPrompt:
      return [
        for (final (e, c) in world.query<ActorSystemPrompt>()) (e.entity, c),
      ];
    case ActorTools:
      return [for (final (e, c) in world.query<ActorTools>()) (e.entity, c)];
    case ActorThreads:
      return [for (final (e, c) in world.query<ActorThreads>()) (e.entity, c)];
    case Agency:
      return [for (final (e, c) in world.query<Agency>()) (e.entity, c)];
    case AwaitingResponse:
      return [
        for (final (e, c) in world.query<AwaitingResponse>()) (e.entity, c),
      ];
    case EscalationRequest:
      return [
        for (final (e, c) in world.query<EscalationRequest>()) (e.entity, c),
      ];
    case Scene:
      return [for (final (e, c) in world.query<Scene>()) (e.entity, c)];
    case SceneFrame:
      return [for (final (e, c) in world.query<SceneFrame>()) (e.entity, c)];
    case PresentInScene:
      return [
        for (final (e, c) in world.query<PresentInScene>()) (e.entity, c),
      ];
    case PresentProp:
      return [for (final (e, c) in world.query<PresentProp>()) (e.entity, c)];
    case Prop:
      return [for (final (e, c) in world.query<Prop>()) (e.entity, c)];
    case Goal:
      return [for (final (e, c) in world.query<Goal>()) (e.entity, c)];
    case Thread:
      return [for (final (e, c) in world.query<Thread>()) (e.entity, c)];
    case ThreadScore:
      return [for (final (e, c) in world.query<ThreadScore>()) (e.entity, c)];
    case ThreadId:
      return [for (final (e, c) in world.query<ThreadId>()) (e.entity, c)];
    case ThreadStatus:
      return [for (final (e, c) in world.query<ThreadStatus>()) (e.entity, c)];
    case ParentScene:
      return [for (final (e, c) in world.query<ParentScene>()) (e.entity, c)];
    case OriginActor:
      return [for (final (e, c) in world.query<OriginActor>()) (e.entity, c)];
    case GoalLink:
      return [for (final (e, c) in world.query<GoalLink>()) (e.entity, c)];
    case DependsOnStep:
      return [for (final (e, c) in world.query<DependsOnStep>()) (e.entity, c)];
    case Step:
      return [for (final (e, c) in world.query<Step>()) (e.entity, c)];
    case DerivedFromThread:
      return [
        for (final (e, c) in world.query<DerivedFromThread>()) (e.entity, c),
      ];
    case ThreadVisibility:
      return [
        for (final (e, c) in world.query<ThreadVisibility>()) (e.entity, c),
      ];
    case BeatId:
      return [for (final (e, c) in world.query<BeatId>()) (e.entity, c)];
    case BelongsToThread:
      return [
        for (final (e, c) in world.query<BelongsToThread>()) (e.entity, c),
      ];
    case SummarizesBeats:
      return [
        for (final (e, c) in world.query<SummarizesBeats>()) (e.entity, c),
      ];
    case BeatSequence:
      return [for (final (e, c) in world.query<BeatSequence>()) (e.entity, c)];
    case Speaker:
      return [for (final (e, c) in world.query<Speaker>()) (e.entity, c)];
    case AddressedTo:
      return [for (final (e, c) in world.query<AddressedTo>()) (e.entity, c)];
    case BeatModality:
      return [for (final (e, c) in world.query<BeatModality>()) (e.entity, c)];
    case BeatStatus:
      return [for (final (e, c) in world.query<BeatStatus>()) (e.entity, c)];
    case ReplyToBeat:
      return [for (final (e, c) in world.query<ReplyToBeat>()) (e.entity, c)];
    case ObservesProp:
      return [for (final (e, c) in world.query<ObservesProp>()) (e.entity, c)];
    case PrivateToActor:
      return [
        for (final (e, c) in world.query<PrivateToActor>()) (e.entity, c),
      ];
    case TextContent:
      return [for (final (e, c) in world.query<TextContent>()) (e.entity, c)];
    case TextStream:
      return [for (final (e, c) in world.query<TextStream>()) (e.entity, c)];
    case AudioStream:
      return [for (final (e, c) in world.query<AudioStream>()) (e.entity, c)];
    case ActionPayload:
      return [for (final (e, c) in world.query<ActionPayload>()) (e.entity, c)];
    case BeatToolCall:
      return [for (final (e, c) in world.query<BeatToolCall>()) (e.entity, c)];
    case ToolResult:
      return [for (final (e, c) in world.query<ToolResult>()) (e.entity, c)];
    case ThoughtContent:
      return [
        for (final (e, c) in world.query<ThoughtContent>()) (e.entity, c),
      ];
    case ObservationData:
      return [
        for (final (e, c) in world.query<ObservationData>()) (e.entity, c),
      ];
    case MemorySummary:
      return [for (final (e, c) in world.query<MemorySummary>()) (e.entity, c)];
    case SummaryOwner:
      return [for (final (e, c) in world.query<SummaryOwner>()) (e.entity, c)];
    case SummaryThread:
      return [for (final (e, c) in world.query<SummaryThread>()) (e.entity, c)];
    case ToolResultContent:
      return [
        for (final (e, c) in world.query<ToolResultContent>()) (e.entity, c),
      ];
    case IdentityBeat:
      return [for (final (e, c) in world.query<IdentityBeat>()) (e.entity, c)];
    case RetryCount:
      return [for (final (e, c) in world.query<RetryCount>()) (e.entity, c)];
    case ToolRoundCount:
      return [
        for (final (e, c) in world.query<ToolRoundCount>()) (e.entity, c),
      ];
    case IdentitySeeded:
      return [
        for (final (e, c) in world.query<IdentitySeeded>()) (e.entity, c),
      ];
  }
  return const [];
}

Map<String, dynamic> _encode(Component raw) {
  const tag = 'type';
  switch (raw) {
    case Actor():
      return {tag: 'Actor', 'agentId': raw.agentId.value};
    case ActorModel():
      return {tag: 'ActorModel', 'modelId': raw.modelId};
    case ActorSystemPrompt():
      return {tag: 'ActorSystemPrompt', 'text': raw.text};
    case ActorTools():
      return {tag: 'ActorTools', 'registryName': raw.registryName};
    case ActorThreads():
      return {
        tag: 'ActorThreads',
        'threads': raw.threads.map((v) => v.toJson()).toList(),
      };
    case Agency():
      return {tag: 'Agency'};
    case AwaitingResponse():
      return {tag: 'AwaitingResponse', 'taskId': raw.taskId?.value};
    case EscalationRequest():
      return {tag: 'EscalationRequest', 'reason': raw.reason};
    case Scene():
      return {tag: 'Scene'};
    case SceneFrame():
      return {tag: 'SceneFrame', 'frame': raw.frame};
    case PresentInScene():
      return {tag: 'PresentInScene', 'scene': raw.sceneEntity.toJson()};
    case PresentProp():
      return {tag: 'PresentProp', 'scene': raw.sceneEntity.toJson()};
    case Prop():
      return {tag: 'Prop', 'name': raw.name};
    case Goal():
      return {
        tag: 'Goal',
        'text': raw.text,
        'successCriteria': raw.successCriteria,
        'status': raw.status,
      };
    case Thread():
      return {tag: 'Thread', 'parentThreadId': raw.parentThreadId?.toJson()};
    case ThreadScore():
      return {tag: 'ThreadScore', 'value': raw.value};
    case ThreadId():
      return {tag: 'ThreadId', 'value': raw.value};
    case ThreadStatus():
      return {tag: 'ThreadStatus', 'value': raw.value.name};
    case ParentScene():
      return {tag: 'ParentScene', 'scene': raw.scene.toJson()};
    case OriginActor():
      return {tag: 'OriginActor', 'actor': raw.actor.toJson()};
    case GoalLink():
      return {tag: 'GoalLink', 'goal': raw.goal?.toJson()};
    case DependsOnStep():
      return {
        tag: 'DependsOnStep',
        'dependencies': raw.dependencies.map((v) => v.toJson()).toList(),
      };
    case Step():
      return {
        tag: 'Step',
        'claim': raw.claim,
        'verificationKind': raw.verificationKind.name,
        'status': raw.status.name,
        'confidence': raw.confidence,
        'criterionArgs': raw.criterionArgs,
      };
    case DerivedFromThread():
      return {tag: 'DerivedFromThread', 'thread': raw.thread.toJson()};
    case ThreadVisibility():
      return {
        tag: 'ThreadVisibility',
        'visibleTo': raw.visibleTo.map((v) => v.value).toList(),
      };
    case BeatId():
      return {tag: 'BeatId', 'value': raw.value};
    case BelongsToThread():
      return {tag: 'BelongsToThread', 'thread': raw.thread.toJson()};
    case SummarizesBeats():
      return {
        tag: 'SummarizesBeats',
        'sources': raw.sources.map((v) => v.toJson()).toList(),
      };
    case BeatSequence():
      return {tag: 'BeatSequence', 'value': raw.value};
    case Speaker():
      return {tag: 'Speaker', 'actor': raw.actor.toJson()};
    case AddressedTo():
      return {tag: 'AddressedTo', 'actor': raw.actor?.toJson()};
    case BeatModality():
      return {tag: 'BeatModality', 'value': raw.value.name};
    case BeatStatus():
      return {tag: 'BeatStatus', 'value': raw.value.name};
    case ReplyToBeat():
      return {tag: 'ReplyToBeat', 'beat': raw.beat.toJson()};
    case ObservesProp():
      return {tag: 'ObservesProp', 'prop': raw.prop.toJson()};
    case PrivateToActor():
      return {tag: 'PrivateToActor', 'actor': raw.actor.toJson()};
    case TextContent():
      return {tag: 'TextContent', 'text': raw.text};
    case TextStream():
      return {tag: 'TextStream', 'chunks': raw.chunks, 'cursor': raw.cursor};
    case AudioStream():
      return {
        tag: 'AudioStream',
        'chunks': raw.chunks.map(base64Encode).toList(),
      };
    case ActionPayload():
      return {tag: 'ActionPayload', 'data': raw.data};
    case BeatToolCall():
      return {tag: 'BeatToolCall', 'name': raw.name, 'args': raw.args};
    case ToolResult():
      return {tag: 'ToolResult', 'result': _jsonValue(raw.result)};
    case ThoughtContent():
      return {tag: 'ThoughtContent', 'text': raw.text};
    case ObservationData():
      return {tag: 'ObservationData', 'data': _jsonValue(raw.data)};
    case MemorySummary():
      return {tag: 'MemorySummary', 'text': raw.text};
    case SummaryOwner():
      return {tag: 'SummaryOwner', 'actor': raw.actor.toJson()};
    case SummaryThread():
      return {tag: 'SummaryThread', 'thread': raw.thread?.toJson()};
    case ToolResultContent():
      return {
        tag: 'ToolResultContent',
        'name': raw.name,
        'output': _jsonValue(raw.output),
      };
    case IdentityBeat():
      return {tag: 'IdentityBeat'};
    case RetryCount():
      return {tag: 'RetryCount', 'value': raw.value};
    case ToolRoundCount():
      return {tag: 'ToolRoundCount', 'value': raw.value};
    case IdentitySeeded():
      return {tag: 'IdentitySeeded'};
  }
  return <String, dynamic>{'type': 'Unknown'};
}

final Map<String, _Decode> _decoders = {
  'Actor': (json, _) => Actor(agentId: AgentId(json['agentId'] as String)),
  'ActorModel': (json, _) =>
      ActorModel(modelId: ModelId(json['modelId'] as String)),
  'ActorSystemPrompt': (json, _) =>
      ActorSystemPrompt(text: json['text'] as String),
  'ActorTools': (json, _) =>
      ActorTools(registryName: json['registryName'] as String),
  'ActorThreads': (json, r) =>
      ActorThreads(threads: _entities(json['threads'], r)),
  'Agency': (_, _) => const Agency(),
  'AwaitingResponse': (json, _) =>
      AwaitingResponse(taskId: _taskId(json['taskId'])),
  'EscalationRequest': (json, _) =>
      EscalationRequest(reason: json['reason'] as String),
  'Scene': (_, _) => const Scene(),
  'SceneFrame': (json, _) => SceneFrame(frame: json['frame'] as int? ?? 0),
  'PresentInScene': (json, r) =>
      PresentInScene(sceneEntity: r(json['scene'] as String)),
  'PresentProp': (json, r) =>
      PresentProp(sceneEntity: r(json['scene'] as String)),
  'Prop': (json, _) => Prop(name: json['name'] as String),
  'Goal': (json, _) => Goal(
    text: json['text'] as String? ?? '',
    successCriteria: List<String>.from(json['successCriteria'] as List? ?? []),
    status: json['status'] as String? ?? 'active',
  ),
  'Thread': (json, r) =>
      Thread(parentThreadId: _entityOrNull(json['parentThreadId'], r)),
  'ThreadScore': (json, _) => ThreadScore((json['value'] as num).toDouble()),
  'ThreadId': (json, _) => ThreadId(json['value'] as String),
  'ThreadStatus': (json, _) =>
      ThreadStatus(ThreadStatusEnum.values.byName(json['value'] as String)),
  'ParentScene': (json, r) => ParentScene(r(json['scene'] as String)),
  'OriginActor': (json, r) => OriginActor(r(json['actor'] as String)),
  'GoalLink': (json, r) => GoalLink(_entityOrNull(json['goal'], r)),
  'DependsOnStep': (json, r) =>
      DependsOnStep(_entities(json['dependencies'], r)),
  'Step': (json, _) => Step(
    claim: json['claim'] as String,
    verificationKind: StepVerificationKind.values.byName(
      json['verificationKind'] as String? ?? 'open',
    ),
    status: StepLifecycle.values.byName(json['status'] as String? ?? 'open'),
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    criterionArgs:
        (json['criterionArgs'] as Map? ?? {}).cast<String, dynamic>(),
  ),
  'DerivedFromThread': (json, r) =>
      DerivedFromThread(r(json['thread'] as String)),
  'ThreadVisibility': (json, _) => ThreadVisibility(
    (json['visibleTo'] as List? ?? []).map((v) => AgentId(v as String)).toSet(),
  ),
  'BeatId': (json, _) => BeatId(json['value'] as String),
  'BelongsToThread': (json, r) => BelongsToThread(r(json['thread'] as String)),
  'SummarizesBeats': (json, r) =>
      SummarizesBeats(sources: _entities(json['sources'], r)),
  'BeatSequence': (json, _) => BeatSequence(json['value'] as int),
  'Speaker': (json, r) => Speaker(r(json['actor'] as String)),
  'AddressedTo': (json, r) => AddressedTo(_entityOrNull(json['actor'], r)),
  'BeatModality': (json, _) =>
      BeatModality(BeatModalityEnum.values.byName(json['value'] as String)),
  'BeatStatus': (json, _) =>
      BeatStatus(BeatStatusEnum.values.byName(json['value'] as String)),
  'ReplyToBeat': (json, r) => ReplyToBeat(r(json['beat'] as String)),
  'ObservesProp': (json, r) => ObservesProp(r(json['prop'] as String)),
  'PrivateToActor': (json, r) => PrivateToActor(r(json['actor'] as String)),
  'TextContent': (json, _) => TextContent(json['text'] as String),
  'TextStream': (json, _) => TextStream(
    chunks: List<String>.from(json['chunks'] as List? ?? []),
    cursor: json['cursor'] as int? ?? 0,
  ),
  'AudioStream': (json, _) => AudioStream(
    chunks: (json['chunks'] as List? ?? [])
        .map((v) => base64Decode(v as String))
        .toList(),
  ),
  'ActionPayload': (json, _) =>
      ActionPayload(Map<String, dynamic>.from(json['data'] as Map? ?? {})),
  'BeatToolCall': (json, _) => BeatToolCall(
    json['name'] as String,
    Map<String, dynamic>.from(json['args'] as Map? ?? {}),
  ),
  'ToolResult': (json, _) => ToolResult(json['result']),
  'ThoughtContent': (json, _) => ThoughtContent(json['text'] as String),
  'ObservationData': (json, _) => ObservationData(json['data']),
  'MemorySummary': (json, _) => MemorySummary(json['text'] as String),
  'SummaryOwner': (json, r) => SummaryOwner(r(json['actor'] as String)),
  'SummaryThread': (json, r) => SummaryThread(_entityOrNull(json['thread'], r)),
  'ToolResultContent': (json, _) =>
      ToolResultContent(name: json['name'] as String, output: json['output']),
  'IdentityBeat': (_, _) => const IdentityBeat(),
  'RetryCount': (json, _) => RetryCount(json['value'] as int),
  'ToolRoundCount': (json, _) => ToolRoundCount(json['value'] as int),
  'IdentitySeeded': (_, _) => const IdentitySeeded(),
};

Map<String, dynamic> snapshotWorld(World world) {
  world.flush();
  final records = <Map<String, dynamic>>[];
  for (final entry in _componentTypes.entries) {
    for (final (entity, component) in _collect(entry.key, world)) {
      final existing = records.where(
        (record) => record['id'] == entity.toJson(),
      );
      if (existing.isNotEmpty) {
        (existing.first['components'] as List).add(_encode(component));
      } else {
        records.add({
          'id': entity.toJson(),
          'components': [_encode(component)],
        });
      }
    }
  }
  return {'version': _snapshotVersion, 'entities': records};
}

World restoreWorld(Map<String, dynamic> snapshot) {
  if (snapshot['version'] != _snapshotVersion) {
    throw ArgumentError.value(snapshot['version'], 'version', 'unsupported');
  }
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ModelRouterResource(ModelRouter()));
  world.flush();

  final records = (snapshot['entities'] as List).cast<Map<String, dynamic>>();
  final newIds = [
    for (var i = 0; i < records.length; i++) world.reserveEmptyEntity().entity,
  ];
  world.flush();

  final oldToNew = <String, String>{
    for (var i = 0; i < records.length; i++)
      records[i]['id'] as String: newIds[i].toJson(),
  };
  Entity remap(String oldId) {
    final newId = oldToNew[oldId];
    if (newId == null)
      throw StateError('Snapshot references missing entity $oldId');
    final parts = newId.split('-');
    return Entity.create(int.parse(parts.first), int.parse(parts.last));
  }

  for (var i = 0; i < records.length; i++) {
    for (final raw in records[i]['components'] as List) {
      final data = Map<String, dynamic>.from(raw as Map);
      final type = (data['type'] ?? '') as String;
      final decoder = _decoders[type];
      if (decoder == null) throw StateError('Unknown component type: $type');
      world.upsertComponent(newIds[i], decoder(data, remap));
    }
  }
  world.flush();
  _rebuildFacetIndex(world);
  world.flush();
  return world;
}

void _rebuildFacetIndex(World world) {
  final index = world.getResource<FacetIndex>();
  index.clear();
  for (final (entity, text, thread)
      in world.query2<TextContent, BelongsToThread>()) {
    final structured = entity.get<ToolResultContent>();
    final indexedText = structured == null
        ? text.text
        : toolResultText(
            ToolExecutionResult(
              name: structured.name,
              output: structured.output,
            ),
          );
    index.indexBeat(
      entity.entity,
      keywordsOf(indexedText),
      thread: thread.thread,
    );
  }
}

@immutable
dynamic _jsonValue(dynamic value) {
  if (value == null || value is String || value is num || value is bool)
    return value;
  if (value is Map || value is List) return value;
  throw ArgumentError.value(value, 'value', 'not JSON-serializable');
}

List<Entity> _entities(dynamic values, Entity Function(String) remap) =>
    (values as List? ?? []).map((value) => remap(value as String)).toList();

Entity? _entityOrNull(dynamic value, Entity Function(String) remap) =>
    value == null ? null : remap(value as String);

TaskId? _taskId(dynamic value) =>
    value == null ? null : TaskId(value as String);
