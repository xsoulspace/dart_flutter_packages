// ignore_for_file: lines_longer_than_80_chars

/// Actor-scoped consent plans — the LLM-free gate (build order item 4).
///
/// Claims under test:
/// 1. Deny-by-default: no plan → `noPlan`; wrong path → `scopeMiss`;
///    wrong verb → `verbMiss` — every non-grant is NAMED.
/// 2. One actor's grant never covers another (`wrongActor` at the plan
///    tier; routed away at the ledger tier).
/// 3. `maxUses` decrements on grant and denies with `exhausted` at 0.
/// 4. `ttl` is enforced against an INJECTED clock → `expired`.
/// 5. v1 backward-compat parse: `{pathGlob, verbs, maxUses}` → actor `*`
///    workspace fallback; malformed values raise NAMED errors (never a
///    silent fallback).
/// 6. Precedence: an explicit actor plan answers before `*`, and `*`
///    cannot widen an explicit actor's deny.
/// 7. Audit entries are append-only and keyed by actor — each actor sees
///    only its own rows.
/// 8. The pure evaluator is PURE: same inputs → same decision, no state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/consent_scoping.dart';

DateTime _t(String iso) => DateTime.parse(iso);

ConsentLedger _ledger(DateTime Function()? clock) =>
    ConsentLedger(clock: clock ?? (() => _t('2026-09-08T12:00:00Z')));

ConsentPlan _actorPlan({
  String planId = 'p-a',
  String actor = 'actor-a',
  String scope = '^pkgs/a/',
  Set<String> verbs = const {'edit'},
  int maxUses = 2,
  Duration? ttl,
}) => ConsentPlan(
  planId: planId,
  actor: actor,
  scopePathGlob: scope,
  verbs: verbs,
  maxUses: maxUses,
  ttl: ttl,
  grantedAt: _t('2026-09-08T10:00:00Z'),
);

void main() {
  group('deny-by-default (named reasons)', () {
    test('no plan at all → noPlan', () {
      final ledger = _ledger(null);
      final d = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(d.allowed, isFalse);
      expect(d.reason, ConsentReason.noPlan);
      expect(d.planId, isNull);
    });

    test('path outside the scope → scopeMiss', () {
      final ledger = _ledger(null)..addPlan(_actorPlan());
      final d = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/b/x.dart',
      );
      expect(d.allowed, isFalse);
      expect(d.reason, ConsentReason.scopeMiss);
      expect(d.planId, 'p-a');
    });

    test('verb outside the plan → verbMiss (no use consumed)', () {
      final ledger = _ledger(null)..addPlan(_actorPlan());
      final d = ledger.matches(
        actor: 'actor-a',
        verb: 'write',
        path: 'pkgs/a/x.dart',
      );
      expect(d.reason, ConsentReason.verbMiss);
      expect(ledger.remainingUses('p-a'), 2);
    });
  });

  group('actor scoping', () {
    test("actor A's grant does NOT cover actor B", () {
      final plan = _actorPlan();
      final decision = plan.evaluate(
        actor: 'actor-b',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
        remainingUses: 5,
        now: _t('2026-09-08T11:00:00Z'),
      );
      expect(decision.allowed, isFalse);
      expect(decision.reason, ConsentReason.wrongActor);
    });

    test('ledger routing: B never draws on A\u2019s plan; audit is keyed', () {
      final ledger = _ledger(null)
        ..addPlan(_actorPlan(maxUses: 3));
      final a = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(a.allowed, isTrue);
      final b = ledger.matches(
        actor: 'actor-b',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(b.allowed, isFalse);
      expect(b.reason, ConsentReason.noPlan);
      // A's budget untouched by B's failed query.
      expect(ledger.remainingUses('p-a'), 2);
      // Each actor sees only its own audit rows.
      expect(ledger.auditFor('actor-a'), hasLength(1));
      expect(ledger.auditFor('actor-a').single.decision.allowed, isTrue);
      expect(ledger.auditFor('actor-b'), hasLength(1));
      expect(ledger.auditFor('actor-b').single.reason, ConsentReason.noPlan);
    });
  });

  group('budgets (monotonic, ADR 0009)', () {
    test('maxUses decrements on grant; exhaustion denies named', () {
      final ledger = _ledger(null)..addPlan(_actorPlan());
      for (var i = 0; i < 2; i++) {
        final d = ledger.matches(
          actor: 'actor-a',
          verb: 'edit',
          path: 'pkgs/a/x.dart',
        );
        expect(d.allowed, isTrue, reason: 'grant #$i');
      }
      final spent = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(spent.allowed, isFalse);
      expect(spent.reason, ConsentReason.exhausted);
      expect(ledger.remainingUses('p-a'), 0);
    });
  });

  group('ttl (injectable clock)', () {
    test('live within ttl, expired past it; deny consumes nothing', () {
      DateTime now = _t('2026-09-08T10:30:00Z'); // grantedAt + 30 min
      final ledger = ConsentLedger(clock: () => now)
        ..addPlan(_actorPlan(ttl: const Duration(hours: 1)));
      final live = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(live.allowed, isTrue);
      now = _t('2026-09-08T11:00:01Z'); // one second past grantedAt + ttl
      final late = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(late.allowed, isFalse);
      expect(late.reason, ConsentReason.expired);
      expect(ledger.remainingUses('p-a'), 1); // expired ≠ consumed
    });
  });

  group('parsing (v2 + v1 backward compat, named errors)', () {
    test('v2 round-trip', () {
      final plan = _actorPlan(ttl: const Duration(hours: 2));
      final back = ConsentPlan.fromJson(plan.toJson());
      expect(back.planId, plan.planId);
      expect(back.actor, plan.actor);
      expect(back.scopePathGlob, plan.scopePathGlob);
      expect(back.verbs, plan.verbs);
      expect(back.maxUses, plan.maxUses);
      expect(back.ttl, plan.ttl);
      expect(back.grantedAt, plan.grantedAt);
    });

    test('v1 shape parses as the documented * workspace fallback', () {
      final plan = ConsentPlan.fromJson({
        'pathGlob': '^(pkgs|docs)/',
        'verbs': ['write', 'edit'],
        'maxUses': 50,
      }, legacyGrantedAt: _t('2026-09-08T09:00:00Z'));
      expect(plan.actor, ConsentPlan.legacyActor);
      expect(plan.scopePathGlob, '^(pkgs|docs)/');
      expect(plan.verbs, {'write', 'edit'});
      expect(plan.maxUses, 50);
      expect(plan.ttl, isNull);
      expect(plan.grantedAt, _t('2026-09-08T09:00:00Z'));
    });

    test('v1 defaults apply for omitted verbs/maxUses', () {
      final plan = ConsentPlan.fromJson({
        'pathGlob': '^pkgs/',
      }, legacyGrantedAt: _t('2026-09-08T09:00:00Z'));
      expect(plan.verbs, ConsentPlan.defaultVerbs);
      expect(plan.maxUses, ConsentPlan.defaultMaxUses);
    });

    test('malformed values raise NAMED errors, never silent fallbacks', () {
      final cases = <String, Object?>{
        'not_an_object': 'nope',
        'missing_scope': <String, Object?>{'verbs': ['write']},
        'missing_planId': <String, Object?>{
          'actor': 'a',
          'scopePathGlob': '^pkgs/',
          'grantedAt': '2026-09-08T10:00:00Z',
        },
        'missing_actor': <String, Object?>{
          'planId': 'p',
          'scopePathGlob': '^pkgs/',
          'grantedAt': '2026-09-08T10:00:00Z',
        },
        'bad_granted_at': <String, Object?>{
          'planId': 'p',
          'actor': 'a',
          'scopePathGlob': '^pkgs/',
          'grantedAt': 'yesterday',
        },
        'bad_verbs': <String, Object?>{
          'planId': 'p',
          'actor': 'a',
          'scopePathGlob': '^pkgs/',
          'grantedAt': '2026-09-08T10:00:00Z',
          'verbs': 'edit',
        },
        'bad_max_uses': <String, Object?>{
          'planId': 'p',
          'actor': 'a',
          'scopePathGlob': '^pkgs/',
          'grantedAt': '2026-09-08T10:00:00Z',
          'maxUses': -1,
        },
        'bad_ttl': <String, Object?>{
          'planId': 'p',
          'actor': 'a',
          'scopePathGlob': '^pkgs/',
          'grantedAt': '2026-09-08T10:00:00Z',
          'ttlSeconds': 0,
        },
      };
      cases.forEach((code, json) {
        expect(
          () => ConsentPlan.fromJson(json),
          throwsA(
            isA<ConsentPlanError>().having(
              (e) => e.code,
              'code',
              code,
            ),
          ),
          reason: 'expected named error "$code"',
        );
      });
    });

    test('v2 key present but incomplete is an ERROR, not a v1 fallback', () {
      expect(
        () => ConsentPlan.fromJson(<String, Object?>{
          'actor': 'a',
          'pathGlob': '^pkgs/',
        }),
        throwsA(
          isA<ConsentPlanError>().having(
            (e) => e.code,
            'code',
            'missing_planId',
          ),
        ),
      );
    });

    test('document parse: single object and multi-plan {"plans": [...]}', () {
      final one = parseConsentPlanDocument({
        'pathGlob': '^pkgs/',
      }, legacyGrantedAt: _t('2026-09-08T09:00:00Z'));
      expect(one, hasLength(1));
      expect(one.single.actor, ConsentPlan.legacyActor);
      final many = parseConsentPlanDocument({
        'plans': [
          _actorPlan().toJson(),
          _actorPlan(planId: 'p-b', actor: 'actor-b').toJson(),
        ],
      });
      expect(many, hasLength(2));
      expect(many.map((p) => p.actor), ['actor-a', 'actor-b']);
      expect(
        () => parseConsentPlanDocument({
          'plans': 'all-of-it',
        }),
        throwsA(
          isA<ConsentPlanError>().having(
            (e) => e.code,
            'code',
            'bad_plans',
          ),
        ),
      );
    });

    test('ledger registration: bad regex + duplicate plan id are named', () {
      expect(
        () => _ledger(null).addPlan(_actorPlan(scope: '^pkgs/[')),
        throwsA(
          isA<ConsentPlanError>().having(
            (e) => e.code,
            'code',
            'bad_scope_regex',
          ),
        ),
      );
      expect(
        () => _ledger(null)
          ..addPlan(_actorPlan())
          ..addPlan(_actorPlan()),
        throwsA(
          isA<ConsentPlanError>().having(
            (e) => e.code,
            'code',
            'duplicate_plan_id',
          ),
        ),
      );
    });
  });

  group('precedence (explicit actor plan over the * fallback)', () {
    test('actor plan answers first; fallback cannot widen its deny', () {
      final ledger = _ledger(null)
        ..addPlan(
          ConsentPlan.v1(
            pathGlob: '^pkgs/a/',
            verbs: const {'write'},
            maxUses: 9,
          ),
        )
        ..addPlan(_actorPlan(maxUses: 1));
      // The * fallback covers 'write' here — but the explicit actor plan
      // only grants 'edit', so 'write' is a NAMED deny, not a fallback
      // allow: the fallback can never WIDEN an explicit actor's grant.
      final widened = ledger.matches(
        actor: 'actor-a',
        verb: 'write',
        path: 'pkgs/a/x.dart',
      );
      expect(widened.allowed, isFalse);
      expect(widened.reason, ConsentReason.verbMiss);
      expect(ledger.remainingUses('*'), 9); // fallback untouched

      // The actor's own verb grants through the ACTOR plan.
      final granted = ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(granted.planId, 'p-a');
    });

    test('unscoped/legacy actors fall through to the * fallback tier', () {
      final ledger = _ledger(null)
        ..addPlan(
          ConsentPlan.v1(
            pathGlob: '^pkgs/a/',
            verbs: const {'edit'},
            maxUses: 1,
          ),
        );
      final d = ledger.matches(
        actor: 'worker-1',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      expect(d.allowed, isTrue);
      expect(d.planId, ConsentPlan.legacyActor);
      expect(ledger.remainingUses(ConsentPlan.legacyActor), 0);
    });
  });

  group('audit log', () {
    test('append-only, keyed by actor, carries decision+reason+plan', () {
      final ledger = _ledger(null)..addPlan(_actorPlan(maxUses: 1));
      ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      ledger.matches(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
      );
      ledger.auditAppend(
        ConsentAuditEntry(
          actor: 'actor-a',
          verb: 'write',
          path: 'pkgs/a/other.dart',
          decision: const ConsentDecision.deny(ConsentReason.verbMiss),
          timestamp: _t('2026-09-08T12:01:00Z'),
        ),
      );
      expect(ledger.audit, hasLength(3));
      final rows = ledger.auditFor('actor-a');
      expect(rows, hasLength(3));
      expect(rows[0].decision.allowed, isTrue);
      expect(rows[0].planId, 'p-a');
      expect(rows[1].reason, ConsentReason.exhausted);
      expect(rows[2].verb, 'write');
      expect(
        rows.every((r) => r.timestamp.isBefore(_t('2026-09-08T12:02:00Z'))),
        isTrue,
      );
      expect(ledger.auditFor('actor-b'), isEmpty);
    });
  });

  group('purity of the evaluator', () {
    test('same inputs → same decision, no state, no clock access', () {
      final plan = _actorPlan(maxUses: 5);
      ConsentDecision eval() => plan.evaluate(
        actor: 'actor-a',
        verb: 'edit',
        path: 'pkgs/a/x.dart',
        remainingUses: 1,
        now: _t('2026-09-08T11:00:00Z'),
      );
      expect(eval().allowed, eval().allowed);
      expect(eval().reason, ConsentReason.granted);
      expect(plan.maxUses, 5); // evaluation never mutates the plan
    });
  });
}
