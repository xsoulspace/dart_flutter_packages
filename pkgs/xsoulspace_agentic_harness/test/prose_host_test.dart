// ignore_for_file: lines_longer_than_80_chars

/// PLAN Stage I4 — prose host #2 (ADR 0015 three-hosts rule, second entry).
///
/// Claim: the SAME meaning tree + ONE collapsed surface (act_with_project)
/// carries a NON-code domain. One sentence → book outline (meaning nodes,
/// kind 'section') → filled sections as TextContent beats (facet-indexed).
/// Eval tier is `evidence` (ADR 0014 §3): prose has no falsifiable oracle,
/// so rows NEVER carry a loud pass — only structured evidence.
///
/// Deterministic end-to-end: the "model" is a scripted handler emitting the
/// same tiny moves a tiny model would pick. No LLM anywhere (North Star).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/act_with_project.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

World _world() => World()..addPlugin(AgentPlugin());

/// HOST PROGRAM (pure, deterministic): one sentence → book outline.
/// Strips the `<title>:` prefix, splits on ';' clauses, strips ordinal
/// markers. The outline lands as meaning nodes — the SAME tree the coding
/// hosts use. No separate "narrative data model" is minted (D1: the
/// meaning tree is the graph).
List<String> outlineFromSentence(String sentence) {
  final body = sentence.contains(':')
      ? sentence.substring(sentence.indexOf(':') + 1)
      : sentence;
  return [
    for (final clause in body.split(';'))
      if (clause.trim().isNotEmpty)
        clause.trim().replaceFirst(
              RegExp(r'^(first|second|third|fourth|fifth),\s*'),
              '',
            ),
  ];
}

/// Scripted generation handler: first [sections.length] decisions add one
/// section node each (meaning moves over the ONE tool); then one decision
/// per section emits the fill prose as TEXT — which the harness attaches as
/// a TextContent beat and facet-indexes automatically.
class _ProseScriptedHandler implements GenerationHandler {
  _ProseScriptedHandler(this.sections);
  final List<String> sections;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final turn = turns;
    turns++;
    if (turn < sections.length) {
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': 'outlining ${sections[turn]}'},
        rawOutput: 'outlining ${sections[turn]}',
        toolCalls: [
          ToolCall(name: const ToolName('act_with_project'), arguments: {
            'action': 'add',
            'kind': 'section',
            'label': sections[turn],
            'props': {'book': 'a short book about tea'},
          }),
        ],
        taskId: request.taskId,
      );
    }
    final fillIndex = turn - sections.length;
    if (fillIndex < sections.length) {
      // Prose fill: the TEXT becomes a beat (facet-indexed by the harness);
      // a cheap `list` tool call keeps the ReAct chain alive so the next
      // section can be filled in a later round.
      final label = sections[fillIndex];
      final fill =
          '$label — tea began long ago and every cup carries that past. '
          'This section on $label keeps the thread of the book.';
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': fill},
        rawOutput: fill,
        toolCalls: fillIndex == sections.length - 1
            ? const []
            : [const ToolCall(name: ToolName('act_with_project'), arguments: {
                  'action': 'list',
                })],
        taskId: request.taskId,
      );
    }
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }

  int turns = 0;
}

void main() {
  test('prose host: sentence → meaning-tree outline → facet-indexed fill '
      'beats, evidence tier (never loud pass)', () async {
    const sentence = 'a short book about tea: first, its history; '
        'second, how it is brewed; third, where it is enjoyed';
    final sections = outlineFromSentence(sentence);
    expect(sections, ['its history', 'how it is brewed', 'where it is enjoyed']);

    final world = _world();
    final router = ModelRouter(inferenceClientsBuilders: {});
    router.models[const ModelId('prose')] = const Model(
      id: ModelId('prose'),
    );
    world
      ..upsertResource(ModelRouterResource(router))
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(
        AgencyPolicy(maxConcurrent: 1),
      )
      ..flush();
    world.getResource<GenerationHandlerResource>().registerDefault(
          _ProseScriptedHandler(sections),
        );

    final registry = ToolRegistry();
    registry.register(actWithProjectTool(
      world: world,
      materialize: () async => {'materialized': true},
    ));
    world.getResource<ToolRegistryResource>().register('default', registry);

    final scene = world.spawnComponents([const Scene(), SceneFrame()]);
    final actor = world.spawnComponents([
      Actor(agentId: AgentId.create()),
      const ActorModel(modelId: ModelId('prose')),
      const ActorSystemPrompt(
        text: 'Outline the book, then fill each section with prose. '
            'One act_with_project move or one prose passage per turn.',
      ),
      ActorThreads(threads: []),
      const ActorTools(registryName: 'default'),
      PresentInScene(sceneEntity: scene),
      const OpenDecision(prompt: sentence),
    ]);
    final thread = spawnThread(world, actor, scene);
    world.upsertComponent(actor, ActorThreads(threads: [thread]));
    world.flush();

    await HarnessLoop(world: world).runUntilIdle();
    expectIdle(world);

    // 1. The outline lives in the SAME meaning tree (D1) — no new model.
    final view = meaningView(world);
    final sectionNodes = view.nodes
        .where((n) => n['kind'] == 'section')
        .map((n) => n['label'])
        .toSet();
    expect(sectionNodes, sections.toSet());

    // 2. Fills are beats, ray-projection-reachable via the facet index:
    //    the host queries the SAME projection law as any other domain.
    final facet = world.getResource<FacetIndex>();
    final fillsFound = <String, bool>{};
    for (final label in sections) {
      final hits = facet.beatsFor(keywordsOf(label)).toList();
      final fillBeat = hits.any((e) {
        final text = world.getEntity(e).$1.get<TextContent>();
        // Response beats render as "text: <content>" — strip the label.
        return text != null && text.text.startsWith('text: $label');
      });
      fillsFound[label] = fillBeat;
    }
    expect(fillsFound.values.every((f) => f), isTrue,
        reason: 'every section fill must be facet-reachable: $fillsFound');

    // 3. Evidence tier (ADR 0014 §3): rows carry structured evidence and
    //    NEVER a loud pass — `passed` stays null by construction.
    final filledCount = fillsFound.values.where((f) => f).length;
    final summary = DatasetResultSummary([
      DatasetRow(
        task: 'outline',
        backend: EvalBackend.scripted,
        tokens: 0,
        calls: sections.length,
        evidence: '${sections.length} sections as meaning nodes',
      ),
      DatasetRow(
        task: 'fill',
        backend: EvalBackend.scripted,
        tokens: 0,
        calls: 0,
        evidence: '$filledCount/${sections.length} sections filled '
            'as facet-indexed beats',
      ),
    ]);
    expect(summary.evidenceCount, 2);
    expect(summary.passableCount, 0, reason: 'prose is never passable');
    expect(summary.passedCount, 0, reason: 'never a loud pass');
    expect(summary.passRate, 0.0);

    // 4. The serialized row shape carries evidence, not verdicts.
    final rowJson = jsonEncode(summary.rows.last.toJson());
    expect(rowJson, contains('"evidence"'));
    expect(rowJson, isNot(contains('"passed"')));
  });

  test('prose host vocabulary: sections are just meaning nodes, '
      'so the stewardship probe holds across hosts', () {
    final world = _world();
    final sections = outlineFromSentence(
      'book: first, alpha; second, beta',
    );
    for (final label in sections) {
      addMeaningNode(world, kind: 'section', label: label);
    }
    final view = meaningView(world);
    expect(view.nodes.where((n) => n['kind'] == 'section').length, 2);
    // Same closed zoom vocabulary applies — summary zoom aggregates sections.
    final cut = meaningCut(world, zoom: 'summary');
    expect((cut['kinds'] as Map)['section'], 2);
  });
}
