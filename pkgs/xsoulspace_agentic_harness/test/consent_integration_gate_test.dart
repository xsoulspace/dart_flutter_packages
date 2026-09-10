// ignore_for_file: lines_longer_than_80_chars

/// Consent-scoping INTEGRATION gate (follow-ups 3+4) — the pure v2 model
/// (`consent_scoping.dart`) wired to the daemon consent paths and the
/// mechanical actors.
///
/// Claims under test:
/// 1. Explicit actor plans beat the `*` fallback, per (actor, verb, path):
///    actor A's plan grants A and NOT B on the same path (B is routed to
///    noPlan / its own explicit plans — one actor's grant never covers
///    another).
/// 2. A legacy v1 workspace plan still answers mechanically — the v1
///    backward-compat parse (`consentLedgerFromDocument` /
///    `ConsentPlan.v1`) lands it as the `*` fallback and the session's
///    derived actor falls through to it.
/// 3. Every decision appends an actor-keyed, append-only
///    `ConsentAuditEntry`; `auditFor` never leaks another actor's rows;
///    the structured `toJson` row carries the named reason.
/// 4. The mechanical actor's consent callback can be constructed FROM the
///    ledger (`consentFromLedger`): a step outside the grant is DENIED
///    (named `mechanical_actor_unconsented`, step stays open), a step
///    inside it executes; deny-by-default is unchanged when the caller
///    passes no ledger callback.
/// 5. The glue is honest: `sessionConsentActor` is a deterministic
///    derivation (stable per workspace, distinct across workspaces);
///    `resetPlans` reconfigures plans WITHOUT touching the append-only
///    audit.
library;

import 'package:ecsly/ecsly.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/data_models/data_models.dart'
    show StepAction, StepStatus;
import 'package:xsoulspace_agentic_harness/src/decisions/actor_topology.dart';
import 'package:xsoulspace_agentic_harness/src/narrative/narrative.dart'
    show Step, StepLifecycle, StepVerificationKind;
import 'package:xsoulspace_agentic_harness/src/resources/resources.dart'
    show ToolRegistryResource;
import 'package:xsoulspace_agentic_harness/src/tooling/consent_scoping.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/mechanical_actor.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ToolRegistry;

import 'support/agent_harness_support.dart';

DateTime _t(String iso) => DateTime.parse(iso);


World _world() => World()..addPlugin(AgentPlugin());

ActorTopologySpec _mechSpec() => const ActorTopologySpec(
  worlds: ['main'],
  actors: [
    TopologyActorSpec(
      id: 'model-a',
      role: 'model',
      tier: 'hosted',
      budget: 4000,
      toolRegistry: 'default',
    ),
    TopologyActorSpec(id: 'mech-1', role: 'mechanical', tier: 'mechanical',
        toolRegistry: 'default'),
  ],
);

Entity _stepWithPath(World world, String path) =>
    world.spawnComponents([
      Step(
        claim: 'replace the section',
        verificationKind: StepVerificationKind.mechanical,
      ),
      StepAction('edit_symbol', {
        'action': 'replace_section',
        'path': path,
        'symbolId': 'sec_1',
        'body': 'new body',
      }),
      StepStatus('open'),
    ]);

void main() {
  group('gate 1 — explicit actor plan beats the * fallback', () {
    test("actor A's plan grants A and NOT B on the same path", () {
      final ledger = ConsentLedger(
        clock: () => _t('2026-09-08T12:00:00Z'),
      )
        ..addPlan(
          ConsentPlan(
            planId: 'p-a',
            actor: 'actor-a',
            scopePathGlob: '^pkgs/a/',
            verbs: const {'edit'},
            maxUses: 5,
            grantedAt: _t('2026-09-08T10:00:00Z'),
          ),
        )
        ..addPlan(
          // The `*` workspace fallback covers the SAME path — it must not
          // widen actor A's (absent) grant for actor B either: B has no
          // explicit plan, so B falls through to the fallback; A's grant
          // covers only A.
          ConsentPlan.v1(
            pathGlob: '^pkgs/',
            verbs: const {'edit'},
            maxUses: 5,
            grantedAt: _t('2026-09-08T10:00:00Z'),
          ),
        );

      final a = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(a.allowed, isTrue, reason: '$a');
      expect(a.planId, 'p-a', reason: 'the explicit plan decided');

      // The fallback answers for an actor with NO explicit plan.
      final b = ledger.matches(
        actor: 'actor-b',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(b.allowed, isTrue, reason: '$b');
      expect(b.planId, ConsentPlan.legacyActor);

      // The fallback can never WIDEN an explicit actor's deny: actor A
      // on a path outside its own plan is denied even though `*` covers
      // it (precedence law — the fallback is not consulted).
      final aOut = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/other/y.dart',
      );
      expect(aOut.allowed, isFalse, reason: '$aOut');
      expect(aOut.reason, ConsentReason.scopeMiss);
      expect(aOut.planId, 'p-a');
    });
  });

  group('gate 2 — the legacy v1 workspace plan still answers mechanically', () {
    test('v1 consent.json parse → * fallback → the session actor granted',
        () {
      // The EXACT v1 wire shape the host loads from
      // `<workspace>/.harnessd/consent.json`.
      final ledger = consentLedgerFromDocument({
        'pathGlob': r'notes\.md',
        'verbs': ['write'],
        'maxUses': 3,
      }, clock: () => _t('2026-09-08T12:00:00Z'));

      final actor = sessionConsentActor('/tmp/ws');
      expect(actor, 'harnessd@/tmp/ws');

      final d = ledger.matches(
        actor: actor,
        verb: 'write',
        path: 'notes.md',
      );
      expect(d.allowed, isTrue, reason: '$d');
      expect(d.planId, ConsentPlan.legacyActor);
      // The budget decrements mechanically — 3rd grant exhausts.
      ledger.matches(actor: actor, verb: 'write', path: 'notes.md');
      final third = ledger.matches(
        actor: actor,
        verb: 'write',
        path: 'notes.md',
      );
      expect(third.allowed, isTrue, reason: '$third');
      final fourth = ledger.matches(
        actor: actor,
        verb: 'write',
        path: 'notes.md',
      );
      expect(fourth.allowed, isFalse, reason: '$fourth');
      expect(fourth.reason, ConsentReason.exhausted);
    });

    test('the derivation is stable per workspace, distinct across workspaces',
        () {
      expect(sessionConsentActor('/tmp/ws'), sessionConsentActor('/tmp/ws'));
      expect(
        sessionConsentActor('/tmp/ws'),
        isNot(sessionConsentActor('/tmp/other-ws')),
      );
    });
  });

  group('gate 3 — audit rows are actor-keyed and append-only', () {
    test('every decision lands keyed by actor; rows are never removed', () {
      final ledger = ConsentLedger(clock: () => _t('2026-09-08T12:00:00Z'))
        ..addPlan(
          ConsentPlan(
            planId: 'p-a',
            actor: 'actor-a',
            scopePathGlob: '^pkgs/a/',
            verbs: const {'edit'},
            maxUses: 2,
            grantedAt: _t('2026-09-08T10:00:00Z'),
          ),
        );

      ledger.matches(actor: 'actor-a', verb: 'edit', path: 'pkgs/a/x.dart');
      ledger.matches(actor: 'actor-a', verb: 'edit', path: 'pkgs/b/y.dart');
      ledger.matches(actor: 'actor-b', verb: 'edit', path: 'pkgs/a/x.dart');
      // An out-of-band human answer lands in the SAME log.
      ledger.auditAppend(
        ConsentAuditEntry(
          actor: 'actor-a',
          verb: 'write',
          path: 'pkgs/a/z.dart',
          decision: const ConsentDecision.allow('approver'),
          timestamp: _t('2026-09-08T12:01:00Z'),
        ),
      );

      expect(ledger.audit, hasLength(4));
      expect(ledger.auditFor('actor-a'), hasLength(3));
      expect(ledger.auditFor('actor-b'), hasLength(1));
      expect(
        ledger.auditFor('actor-a').every((e) => e.actor == 'actor-a'),
        isTrue,
      );
      expect(ledger.auditFor('actor-b').single.reason, ConsentReason.noPlan);

      // Append-only: rows grow, never shrink or rewrite.
      final before = ledger.audit.toList();
      ledger.auditAppend(
        ConsentAuditEntry(
          actor: 'actor-a',
          verb: 'edit',
          path: 'pkgs/a/w.dart',
          decision: const ConsentDecision.deny(ConsentReason.verbMiss),
          timestamp: _t('2026-09-08T12:02:00Z'),
        ),
      );
      expect(ledger.audit, hasLength(before.length + 1));
      expect(
        ledger.audit.take(before.length).toList(),
        equals(before),
        reason: 'earlier rows are untouched',
      );

      // The structured row carries the actor key + the named reason.
      final row = ledger.audit.last.toJson();
      expect(row['actor'], 'actor-a');
      expect(row['decision'], 'deny');
      expect(row['reason'], 'verbMiss');
    });

    test('resetPlans reconfigures plans, PRESERVING the append-only audit',
        () {
      final ledger = ConsentLedger(clock: () => _t('2026-09-08T12:00:00Z'))
        ..addPlan(
          ConsentPlan.v1(
            pathGlob: '^pkgs/',
            verbs: const {'write'},
            maxUses: 1,
            grantedAt: _t('2026-09-08T10:00:00Z'),
          ),
        );
      final first = ledger.matches(
        actor: sessionConsentActor('/tmp/ws'),
        verb: 'write',
        path: 'pkgs/x.dart',
      );
      expect(first.allowed, isTrue);

      ledger.resetPlans([
        ConsentPlan.v1(
          pathGlob: '^pkgs/',
          verbs: const {'write'},
          maxUses: 1,
          grantedAt: _t('2026-09-08T11:00:00Z'),
        ),
      ]);
      // Audit preserved; counters fresh.
      expect(ledger.audit, hasLength(1));
      expect(ledger.remainingUses(ConsentPlan.legacyActor), 1);
      expect(ledger.matches(
        actor: sessionConsentActor('/tmp/ws'),
        verb: 'write',
        path: 'pkgs/x.dart',
      ).allowed, isTrue);
      expect(ledger.audit, hasLength(2));
    });
  });

  group('gate 4 — mechanical-actor consent via the ledger', () {
    test('a step inside the grant executes', () async {
      final ledger = ConsentLedger(clock: () => _t('2026-09-08T12:00:00Z'))
        ..addPlan(
          ConsentPlan(
            planId: 'p-mech',
            actor: 'mech-1',
            scopePathGlob: '^docs/',
            verbs: const {'edit'},
            maxUses: 5,
            grantedAt: _t('2026-09-08T10:00:00Z'),
          ),
        );
      final world = _world()
        ..upsertResource(
          ToolRegistryResource()..register('default', ToolRegistry()),
        );
      final mech = registerActorTopology(world, _mechSpec())[1];
      final step = _stepWithPath(world, 'docs/README.md');
      world.flush();
      expect(claimStep(world, step, mech), isA<StepClaimed>());

      final out = await workClaimedReadyStep(
        world: world,
        stepEntity: step,
        actorEntity: mech,
        editExecutor: (args) => Future.value({
          'ok': true,
          'files': [args['path'] as String],
        }),
        // THE INTEGRATION: the callback IS the ledger (topology actor id
        // as the consent actor).
        consent: consentFromLedger(ledger: ledger, actor: 'mech-1'),
      );
      expect(out['ok'], isTrue, reason: '$out');
      final (facade, _) = world.getEntity(step);
      expect(facade.get<Step>()!.status, StepLifecycle.verified);
      // The grant decremented the plan's budget; the answer is audited.
      expect(ledger.remainingUses('p-mech'), 4);
      expect(ledger.auditFor('mech-1'), hasLength(1));
      expect(ledger.auditFor('mech-1').single.decision.allowed, isTrue);
      expectIdle(world);
    });

    test('an unconsented step (outside the grant / no plan) is DENIED and '
        'stays open', () async {
      final ledger = ConsentLedger(clock: () => _t('2026-09-08T12:00:00Z'))
        ..addPlan(
          ConsentPlan(
            planId: 'p-mech',
            actor: 'mech-1',
            scopePathGlob: '^docs/',
            verbs: const {'edit'},
            maxUses: 5,
            grantedAt: _t('2026-09-08T10:00:00Z'),
          ),
        );
      final world = _world()
        ..upsertResource(
          ToolRegistryResource()..register('default', ToolRegistry()),
        );
      final mech = registerActorTopology(world, _mechSpec())[1];
      final step = _stepWithPath(world, 'lib/src/secret.dart');
      world.flush();
      expect(claimStep(world, step, mech), isA<StepClaimed>());

      var executed = false;
      final out = await workClaimedReadyStep(
        world: world,
        stepEntity: step,
        actorEntity: mech,
        editExecutor: (args) {
          executed = true;
          return Future.value({'ok': true});
        },
        consent: consentFromLedger(ledger: ledger, actor: 'mech-1'),
      );
      expect(out['ok'], isFalse, reason: '$out');
      expect(out['code'], 'mechanical_actor_unconsented');
      expect(executed, isFalse, reason: 'deny-by-default: nothing ran');
      // Nothing executed → the step is NOT forged into `failed`; it stays
      // open and claimed (one step, one execution).
      final (facade, _) = world.getEntity(step);
      expect(facade.get<Step>()!.status, StepLifecycle.open);
      expect(facade.get<StepAction>()!.outcome, isNull);
      // The deny is audited, keyed by the actor, and consumed nothing.
      expect(ledger.remainingUses('p-mech'), 5);
      expect(ledger.auditFor('mech-1'), hasLength(1));
      expect(ledger.auditFor('mech-1').single.reason, ConsentReason.scopeMiss);
      expectIdle(world);
    });

    test('args without a usable path are DENIED (deny-by-default is '
        'structural)', () {
      final ledger = ConsentLedger(clock: () => _t('2026-09-08T12:00:00Z'));
      final consent = consentFromLedger(ledger: ledger, actor: 'mech-1');
      expect(consent({'action': 'replace_section'}), isFalse);
      expect(consent({'path': ''}), isFalse);
      expect(ledger.audit, isEmpty, reason: 'no path → no ledger query');
    });
  });
}
