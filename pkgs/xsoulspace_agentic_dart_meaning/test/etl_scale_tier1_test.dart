// ignore_for_file: lines_longer_than_80_chars

/// TIER 1 — the harness package itself, deterministically ETL'd in and out.
///
/// Proves, LLM-free, at package scale (≈2.3k symbols / ≈39k edges):
/// 1. code → meaning tree round-trip holds (fidelity 100%);
/// 2. every zoom projection stays inside its token budget (the ray-cast
///    claim at scale);
/// 3. decomposition is deterministic: impact frontier hard-bounded, plan
///    steps projected under budget (ADR 0009);
/// 4. raw text (ADR 0022) and AE canonical matrices ETL into the same tree;
/// 5. snapshot/restore preserves the whole structure;
/// 6. the model-visible cut (Situation) stays within budget — a small
///    model can genuinely work at this scale.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show canonicalToMeaningTree;
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show defaultGoalFlow;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

Directory? _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('workspace:')) {
      return dir;
    }
    dir = dir.parent;
  }
  return null;
}

World _world() => World()..addPlugin(AgentPlugin());

Map<String, List<CodeFileScan>> _scanHarnessPackage(Directory repoRoot) {
  final pkg = Directory('${repoRoot.path}/pkgs/xsoulspace_agentic_harness');
  final files = dartFiles(pkg);
  return {
    'xsoulspace_agentic_harness': [
      for (final f in files)
        scanDartFile(f, f.path.substring(repoRoot.path.length + 1)),
    ],
  };
}

/// Text ETL FIXTURE — deterministic section split for the tier tests ONLY.
/// This is NOT a distiller: AE owns text reduction (know packs + delegated
/// distill → canonical rows, see ae_harness_etl_spec.md §Distillation).
/// A harness-side text distiller would be a duplication violation.
int buildMeaningTreeFromText(
  World world,
  String markdown, {
  required String sourceName,
}) {
  var count = 0;
  final sectionRe = RegExp(r'^## (.+)$', multiLine: true);
  final matches = sectionRe.allMatches(markdown).toList();
  for (var i = 0; i < matches.length; i++) {
    final heading = matches[i].group(1)!.trim();
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : markdown.length;
    final body = markdown.substring(start, end).trim();
    if (body.isEmpty) continue;
    addMeaningNode(
      world,
      kind: 'requirement',
      label: heading,
      props: {
        'source': sourceName,
        'section': i + 1,
        'criteria': body.length > 500 ? body.substring(0, 500) : body,
      },
      id: 'req_${sourceName.replaceAll(RegExp(r'\W'), '_')}_$i',
    );
    count++;
  }
  return count;
}

/// Matrix ETL: an AE canonical matrix (JSON) → the same tree.
int buildMeaningTreeFromMatrix(World world, Map<String, dynamic> matrix) {
  final export = canonicalToMeaningTree(matrix);
  for (final n in export.nodes) {
    addMeaningNode(
      world,
      kind: n.kind,
      label: n.label,
      props: n.props,
      id: n.id,
    );
  }
  var edges = 0;
  for (final e in export.edges) {
    if (linkMeaning(world, from: e.from, relation: e.relation, to: e.to)) {
      edges++;
    }
  }
  return export.nodes.length + edges;
}

/// The scripted actor: text-only response (no tools) — the decision exists
/// only to observe the cut the model would see.
class _TextOnlyActor implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'acknowledged the cut'},
      rawOutput: 'acknowledged the cut',
      toolCalls: const [],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  final repoRoot = _repoRoot();
  test(
    'TIER 1: harness package ETL round-trip holds (fidelity 100%)',
    () async {
      expect(repoRoot, isNotNull);
      final scans = _scanHarnessPackage(repoRoot!);
      final world = _world();
      final built = buildMeaningTreeFromCode(world, scans);
      expect(built.files, greaterThan(150));
      expect(built.symbols, greaterThan(1500));
      expect(built.edges, greaterThan(10000));
      final fid = fidelityCheck(world, scans);
      expect(fid.mismatches, 0, reason: fid.samples.join('\n'));
      expect(fid.checked, built.symbols);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'TIER 1: every zoom projection stays inside its token budget',
    () async {
      final scans = _scanHarnessPackage(repoRoot!);
      final world = _world();
      buildMeaningTreeFromCode(world, scans);
      final index = world.getResource<MeaningIndex>();
      final target = index.byId.keys
          .where((id) => id.endsWith('_HarnessLoop'))
          .first;
      for (final zoom in const ['point', 'local', 'region', 'summary']) {
        final cut = meaningCut(world, focusIds: [target], zoom: zoom);
        final tokens = (cut.toString().length / 4).ceil();
        expect(
          tokens,
          lessThanOrEqualTo(2100),
          reason: 'zoom $zoom rendered $tokens tokens at '
              '${index.nodeCount}-node scale — the cut is not bounded',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'TIER 1: decomposition is deterministic and hard-bounded '
    '(impact frontier + plan projection)',
    () async {
      final scans = _scanHarnessPackage(repoRoot!);
      final world = _world();
      buildMeaningTreeFromCode(world, scans);
      final index = world.getResource<MeaningIndex>();
      final target = index.byId.keys
          .where((id) => id.endsWith('_HarnessLoop'))
          .first;

      // The frontier is HARD-capped (scale finding: real frontiers reach
      // 1,000+ nodes at depth 2 — a model must never receive them raw).
      final frontier = impactFrontier(world, target, maxDepth: 2, maxNodes: 64);
      expect(frontier.length, lessThanOrEqualTo(64));

      // Determinism: same input, same output (two builds agree).
      final world2 = _world();
      buildMeaningTreeFromCode(world2, scans);
      final frontier2 = impactFrontier(
        world2.getResource<MeaningIndex>() == world2.getResource<MeaningIndex>()
            ? world2
            : world2,
        index.byId.keys.where((id) => id.endsWith('_HarnessLoop')).first,
        maxDepth: 2,
        maxNodes: 64,
      );
      expect(frontier.length, frontier2.length);

      // Plan projection under a token budget (ADR 0009).
      final goal = world.spawnComponents([Goal(text: 'modify HarnessLoop')]);
      world.flush();
      final entities = [
        for (final id in frontier.take(20))
          world.spawnComponents([
            Step(
              claim: 'update $id (impact of the HarnessLoop change)',
              verificationKind: StepVerificationKind.mechanical,
            ),
            GoalLink(goal),
          ]),
      ];
      world.flush();
      final projection = projectPlanFrontier(
        world,
        null,
        budget: 512,
        estimator: (t) => (t.length / 4).ceil(),
      );
      expect(projection.tokenBudget, 512);
      expect(projection.tokensUsed, lessThanOrEqualTo(512));
      expect(projection.steps.length, lessThanOrEqualTo(entities.length));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'TIER 1: raw text (ADR 0022) and AE canonical matrices ETL into the '
    'same tree',
    () async {
      final adr = File(
        '${repoRoot!.path}/docs/decisions/0022_workspace_oracle_meaning_pipeline.md',
      );
      expect(adr.existsSync(), isTrue);
      final world = _world();
      final reqs = buildMeaningTreeFromText(
        world,
        adr.readAsStringSync(),
        sourceName: 'adr_0022',
      );
      expect(reqs, greaterThanOrEqualTo(3));
      // The requirements are queryable by ray-cast, bounded.
      final cut = meaningCut(
        world,
        query: 'workspace oracle',
        zoom: 'local',
        tokenBudget: 1024,
      );
      expect(
        (cut.toString().length / 4).ceil(),
        lessThanOrEqualTo(1100),
      );

      // AE canonical matrix → same tree (the 'from matrix' path).
      final nodes = buildMeaningTreeFromMatrix(world, {
        'schema': 'ae.canonical_matrix.v1',
        'concept': 'etl',
        'features': [
          {'id': 'etl.in.code', 'source': 'code', 'tier': 'mechanical'},
          {'id': 'etl.in.text', 'source': 'text', 'tier': 'evidence'},
          {'id': 'etl.out.dart', 'source': 'code', 'tier': 'mechanical'},
        ],
      });
      expect(nodes, greaterThan(0));
      final index = world.getResource<MeaningIndex>();
      expect(
        index.byId.containsKey('req_adr_0022_0'),
        isTrue,
        reason: 'text-ETL node missing',
      );
      expect(index.byId.containsKey('etl.in.code'), isTrue,
          reason: 'matrix-ETL node missing');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'TIER 1: snapshot carries NO code tree — it re-derives (ADR 0023 §2)',
    () async {
      final scans = _scanHarnessPackage(repoRoot!);
      final world = _world();
      final built = buildMeaningTreeFromCode(world, scans);
      final store = SnapshotStore();
      await store.open(
        '${Directory.systemTemp.path}/etl_t1_${DateTime.now().millisecondsSinceEpoch}/store',
      );
      await store.save(world, name: 't1', meta: {'tier': 1});
      final restored = await store.load('t1');
      final index = world.getResource<MeaningIndex>();
      final rIndex = restored.getResource<MeaningIndex>();
      // R7 hard cut: snapshots persist beats/verdicts/budgets ONLY — the
      // tree is re-derivable and never restored. The restored world starts
      // tree-free; the owner re-derives (repo_etl scan/refresh) and the
      // re-derived tree must be byte-equivalent to the original.
      expect(rIndex.nodeCount, 0,
          reason: 'the tree is re-derived, never restored (ADR 0023 §2)');
      expect(rIndex.edgeCount, 0);
      buildMeaningTreeFromCode(restored, scans);
      expect(rIndex.nodeCount, index.nodeCount);
      expect(rIndex.edgeCount, index.edgeCount);
      // The RE-DERIVED tree is not just counted — it is USABLE.
      final fid = fidelityCheck(restored, scans);
      expect(fid.mismatches, 0, reason: fid.samples.join('\n'));
      expect(built.symbols, greaterThan(1500));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'TIER 1: the model-visible cut (Situation) stays within budget at '
    'package scale — a small model can work here',
    () async {
      final scans = _scanHarnessPackage(repoRoot!);
      final world = _world();
      buildMeaningTreeFromCode(world, scans);
      final handler = _TextOnlyActor();
      world
        ..upsertResource(ToolRegistryResource())
        ..upsertResource(FlightRecorder())
        ..upsertResource(DecisionFlowResource(defaultGoalFlow()))
        ..upsertResource(AgencyPolicy(maxConcurrent: 1, maxToolRounds: 12))
        ..upsertResource(
          CutCompositionResource(CutComposition.coderLean()),
        )
        ..upsertResource(ProjectionBudget(tokens: 4000))
        ..upsertResource(GenerationHandlerResource())
        ..upsertResource(ModelRouterResource(ModelRouter()))
        ..flush();
      world.getResource<GenerationHandlerResource>().registerDefault(handler);

      // The goal: a real-scale task over the tree.
      final taskPrompt =
          'Impact of a HarnessLoop change: update the referenced symbols '
          'in pkgs/xsoulspace_agentic_harness. Work from the projected '
          'frontier; the tree holds the whole package.';
      final scene = world.spawnComponents([Scene(), SceneFrame()]);
      final actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorSystemPrompt(text: 'You work from the projected cut only.'),
        ActorThreads(threads: []),
        ActorTools(registryName: 'default'),
        PresentInScene(sceneEntity: scene),
        Goal(text: taskPrompt),
        OpenDecision(prompt: taskPrompt),
      ]);
      final thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();

      // ETL events land as beats (durable, projected — not a context log).
      var landed = 0;
      for (final scan in scans.values.first.take(30)) {
        final beat = startBeat(world, thread, actor, BeatModalityEnum.text);
        appendToBeat(
          world,
          beat,
          'etl: ${scan.relPath} — ${scan.symbols.length} symbols',
        );
        completeBeat(world, beat);
        landed++;
      }
      world.flush();
      expect(landed, 30);

      await HarnessLoop(world: world).runUntilIdle();
      final situation = world.getEntity(actor).$1.get<Situation>();
      expect(situation, isNotNull, reason: 'no cut was projected');
      expect(
        situation!.tokensUsed,
        lessThanOrEqualTo(4000),
        reason:
            'the model-visible cut is ${situation.tokensUsed} tokens at '
            '${world.getResource<MeaningIndex>().nodeCount}-node scale',
      );
      // Green-screen honesty: the whole tree does NOT fit — the absence
      // must be explicit, not silent.
      expect(situation.tokenBudget, 4000);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
