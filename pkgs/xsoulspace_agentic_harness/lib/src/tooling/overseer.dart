// ignore_for_file: lines_longer_than_80_chars

/// J7 — the overseer actor: zoom strategies across actors.
///
/// One actor takes small decisions (point zoom); a second holds the bigger
/// picture (summary zoom) and reviews the structured gate evidence. When the
/// mover's goal-attempt budget is exhausted (J1.5.1), the overseer system
/// spawns an OVERSEER actor whose decision sees ONLY:
///
/// - the **summary zoom** of the meaning tree (`meaningCut(zoom: 'summary')`
///   — kind histogram + aggregated edges, no node details);
/// - the **structured gate failure** (the `GoalAttemptsExhausted` reason);
/// - the **failing intent's chain dump** (`validateMeaningProgram` problems
///   + the chain ops + an interpreter replay of the failing call).
///
/// Its decision vocabulary is CLOSED: `approve` / `repair(intent, notes)` /
/// `escalate(reason)` — one tool (`overseer_decision`), no free-form path.
/// `repair` re-opens exactly one intent's scope via [openFreshDecision] on
/// the MOVER with the overseer's notes prepended (max [OverseerLedger.maxCycles]
/// cycles). `escalate` is the J8.1 rung: swap to a higher `Model.tier` if the
/// router declares one, else a structured FAIL. Approval never forces a pass:
/// the mechanical final oracle still decides.
///
/// `Agent = G ∘ F`: the overseer is a tiny selection over a budgeted view;
/// spawning, briefs, budgets and the disposition machinery are host programs.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, Model, SchemaBundle, ToolDef, ToolName;

import '../../xsoulspace_agentic_harness.dart'
    show ActorModel, AgentId, MeaningIndex, MeaningNode, MeaningProps,
        ModelId, ModelRouterResource, OpenDecision, PresentInScene, ToolRegistry,
        ToolRegistryResource, meaningComponentOf, meaningCut;
import '../data_models/components.dart'
    show Actor, ActorSystemPrompt, ActorThreads, ActorTools, EscalationRequest,
        GoalAttemptsExhausted;
import '../meaning/meaning_program.dart'
    show chainSpecError, interpretMeaningProgram, meaningExecutorOps,
        validateMeaningProgram;
import '../narrative/components.dart'
    show ThreadStatus, ThreadStatusEnum;
import '../schedules.dart' show Schedules;
import 'build_gates.dart'
    show IntentGoalSpec, OverseerLedger, openFreshDecision;

/// Teaching for the overseer actor (host-authored; only the overseer sees it).
const overseerSystemPrompt =
    'You are the OVERSEER. A mover actor tried to build/fix a meaning '
    'program and exhausted its verification budget. You see only the '
    'summary zoom, the structured gate failure, and the failing chain '
    'dump — never raw tool noise. Decide ONCE with the overseer_decision '
    'tool: approve (the state is acceptable as-is), repair(intent, notes, '
    'specs?) (re-open exactly that intent), or escalate(reason) (nothing '
    'salvageable). HARD RULES: ops exist ONLY in the dump\'s valid_ops '
    'list — NEVER name an op outside it (there is no return_value; the '
    'vocabulary is exactly valid_ops). Prefer repair with SPECS: the '
    'dump\'s chain_rows are already in intent_define row format — copy '
    'them and change ONLY the rows that are wrong (fix label/a/b/next or '
    'jumps_to → b: "#row"). With specs, the mover applies them verbatim; '
    'notes alone make the mover guess.';

/// The chain dump for one intent: validation problems, the chain ops
/// (id/label/props/next), and an interpreter replay of the failing call
/// over a FRESH state (the same semantics the oracle replay uses).
Map<String, dynamic> meaningChainDump(
  World world,
  String intent,
  Map<String, dynamic> args,
) {
  final replay = interpretMeaningProgram(world, intent, {}, args);
  final index = world.getResource<MeaningIndex>();
  String? entry;
  final nextOf = <String, String>{};
  for (final (from, relation, to) in index.triples) {
    if (relation == 'impl' && from == intent) entry = to;
    if (relation == 'then') nextOf[from] = to;
  }
  // Render the chain as SPEC ROWS (the address space repairs happen in:
  // intent_define rows carry `next` indices and `b: '#row'` jump targets —
  // the on-device P2 finding showed op-entity ids like `op_11` are a
  // different address space the mover cannot repair in).
  final rows = <Map<String, dynamic>>[];
  final opIdToRow = <String, int>{};
  var cursor = entry;
  var guard = 0;
  while (cursor != null && guard++ < 64) {
    opIdToRow[cursor] = rows.length;
    final entity = index.byId[cursor];
    Map<String, dynamic> json = {'row': rows.length, 'op': '?'};
    if (entity != null) {
      final node = meaningComponentOf<MeaningNode>(world, entity);
      final props =
          meaningComponentOf<MeaningProps>(world, entity) ??
          const MeaningProps();
      if (node != null) {
        json = {
          'row': rows.length,
          'op': node.label,
          'a': props.props['a'],
          'b': props.props['b'],
        };
      }
    }
    rows.add(json);
    cursor = nextOf[cursor];
  }
  // Rewrite jump targets ('#row' strings and raw ids) into row indices so
  // the dump is directly diffable against intent_define specs.
  for (final row in rows) {
    final b = row['b'];
    if (b is String && b.startsWith('#')) {
      final target = int.tryParse(b.substring(1));
      row['jumps_to'] = target;
    }
  }
  return {
    'intent': intent,
    'valid_ops': meaningExecutorOps,
    'problems': validateMeaningProgram(world),
    'chain_rows': rows,
    'replay_result': replay['_result'],
  };
}

/// The overseer's ENTIRE decision view: summary zoom + structured gate
/// failure + the failing intent's chain dump. Harness-owned context (D7).
String buildOverseerBrief(
  World world, {
  required String gateFailure,
  String? failingIntent,
  Map<String, dynamic> failingArgs = const {},
}) {
  final summary = meaningCut(world, zoom: 'summary');
  final buf = StringBuffer()
    ..writeln('OVERSEER BRIEF')
    ..writeln(
      'The mover exhausted its goal-attempt budget. Decide the disposition '
      'with the overseer_decision tool (exactly ONE call).',
    )
    ..writeln('--- structured gate failure ---')
    ..writeln(gateFailure)
    ..writeln('--- meaning summary zoom ---')
    ..writeln(jsonEncode(summary));
  if (failingIntent != null) {
    buf
      ..writeln('--- failing intent chain dump: $failingIntent ---')
      ..writeln(jsonEncode(meaningChainDump(world, failingIntent, failingArgs)));
  }
  return buf.toString();
}

/// J7 system (schedule on [Schedules.narrative] via [wireOverseer]): when the
/// mover's goal budget is exhausted and the overseer ledger has budget,
/// spawn the overseer actor with the brief. The exhaustion record moves to
/// the overseer's custody — the disposition tool re-stamps a terminal record
/// unless it grants a repair.
Future<void> overseerEscalationSystem(World world) async {
  maybeSpawnOverseer(world);
}

/// Spawns the overseer for the exhausted mover when the ledger allows.
/// Returns true when a spawn happened. Callable from hosts DIRECTLY: a
/// stamp-only world has no open work, so `runUntilIdle` may exit before the
/// scheduled system ever ticks (the on-device P2 finding) — the driver
/// therefore invokes this explicitly before its overseer session.
bool maybeSpawnOverseer(World world) {
  OverseerLedger? ledger;
  try {
    ledger = world.getResource<OverseerLedger>();
  } on StateError {
    return false; // overseer not wired → no-op
  }
  if (ledger.overseerPending || !ledger.canAct) return false;
  final exhausted = world.query2<Actor, GoalAttemptsExhausted>().toList();
  if (exhausted.isEmpty) return false;

  final (facade, _, _) = exhausted.first;
  final mover = facade.entity;
  // The structured gate failure IS the exhaustion reason.
  final we = world.getEntity(mover).$1;
  final gateFailure = we.get<GoalAttemptsExhausted>()?.reason ?? 'unknown';
  // Which intent failed? The verifier's structured detail names it
  // ("intents failed: <intent> → ..."); args come from the wired spec.
  String? failingIntent;
  final match = RegExp(r'intents failed: (\S+) →').firstMatch(gateFailure);
  if (match != null) failingIntent = match.group(1);
  var failingArgs = const <String, dynamic>{};
  try {
    final spec = world.getResource<IntentGoalSpec>();
    if (failingIntent == null && spec.sequence.isNotEmpty) {
      failingIntent = spec.sequence.first.intent;
    }
    for (final e in spec.sequence) {
      if (e.intent == failingIntent) {
        failingArgs = e.args;
        break;
      }
    }
  } on StateError {
    // no intent spec (run-graded tasks): the gate failure still travels.
  }

  final brief = buildOverseerBrief(
    world,
    gateFailure: gateFailure,
    failingIntent: failingIntent,
    failingArgs: failingArgs,
  );
  ledger
    ..overseerPending = true
    ..lastGateFailure = gateFailure
    ..lastBrief = brief;

  // The overseer sees the same model the mover used (same ModelId).
  final moverModel = we.get<ActorModel>()?.modelId ?? ModelId.create();
  // The overseer joins the MOVER's existing scene (projection supports a
  // single scene; the overseer is a peer actor in the same world).
  final moverScene = we.get<PresentInScene>()?.sceneEntity;
  _ensureOverseerRegistry(world, mover: mover);

  final overseerComponents = <Component>[
    Actor(agentId: AgentId.create()),
    ActorModel(modelId: moverModel),
    const ActorSystemPrompt(text: overseerSystemPrompt),
    const ActorTools(registryName: 'overseer'),
    OpenDecision(prompt: brief),
    if (moverScene != null) PresentInScene(sceneEntity: moverScene),
  ];
  world.spawnComponents(overseerComponents);
  // NOTE: the mover's GoalAttemptsExhausted record STAYS stamped while the
  // overseer deliberates (it also blocks the policy from re-prompting). The
  // disposition tool moves it: a repair removes it (fresh decision);
  // approve/escalate/repair_denied keep the terminal record.
  world.flush();
  return true;
}

void _ensureOverseerRegistry(World world, {required Entity mover}) {
  final resource = world.getResource<ToolRegistryResource>();
  if (resource.get('overseer') == null) {
    final registry = ToolRegistry();
    registry.register(overseerDecisionTool(world, mover: mover));
    resource.register('overseer', registry);
  }
}

/// The overseer's CLOSED decision vocabulary — one tool, one call.
ToolDef overseerDecisionTool(World world, {required Entity mover}) =>
    ToolDef.encode(
      name: const ToolName('overseer_decision'),
      description:
          'Your disposition for the exhausted mover. Exactly ONE call. '
          'approve: the current state is acceptable as-is (the mechanical '
          'final oracle still decides). repair: re-open exactly ONE intent '
          "with your notes (notes are the mover's only steering — name the "
          'wrong op/wiring and the correct one). escalate: nothing '
          'salvageable — hand the structured reason to the ladder.',
      argsSchema: SchemaBundle(
        root: FM.object('overseer_decision', properties: () => [
          FM.prop('action', FM.enum_('action', const [
            'approve',
            'repair',
            'escalate',
          ])),
          FM.prop('intent', FM.string(), optional: true),
          FM.prop('notes', FM.string(), optional: true),
          FM.prop('reason', FM.string(), optional: true),
          FM.prop('specs', FM.array(FM.object('spec', properties: () => [
            FM.prop('label', FM.string()),
            FM.prop('a', FM.string(), optional: true),
            FM.prop('b', FM.string(), optional: true),
            FM.prop('next', FM.integer(), optional: true),
          ])), optional: true),
        ]),
      ),
      execute: (args) async {
        final map = args is Map ? args : const {};
        final action = map['action'];
        final ledger = world.getResource<OverseerLedger>();
        ledger.overseerPending = false;
        final we = world.getEntity(mover).$1;

        String dispositionRecord(String disposition, Map<String, dynamic> extra) {
          final record = {'disposition': disposition, ...extra};
          ledger.records.add(record);
          return jsonEncode(record);
        }

        switch (action) {
          case 'repair':
            final intent = map['intent'];
            if (intent is! String || intent.isEmpty) {
              ledger.overseerPending = true; // still undecided — retry
              return {
                'ok': false,
                'error': 'repair requires the intent name to re-open',
              };
            }
            if (!ledger.canRepair) {
              // J8.1 rung: budget spent — structured FAIL, not a silent loop.
              const reason = 'overseer repair budget exhausted';
              ledger.disposed = true;
              _stampTerminal(world, mover, '$reason; last gate failure: '
                  '${ledger.lastGateFailure}');
              return {
                'ok': false,
                'disposition': 'repair_denied',
                'record': dispositionRecord('repair_denied', {
                  'intent': intent,
                  'reason': reason,
                }),
              };
            }
            ledger.cycles++;
            final notes = map['notes'] is String ? map['notes'] as String : '';
            we
              ..remove<GoalAttemptsExhausted>()
              ..remove<EscalationRequest>();
            _resumeThreads(world, mover);
            // Fresh decision (the ONLY budget-reset path, J1.5.2) on the
            // MOVER — the overseer's notes prepended, scope limited to the
            // ONE intent the overseer named.
            openFreshDecision(
              world,
              mover,
              prompt: 'OVERSEER REPAIR (cycle ${ledger.cycles}/'
                  '${ledger.maxCycles}) — repair ONLY the intent "$intent".\n'
                  'Overseer notes: $notes\n\n'
                  'Gate failure being repaired:\n${ledger.lastGateFailure}\n\n'
                  'Fix the named intent (intent_define action=define with '
                  'corrected specs replaces its chain atomically), materialize, '
                  'and call the intents to verify.',
            );
            return {
              'ok': true,
              'disposition': 'repair',
              'intent': intent,
              'cycle': ledger.cycles,
              'record': dispositionRecord('repair', {
                'intent': intent,
                'notes': notes,
                'cycle': ledger.cycles,
              }),
            };
          case 'approve':
            // Approval never forces a pass: the terminal record is stamped
            // and the mechanical final oracle still grades the run.
            ledger.disposed = true; // approve is final
            _stampTerminal(
              world,
              mover,
              'overseer approved the current state; final mechanical oracle '
                  'decides. Gate failure was: ${ledger.lastGateFailure}',
            );
            return {
              'ok': true,
              'disposition': 'approve',
              'record': dispositionRecord('approve', const {}),
            };
          case 'escalate':
            final reason = map['reason'] is String ? map['reason'] as String : 'unspecified';
            // J8.1 rung: swap to a higher Model.tier if the router declares
            // one; else structured FAIL.
            final higher = _higherTierModel(world, mover);
            if (higher != null && !ledger.escalatedToTier) {
              // An escalation consumes the overseer's one cycle.
              ledger
                ..escalatedToTier = true
                ..cycles = ledger.cycles + 1;
              we.remove<GoalAttemptsExhausted>();
              _resumeThreads(world, mover);
              world.upsertComponent(mover, ActorModel(modelId: higher.id));
              openFreshDecision(
                world,
                mover,
                prompt: 'TIER ESCALATION — a stronger model now owns this '
                    'goal.\nOverseer reason: $reason\n\n'
                    'Gate failure:\n${ledger.lastGateFailure}\n'
                    'Repair the goal.',
              );
              return {
                'ok': true,
                'disposition': 'escalate',
                'tier': higher.tier,
                'record': dispositionRecord('escalate', {
                  'reason': reason,
                  'tier': higher.tier,
                }),
              };
            }
            ledger.disposed = true; // structured FAIL is final
            _stampTerminal(
              world,
              mover,
              'escalate: $reason (no higher model tier available). '
                  'Gate failure was: ${ledger.lastGateFailure}',
            );
            return {
              'ok': true,
              'disposition': 'escalate_failed',
              'record': dispositionRecord('escalate_failed', {'reason': reason}),
            };
          default:
            ledger.overseerPending = true; // still undecided — retry
            return {'ok': false, 'error': 'unknown disposition: $action'};
        }
      },
    );

void _stampTerminal(World world, Entity mover, String reason) {
  world.getEntity(mover).$1
    ..insert(GoalAttemptsExhausted(reason))
    ..insert(EscalationRequest(reason: reason));
  world.flush();
}

/// Resumes the mover's suspended threads so the granted decision can run.
void _resumeThreads(World world, Entity mover) {
  final threads =
      world.getEntity(mover).$1.get<ActorThreads>()?.threads ?? const [];
  for (final t in threads) {
    final (we, valid) = world.getEntity(t);
    if (!valid) continue;
    final status = we.get<ThreadStatus>();
    if (status != null) status.value = ThreadStatusEnum.active;
  }
  world.flush();
}

/// Finds a declared higher-tier model in the router (J8.1 rung). Null when
/// none exists — the structured FAIL path.
Model? _higherTierModel(World world, Entity mover) {
  try {
    final router = world.getResource<ModelRouterResource>().router;
    final currentTier =
        world.getEntity(mover).$1.get<ActorModel>()?.let((am) => router.models[am.modelId]?.tier ?? 0) ??
        0;
    Model? best;
    for (final m in router.models.values) {
      if (m.tier > currentTier && (best == null || m.tier > best.tier)) {
        best = m;
      }
    }
    return best;
  } on StateError {
    return null;
  }
}

// The `.let` helper above keeps the tier lookup null-safe without pulling in
// a package dependency.
extension _Let<T> on T? {
  R? let<R>(R Function(T) f) {
    final self = this;
    return self == null ? null : f(self);
  }
}

// Schedules import kept last so the system can be scheduled by hosts; the
// wire function mirrors wireRunGradedGoal's shape.
/// Wires the J7 overseer: ledger + escalation system on the narrative
/// schedule. [moverActor] is the goal-carrying actor the overseer reviews.
void wireOverseer(World world, {required Entity moverActor, int maxCycles = 1}) {
  world
    ..upsertResource(OverseerLedger(maxCycles: maxCycles))
    ..schedule(Schedules.narrative)
    .add(overseerEscalationSystem, name: 'overseerEscalationSystem');
  world.flush();
}
