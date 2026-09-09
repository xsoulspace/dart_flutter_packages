// ignore_for_file: lines_longer_than_80_chars

/// Actor-scoped consent plans — build order item 4, prerequisite for ALL
/// multi-actor work.
///
/// Consent was WORKSPACE-scoped (R9.1: `.harnessd/consent.json` with
/// `{pathGlob, verbs, maxUses}` — see the host's `ConsentPlan`, which this
/// model is wire-compatible with). When workers share a world, one actor's
/// consent plan cannot blanket-cover others. This library is the v2 PURE
/// model: plan data + parser + evaluator + audit ledger, wired to nothing.
///
/// ## The law (docs/agent/consent_scoping.md)
///
/// Consent is a WRITING property and stays orthogonal to tier profiles,
/// which are READING properties: a plan never widens what an actor can
/// READ, and a tier profile never grants a WRITE. Evaluation is
/// deny-by-default with NAMED reasons — never a silent refusal, never a
/// silent fallback. Malformed input raises [ConsentPlanError] with a
/// stable `code` (the EnvConfig error convention: named, never silent).
///
/// Everything here is LLM-free and injectable-clock testable: the plan's
/// [ConsentPlan.evaluate] is a pure function of (actor, verb, path,
/// remainingUses, now); the [ConsentLedger] is the only stateful shell
/// (use counters + the append-only audit log).
///
/// Spec: [consent_scoping.md](../../../../docs/agent/consent_scoping.md).
library;

/// Why ONE consent evaluation returned what it returned. Deny-by-default:
/// every non-grant is a NAMED reason.
enum ConsentReason {
  /// No plan at all covers the queried actor (not even the `*` fallback).
  noPlan,

  /// A plan exists but belongs to another actor — one actor's grant never
  /// covers another. Surfaced by the pure per-plan evaluator
  /// ([ConsentPlan.evaluate]); the ledger routes so actors never see
  /// other actors' plans in the first place.
  wrongActor,

  /// The path does not match the plan's `scopePathGlob`.
  scopeMiss,

  /// The verb is not in the plan's `verbs` set.
  verbMiss,

  /// The plan's use budget is spent (`maxUses` reached).
  exhausted,

  /// The plan's `ttl` has lapsed against the supplied clock.
  expired,

  /// The plan granted the move. The ONLY allow reason.
  granted,
}

/// The verdict of ONE consent evaluation: allow|deny + the named reason
/// + the plan that decided (null when no plan applied).
class ConsentDecision {
  const ConsentDecision.allow(this.planId)
    : allowed = true,
      reason = ConsentReason.granted;

  const ConsentDecision.deny(this.reason, {this.planId})
    : allowed = false;

  /// Whether the move is allowed. False is the default universe.
  final bool allowed;

  /// The named reason — never silent.
  final ConsentReason reason;

  /// The plan that decided, when one existed.
  final String? planId;

  @override
  String toString() =>
      'ConsentDecision(${allowed ? 'allow' : 'deny'}, '
      '${reason.name}, plan: ${planId ?? 'none'})';
}

/// One audited consent outcome. The audit log is keyed by [actor],
/// append-only: each actor only ever sees its own rows.
class ConsentAuditEntry {
  const ConsentAuditEntry({
    required this.actor,
    required this.verb,
    required this.path,
    required this.decision,
    required this.timestamp,
  });

  /// The actor that was evaluated — the audit key.
  final String actor;

  final String verb;
  final String path;

  /// The full verdict (allow|deny + named reason + plan id).
  final ConsentDecision decision;

  /// When the decision was recorded (the ledger's injected clock).
  final DateTime timestamp;

  /// The named deny/allow reason.
  ConsentReason get reason => decision.reason;

  /// The deciding plan id, when one existed.
  String? get planId => decision.planId;

  @override
  String toString() =>
      'ConsentAuditEntry($actor, $verb, $path, ${decision.reason.name})';
}

/// A named consent error — malformed schema, unknown plan id, duplicate
/// registration. NEVER a silent fallback: parse failures carry a stable
/// machine-readable [code] and a human-readable message (the EnvConfig
/// error convention).
class ConsentPlanError implements Exception {
  const ConsentPlanError(this.code, this.message);

  /// Stable machine-readable code, e.g. `missing_planId`, `missing_actor`,
  /// `missing_scopePathGlob`, `missing_scope`, `bad_verbs`, `bad_max_uses`,
  /// `bad_ttl`, `bad_granted_at`, `bad_scope_regex`, `not_an_object`,
  /// `bad_plans`, `duplicate_plan_id`.
  final String code;

  final String message;

  @override
  String toString() => 'ConsentPlanError($code): $message';
}

/// ConsentPlan v2 — ONE bounded grant, scoped to ONE actor.
///
/// Fields (all data, no behavior beyond the pure evaluator):
///
/// - `planId` — unique within a ledger.
/// - `actor` — the grant's owner. `*` is the documented workspace fallback
///   (legacy v1 plans parse to `*`); an explicit actor plan ALWAYS takes
///   precedence over `*` for that actor, and the fallback can never widen
///   an explicit actor's deny.
/// - `scopePathGlob` — a REGULAR EXPRESSION over workspace-relative paths
///   (the name `pathGlob` is kept from v1 for wire compatibility; the
///   value is regex syntax, matched with `hasMatch` — v1 semantics).
/// - `verbs` — the covered verbs: `write` (whole-file via write_review),
///   `edit` (span-edit moves), `pack_write` (trusted-author tier).
/// - `maxUses` — hard cap; a plan is NOT an unbounded grant (monotonic
///   budgets, ADR 0009).
/// - `ttl` — optional time-to-live from [grantedAt]; null = no expiry.
/// - `grantedAt` — when the grant was made; ttl is enforced against this
///   plus the SUPPLIED clock (injectable for tests).
class ConsentPlan {
  const ConsentPlan({
    required this.planId,
    required this.actor,
    required this.scopePathGlob,
    required this.grantedAt,
    this.verbs = defaultVerbs,
    this.maxUses = defaultMaxUses,
    this.ttl,
  });

  /// Builds a v1-style (workspace fallback) plan: actor `*`, no ttl.
  /// The plan id defaults to the legacy actor `*` — the workspace tier is
  /// ONE shared plan, so the use counter keys on `*` too. `grantedAt`
  /// defaults to [now] (supply a fixed clock value in tests).
  factory ConsentPlan.v1({
    required String pathGlob,
    Set<String> verbs = defaultVerbs,
    int maxUses = defaultMaxUses,
    DateTime? grantedAt,
    String planId = legacyActor,
    DateTime Function()? now,
  }) =>
      ConsentPlan(
        planId: planId,
        actor: legacyActor,
        scopePathGlob: pathGlob,
        verbs: verbs,
        maxUses: maxUses,
        grantedAt: grantedAt ?? (now ?? DateTime.now)(),
      );

  /// Parses v2 — and, BACKWARD-COMPATIBLY, v1.
  ///
  /// v2 shape: `{planId, actor, scopePathGlob, verbs, maxUses, ttlSeconds,
  /// grantedAt}` — `planId`/`actor`/`scopePathGlob`/`grantedAt` required,
  /// `verbs`/`maxUses` optional (v1 defaults), `ttlSeconds` optional.
  ///
  /// v1 shape: `{pathGlob, verbs, maxUses}` with NO actor field — parsed
  /// as the documented LEGACY workspace fallback: actor `*`, no ttl,
  /// `grantedAt` = [legacyGrantedAt] (or the wall clock when null). The
  /// fallback is DOCUMENTED, never silent: any v2 key present but
  /// incomplete, or a wrongly-typed value, raises [ConsentPlanError].
  factory ConsentPlan.fromJson(
    Object? json, {
    DateTime? legacyGrantedAt,
    String legacyPlanId = legacyActor,
  }) {
    if (json is! Map) {
      throw const ConsentPlanError(
        'not_an_object',
        'consent plan must be a JSON object',
      );
    }
    const v2Keys = ['planId', 'actor', 'scopePathGlob', 'grantedAt'];
    final isV2 = v2Keys.any(json.containsKey);
    if (!isV2) return ConsentPlan._parseV1(json, legacyGrantedAt, legacyPlanId);

    final planId = _requireString(json, 'planId');
    final actor = _requireString(json, 'actor');
    final scope = _requireString(json, 'scopePathGlob');
    final verbs = _parseVerbs(json);
    final maxUses = _parseMaxUses(json);
    final ttl = _parseTtl(json);
    final grantedRaw = json['grantedAt'];
    if (grantedRaw is! String || grantedRaw.isEmpty) {
      throw const ConsentPlanError(
        'bad_granted_at',
        '"grantedAt" must be a non-empty ISO-8601 string',
      );
    }
    final DateTime grantedAt;
    try {
      grantedAt = DateTime.parse(grantedRaw);
    } on FormatException {
      throw ConsentPlanError(
        'bad_granted_at',
        '"grantedAt" is not ISO-8601: "$grantedRaw"',
      );
    }
    return ConsentPlan(
      planId: planId,
      actor: actor,
      scopePathGlob: scope,
      verbs: verbs,
      maxUses: maxUses,
      ttl: ttl,
      grantedAt: grantedAt,
    );
  }

  factory ConsentPlan._parseV1(
    Map<Object?, Object?> json,
    DateTime? legacyGrantedAt,
    String legacyPlanId,
  ) {
    final glob = json['pathGlob'];
    if (glob is! String || glob.isEmpty) {
      throw const ConsentPlanError(
        'missing_scope',
        'consent plan needs "scopePathGlob" (v2) or "pathGlob" (v1)',
      );
    }
    return ConsentPlan(
      planId: legacyPlanId,
      actor: legacyActor,
      scopePathGlob: glob,
      verbs: _parseVerbs(json),
      maxUses: _parseMaxUses(json),
      grantedAt: legacyGrantedAt ?? DateTime.now(),
    );
  }

  /// The actor value a legacy v1 (workspace-scoped) plan carries.
  static const legacyActor = '*';

  /// v1-inherited defaults (host `ConsentPlan.forWorkspace` semantics).
  static const defaultVerbs = {'write', 'edit'};
  static const defaultMaxUses = 50;

  final String planId;
  final String actor;
  final String scopePathGlob;
  final Set<String> verbs;
  final int maxUses;

  /// Null = the grant never expires (v1 legacy semantics).
  final Duration? ttl;
  final DateTime grantedAt;

  /// PURE per-plan evaluation — no mutation, no clock access, no I/O.
  ///
  /// [remainingUses] and [now] are SUPPLIED (the ledger owns the use
  /// counter and the clock), so this is a pure function:
  ///
  /// 1. wrong actor (`actor != this.actor` and `this.actor != '*'`) →
  ///    [ConsentReason.wrongActor] — one actor's grant never covers
  ///    another;
  /// 2. path misses [scopePathGlob] → [ConsentReason.scopeMiss];
  /// 3. verb not in [verbs] → [ConsentReason.verbMiss];
  /// 4. [remainingUses] <= 0 → [ConsentReason.exhausted];
  /// 5. [ttl] set and [now] past [grantedAt]+[ttl] →
  ///    [ConsentReason.expired];
  /// 6. otherwise → allow ([ConsentReason.granted]).
  ///
  /// Deny-by-default: anything not explicitly granted is a named deny.
  ConsentDecision evaluate({
    required String actor,
    required String verb,
    required String path,
    required int remainingUses,
    required DateTime now,
  }) {
    if (this.actor != actor && this.actor != legacyActor) {
      return ConsentDecision.deny(
        ConsentReason.wrongActor,
        planId: planId,
      );
    }
    if (!RegExp(scopePathGlob).hasMatch(path)) {
      return ConsentDecision.deny(ConsentReason.scopeMiss, planId: planId);
    }
    if (!verbs.contains(verb)) {
      return ConsentDecision.deny(ConsentReason.verbMiss, planId: planId);
    }
    if (remainingUses <= 0) {
      return ConsentDecision.deny(ConsentReason.exhausted, planId: planId);
    }
    final ttl = this.ttl;
    if (ttl != null && now.isAfter(grantedAt.add(ttl))) {
      return ConsentDecision.deny(ConsentReason.expired, planId: planId);
    }
    return ConsentDecision.allow(planId);
  }

  Map<String, Object?> toJson() => {
    'planId': planId,
    'actor': actor,
    'scopePathGlob': scopePathGlob,
    'verbs': verbs.toList()..sort(),
    'maxUses': maxUses,
    if (ttl != null) 'ttlSeconds': ttl!.inSeconds,
    'grantedAt': grantedAt.toUtc().toIso8601String(),
  };

  static String _requireString(Map<Object?, Object?> json, String key) {
    final v = json[key];
    if (v is! String || v.isEmpty) {
      throw ConsentPlanError(
        'missing_$key',
        '"$key" must be a non-empty string',
      );
    }
    return v;
  }

  static Set<String> _parseVerbs(Map<Object?, Object?> json) {
    final raw = json['verbs'];
    if (raw == null) return {...defaultVerbs};
    if (raw is! List || raw.isEmpty) {
      throw const ConsentPlanError(
        'bad_verbs',
        '"verbs" must be a non-empty array of strings',
      );
    }
    if (raw.any((v) => v is! String || v.isEmpty)) {
      throw const ConsentPlanError(
        'bad_verbs',
        '"verbs" must contain only non-empty strings',
      );
    }
    return {for (final v in raw) v as String};
  }

  static int _parseMaxUses(Map<Object?, Object?> json) {
    final raw = json['maxUses'];
    if (raw == null) return defaultMaxUses;
    if (raw is! int || raw < 0) {
      throw const ConsentPlanError(
        'bad_max_uses',
        '"maxUses" must be a non-negative integer',
      );
    }
    return raw;
  }

  static Duration? _parseTtl(Map<Object?, Object?> json) {
    final raw = json['ttlSeconds'];
    if (raw == null) return null;
    if (raw is! int || raw <= 0) {
      throw const ConsentPlanError(
        'bad_ttl',
        '"ttlSeconds" must be a positive integer',
      );
    }
    return Duration(seconds: raw);
  }

  @override
  String toString() =>
      'ConsentPlan($planId, actor: $actor, uses: $maxUses'
      '${ttl == null ? '' : ', ttl: ${ttl!.inSeconds}s'})';
}

/// Parses a CONSENT DOCUMENT — the shape the backend will load from
/// `<workspace>/.harnessd/consent.json` once lanes merge:
///
/// - a single plan object (v1 or v2) → one plan;
/// - `{"plans": [ ... ]}` → the multi-plan v2 document (workspace `*`
///   fallback + per-actor plans side by side);
/// - anything else → [ConsentPlanError] with a named code, never a
///   silent fallback.
List<ConsentPlan> parseConsentPlanDocument(
  Object? json, {
  DateTime? legacyGrantedAt,
}) {
  if (json is! Map) {
    throw const ConsentPlanError(
      'not_an_object',
      'consent document must be a JSON object',
    );
  }
  final plans = json['plans'];
  if (plans == null) {
    return [
      ConsentPlan.fromJson(json, legacyGrantedAt: legacyGrantedAt),
    ];
  }
  if (plans is! List) {
    throw const ConsentPlanError(
      'bad_plans',
      '"plans" must be an array of plan objects',
    );
  }
  return [
    for (var i = 0; i < plans.length; i++)
      ConsentPlan.fromJson(
        plans[i],
        legacyGrantedAt: legacyGrantedAt,
        legacyPlanId: 'legacy-${i + 1}',
      ),
  ];
}

/// The stateful shell around the pure model: holds registered plans,
/// per-plan use counters and the append-only, actor-keyed audit log.
///
/// Integration hooks (see consent_scoping.md): the backend calls
/// [matches] where it currently consults the workspace plan, and
/// [auditAppend] for decisions taken outside [matches] (e.g. a human
/// approver's answer) so every consent outcome lands in ONE log.
class ConsentLedger {
  ConsentLedger({ConsentClock? clock})
    : clock = clock ?? DateTime.now,
      _remainingUses = {},
      _plans = [],
      _audit = [];

  /// Injectable clock — tests pass a fixed closure.
  final ConsentClock clock;

  final List<ConsentPlan> _plans;
  final Map<String, int> _remainingUses;
  final List<ConsentAuditEntry> _audit;

  /// Registered plans in registration order. Read-only view.
  List<ConsentPlan> get plans => List.unmodifiable(_plans);

  /// The append-only audit log, keyed by actor. Read-only view.
  List<ConsentAuditEntry> get audit => List.unmodifiable(_audit);

  /// This actor's audit rows only — each actor sees its own grants.
  List<ConsentAuditEntry> auditFor(String actor) =>
      List.unmodifiable(_audit.where((e) => e.actor == actor));

  /// Registers [plan]. A malformed glob raises `bad_scope_regex`; a
  /// duplicate [ConsentPlan.planId] raises `duplicate_plan_id` — named
  /// errors, never silent overwrites.
  void addPlan(ConsentPlan plan) {
    try {
      RegExp(plan.scopePathGlob);
    } on FormatException catch (e) {
      throw ConsentPlanError(
        'bad_scope_regex',
        '"scopePathGlob" is not a valid regex: ${e.message}',
      );
    }
    if (_plans.any((p) => p.planId == plan.planId)) {
      throw ConsentPlanError(
        'duplicate_plan_id',
        'plan "${plan.planId}" is already registered',
      );
    }
    _plans.add(plan);
    _remainingUses[plan.planId] = plan.maxUses;
  }

  /// The uses left on [planId] (0 for an unknown id — deny-by-default).
  int remainingUses(String planId) => _remainingUses[planId] ?? 0;

  /// Evaluates (actor, verb, path) against the registered plans.
  ///
  /// PRECEDENCE (the law): explicit actor plans are consulted first, in
  /// registration order; the first GRANT wins. If the actor has explicit
  /// plans and none grants, the deny stands and the `*` fallback is NOT
  /// consulted — the fallback can never WIDEN an explicit actor's grant.
  /// Only an actor with no explicit plan falls through to the `*`
  /// workspace tier (legacy v1 semantics).
  ///
  /// On a grant the plan's use counter DECREMENTS; on a deny nothing is
  /// consumed. The decision is appended to [audit] — one call = one
  /// audited outcome, keyed by [actor].
  ConsentDecision matches({
    required String actor,
    required String verb,
    required String path,
  }) {
    final now = clock();
    final own = _plans.where((p) => p.actor == actor).toList();
    final fallback = _plans
        .where((p) => p.actor == ConsentPlan.legacyActor)
        .toList();
    final candidates = own.isNotEmpty ? own : fallback;
    if (candidates.isEmpty) {
      return _record(
        ConsentAuditEntry(
          actor: actor,
          verb: verb,
          path: path,
          decision: const ConsentDecision.deny(ConsentReason.noPlan),
          timestamp: now,
        ),
      );
    }
    ConsentDecision? firstDeny;
    for (final plan in candidates) {
      final decision = plan.evaluate(
        actor: actor,
        verb: verb,
        path: path,
        remainingUses: _remainingUses[plan.planId] ?? 0,
        now: now,
      );
      if (decision.allowed) {
        _remainingUses[plan.planId] =
            (_remainingUses[plan.planId] ?? 0) - 1;
        return _record(
          ConsentAuditEntry(
            actor: actor,
            verb: verb,
            path: path,
            decision: decision,
            timestamp: now,
          ),
        );
      }
      firstDeny ??= decision;
    }
    return _record(
      ConsentAuditEntry(
        actor: actor,
        verb: verb,
        path: path,
        decision: firstDeny!,
        timestamp: now,
      ),
    );
  }

  /// Appends an OUT-OF-BAND consent outcome to the audit log (e.g. a
  /// human approver's allow/deny that never went through [matches]).
  /// Append-only: entries are never rewritten or removed.
  void auditAppend(ConsentAuditEntry entry) => _record(entry);

  ConsentDecision _record(ConsentAuditEntry entry) {
    _audit.add(entry);
    return entry.decision;
  }
}

/// Injectable clock: returns the current evaluation time.
typedef ConsentClock = DateTime Function();
