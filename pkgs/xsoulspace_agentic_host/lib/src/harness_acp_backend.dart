// ignore_for_file: lines_longer_as_80_chars

/// Stage N3/N4 + R7c — the harness as a long-running ACP agent: `harnessd`.
///
/// The daemon is TRANSPORT + HOST POLICY (D5) and lives here (ADR 0025):
/// any composition root — a thin bin in a provider package, an app like
/// last_answer, a pi extension or a test — injects its backends as
/// `HarnessBackendBinding` entries; the core learns no ACP and the host
/// learns no provider.
///
/// Any ACP client (Zed, pi via stdio, last_answer) can address the harness:
/// `session/new` (cwd = the delegated workspace) → `session/prompt` (a free
/// task sentence, D8 workspace-convention oracle) → streaming
/// `session/update`s (generation moves + tool calls) → final verdict chunk.
///
/// R7c (ADR 0023 §2) — the daemon HOLDS THE WORLD:
/// - sessions are keyed PER WORKSPACE (`cwd`): a second `session/new` for
///   the same workspace continues the live world instead of starting over;
/// - the code tree is built ONCE per workspace via `repo_etl` and NEVER
///   snapshotted — a mechanical tick (`refresh`) re-scans mtime-changed
///   files before every prompt (zero model tokens);
/// - snapshots persist beats/verdicts/budgets only (the codec drops the
///   meaning tree — ADR 0023 §2);
/// - `loadSession: true`: a new session for a workspace with an existing
///   snapshot store RESTORES the world from it (P5 machinery) — resume is
///   real, the capability flag no longer lies;
/// - `requestPermission` is DENY-BY-DEFAULT and routes to the write gate /
///   edit approver (never an unconditional allow);
/// - `cancelSession` plumbs into generation cancellation: the session flag
///   aborts the loop and the backend's in-flight generation is cancelled
///   via the binding's cancel hook (no more no-op);
/// - escalation stays bounded: `maxGoalAttempts = 3 + escalationRounds` is
///   hard-capped at 9 (monotonic widening, never unbounded).
///
/// The daemon is TRANSPORT + host policy — the core learns no ACP (D5).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableWire;
import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
// Consent-scoping integration (follow-ups 3+4): the v2 actor-scoped
// consent model. PREFIXED — the host keeps its own legacy `ConsentPlan`
// (the v1 wire shape) unambiguous.
import 'package:xsoulspace_agentic_harness/src/tooling/consent_scoping.dart'
    as consent;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, JailWriteGateway, WriteGateMode, runTool;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_read_program.dart'
    show meaningProgramTool;
import 'package:xsoulspace_agentic_harness/src/tools/meaning_query_tools.dart'
    show meaningSpanReader;
// ADR 0003 — conditional workspace import: on the web target the honest
// stub (agentic_workspace_web_stub.dart) replaces the workspace barrel, so
// its dart:io edit/ETL tier stays OUT of the web graph. VM/macOS: the real
// import, unchanged.
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart'
    if (dart.library.js_interop) 'agentic_workspace_web_stub.dart'
    show
        RepoEtlState,
        SpanEditPlan,
        editSymbolTool,
        meaningSpanReader,
        repoEtlTool,
        writeReviewTool;

import 'coding_agent_runner.dart'
    show
        CodingAgentRunResult,
        CodingAgentTask,
        runCodingAgentOnce,
        taskFromSentence;

// ADR 0027 amendment — MECHANICAL EDITS: the directive classifier (this
// package; minimal local shape checks only — the deep validation stays in
// the workspace materializer, which bounces as structured data).
import 'mechanical_edit_directive.dart';
// Server-side tier enforcement (follow-up 1): the session actor's tier
// declaration (`_meta.sessionTier`) parsed at session/new; the tier's
// read budgets thread into the read world's meaning program.
import 'session_tier.dart';

/// One registered inference backend (ADR 0025): the host learns no
/// provider — the composition root binds a backend NAME to the factory
/// that builds its [ModelRouter] (or null when unavailable, e.g. a
/// missing API key) plus an optional generation-cancel hook.
final class HarnessBackendBinding {
  const HarnessBackendBinding({
    required this.defaultModel,
    required this.buildRouter,
    this.cancelActiveGeneration,
  });

  /// Default model id when the CLI/host does not spell one
  /// (e.g. `deepseek/deepseek-v4-flash-0731` for OpenRouter,
  /// `apple_foundation` for the AFM bridge).
  final String defaultModel;

  /// Builds the router for this backend, or null when the backend is
  /// unavailable (missing credentials, engine unavailable) — the daemon
  /// then refuses prompts with named data instead of hanging.
  final ModelRouter? Function({required String model, String? apiKey})
  buildRouter;

  /// Cancels the backend's in-flight generation (e.g. AFM `xs_fm_cancel`)
  /// when the client cancels the session. Null → loop-flag cancellation
  /// only.
  final void Function()? cancelActiveGeneration;
}

/// ADR 0027 amendment — CONSENT PLAN: one bounded grant covering a class
/// of writes/edits (host-side policy, invisible to the model). Deny-
/// by-default OUTSIDE the plan is untouched; every plan answer is logged.
class ConsentPlan {
  const ConsentPlan({
    required this.pathGlob,
    this.verbs = const {'write', 'edit'},
    this.maxUses = 50,
  });

  /// Glob over workspace-relative paths the plan covers
  /// (e.g. `lib/src/.*` — grant writes within one package's subtree).
  final String pathGlob;

  /// Verbs covered: `write` (whole-file via write_review), `edit`
  /// (span-edit moves) and/or `pack_write` (P1 trusted-author tier — the
  /// pack-write consent for authored-body pack executables; SYNC, the
  /// pack path `.dart_tool/harnessd/edit_pack.json` is what the glob
  /// matches).
  final Set<String> verbs;

  /// Hard cap — a plan is NOT an unbounded grant (monotonic budgets).
  final int maxUses;

  /// Loads the WORKSPACE-LEVEL consent policy from
  /// `<workspace>/.harnessd/consent.json` — the policy lives with the
  /// workspace it scopes, survives daemon restarts, and is honored for
  /// every host consumer (applied automatically at session creation).
  /// Shape: `{"pathGlob": "...", "verbs": ["write", "edit"],
  /// "maxUses": 50}` — `verbs`/`maxUses` optional. Absent or malformed
  /// file → null (deny-by-default unchanged, never a crash).
  static ConsentPlan? forWorkspace(final Directory workspace) {
    final file = File(
      '${workspace.path}${Platform.pathSeparator}.harnessd'
      '${Platform.pathSeparator}consent.json',
    );
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return null;
      final glob = raw['pathGlob'];
      if (glob is! String || glob.isEmpty) return null;
      final verbsRaw = raw['verbs'];
      final verbs = <String>{
        if (verbsRaw is List)
          for (final v in verbsRaw)
            if (v is String) v,
      };
      return ConsentPlan(
        pathGlob: glob,
        verbs: verbs.isEmpty ? const {'write', 'edit'} : verbs,
        maxUses: raw['maxUses'] is int ? raw['maxUses'] as int : 50,
      );
    } on Object {
      return null;
    }
  }
}

/// Hard ceiling for the monotonic escalation widening (R7c): 3 base
/// attempts + up to 6 escalation rounds — never unbounded.
const maxEscalationCeiling = 9;

/// P1 consent UX hardening — the permission-wait DEADLINE as DATA. 45 s:
/// well under the 5-minute ACP permission timeout that produced the Phase
/// 1.5 unbounded stall loop (an unanswered request held the whole tool
/// round for its deadline and the model retried into another 5-minute
/// wait), yet above typical human glance latency for a consent card so a
/// real approver is never raced. It is a LOOP-BREAKER, not a policy
/// change: the deadline resolves THIS wait as DENY (deny-by-default
/// holds); the human can still allow a LATER retry by re-delegating.
/// Tests inject a shorter deadline through
/// [HarnessAcpBackend.permissionDeadline].
const defaultPermissionDeadline = Duration(seconds: 45);

/// The outcome of ONE bounded client permission round-trip: WHICH path
/// answered (F3 attribution: `approver` | `timeout` | `cancel-deny` |
/// `no-approver`) and whether the change is allowed. `failureClass` names
/// the deny for the tool result (`permission_timeout` /
/// `permission_cancelled`); empty for a plain approver answer.
typedef _PermissionAnswer = ({bool allowed, String path, String failureClass});

/// ADR 0027 §1 — is [text] a DIRECTIVE-ONLY read prompt? True iff it
/// carries ≥1 read directive (`[scan]`, `[zoom …]`, structured
/// `harness_meaning_program` payloads) AND no mutation marker
/// (`harness_edit`, `harness_fs_write`, `[verify]`) AND no leftover task
/// prose after stripping the directives (free prose = a delegated task).
bool isReadOnlyDirectivePrompt(String text) {
  if (_hasMutationMarker(text)) return false;
  final hasRead =
      RegExp(r'\[scan\]').hasMatch(text) ||
      RegExp(r'\[zoom [^\]]+\]').hasMatch(text) ||
      text.contains('harness_meaning_program');
  if (!hasRead) return false;
  // Strip every directive form; whatever remains must be empty.
  var stripped = text
      .replaceAll(RegExp(r'\[scan\]'), '')
      .replaceAll(RegExp(r'\[zoom [^\]]+\]'), '');
  stripped = _ScriptedDaemonActor.stripPayloads(
    stripped,
    'harness_meaning_program',
  );
  return stripped.trim().isEmpty;
}

/// `[read-only]` host-declared marker on a free-form delegation (ADR 0027
/// §1: the read/no-read decision is DATA from the delegator, never
/// inferred from laziness).
bool _marksReadOnly(String text) =>
    text.startsWith('[read-only]') || text.contains('[read-only]');

bool isMechanicalRunDirective(String text) {
  if (text.contains('harness_edit') ||
      text.contains('harness_fs_write') ||
      RegExp(r'\[verify\]').hasMatch(text) ||
      RegExp(r'\[edit[\s]').hasMatch(text) ||
      _marksReadOnly(text)) {
    return false;
  }
  final payloads = _ScriptedDaemonActor._payloads(text, 'harness_run');
  if (payloads.items.isEmpty) return false;
  final stripped = _ScriptedDaemonActor.stripPayloads(text, 'harness_run');
  return stripped.trim().isEmpty;
}

bool _hasMutationMarker(String text) =>
    text.contains('harness_edit') ||
    text.contains('harness_fs_write') ||
    RegExp(r'\[verify\]').hasMatch(text) ||
    RegExp(r'\[edit[\s]').hasMatch(text);

/// ADR 0027 amendment (dogfood 2026-09-06) — is [text] a MECHANICAL WRITE
/// directive? True iff it carries ≥1 `harness_fs_write {…}` payload, NO
/// other directive/mutation form, and NO leftover prose. A consented
/// whole-file write is NOT a mover decision: the content is DATA and the
/// human is the approver (the review gate) — routing it through the mover
/// as a graded task measured `mover_refusal` after a 9-minute wall.
/// Mixed prompts (write + prose/edit/verify) NEVER take this path —
/// deny-by-default on ambiguity.
bool isMechanicalWriteDirective(String text) {
  if (text.contains('harness_edit') ||
      RegExp(r'\[verify\]').hasMatch(text) ||
      RegExp(r'\[edit[\s]').hasMatch(text) ||
      _marksReadOnly(text)) {
    return false;
  }
  final payloads = _ScriptedDaemonActor._payloads(text, 'harness_fs_write');
  if (payloads.items.isEmpty) return false;
  final stripped = _ScriptedDaemonActor.stripPayloads(
    text,
    'harness_fs_write',
  );
  return stripped.trim().isEmpty;
}

/// ADR 0027 §3 — the mover REASONING CLASS for a decision (the daemon
/// classifies; the client maps it to model/thinking config):
/// mechanical reads → `none`, structured edits → `low`, everything else
/// (decomposition, planning, repair) → `high`.
String classifyReasoning(String prompt) {
  if (isReadOnlyDirectivePrompt(prompt)) return 'none';
  if (prompt.contains('harness_edit') || prompt.contains('harness_fs_write')) {
    return 'low';
  }
  return 'high';
}

/// The monotonic (hard-capped) attempt allowance for an escalation round:
/// `3 + rounds`, never above [maxEscalationCeiling], never a reset.
int escalationAllowance(int escalationRounds) =>
    min(3 + escalationRounds, maxEscalationCeiling);

class HarnessAcpBackend
    implements AcpAgentBackend, AcpPermissionRequesting, AcpMoveProposing {
  HarnessAcpBackend({
    this.backend = 'open_router',
    this.bindings = const {},
    this.model = 'deepseek/deepseek-v4-flash-0731',
    this.handlerFactory,
    this.meaningProfile = false,
    this.scripted = false,
    this.remoteMover = false,
    this.apiKey,
    this.checkCommand,
    this.permissionDeadline = defaultPermissionDeadline,
  });

  /// Backend name, resolved against [bindings] (e.g. `open_router`,
  /// `apple_foundation_afm`). Unresolvable → scripted / remote-mover /
  /// [handlerFactory] modes only (LLM-free gates and embedded hosts).
  final String backend;

  /// Injected backends (ADR 0025): the composition root registers one
  /// `HarnessBackendBinding` per provider it composes.
  final Map<String, HarnessBackendBinding> bindings;
  final String model;

  /// Explicit OpenRouter API key (embedded hosts — e.g. last_answer —
  /// cannot rely on `OPENROUTER_API_KEY` in the process environment).
  /// Null → the environment variable is read, as before.
  final String? apiKey;

  /// Explicit verification criterion overriding the D8 workspace
  /// convention (the CLI spells it `--check`). The product host (agent
  /// docs) declares it as data on the binding. Null → convention decides.
  final List<String>? checkCommand;

  /// P1 consent UX hardening: how long a client permission round-trip may
  /// stay unanswered before it resolves as DENY (deny-on-timeout). See
  /// [defaultPermissionDeadline] for the default's rationale.
  final Duration permissionDeadline;

  /// R7: when true, delegated tasks run through the MEANING-PROFILE
  /// surface ([repo_etl, meaning_program, edit_symbol, run])
  /// — zero `read`, zero `write`; the tree is the only code interface.
  final bool meaningProfile;

  /// Injectable handler factory (LLM-free tests). Null → the real backend.
  final GenerationHandler Function(ModelRouter router)? handlerFactory;

  /// R7 gate mode: the mover is a SCRIPTED directive interpreter — the
  /// prompt carries bracketed READ directives (`[scan]`,
  /// `[zoom <query>]`, `[verify]`) and STRUCTURED JSON payloads for the
  /// id-bearing verbs (`harness_edit {…}`, `harness_meaning_program {…}`
  /// — the exact registry args, R7 production #1), and the actor emits the
  /// corresponding REAL registry tool calls. The daemon surface
  /// (registry, oracles, auto-revert, budgets) is the production one;
  /// only the mover is deterministic (LLM-free gate discipline).
  final bool scripted;

  /// R7 production #4 — the REMOTE MOVER: the daemon runs the harness
  /// loop but has NO mover model; every decision round-trips to the
  /// CLIENT (pi's model) as `session/propose_move` (bounded cut + tool
  /// schemas out, typed tool calls back). The client never touches files
  /// and never executes anything — the host validates, materializes and
  /// verifies every proposed move. Precedence: [scripted] > [remoteMover]
  /// > [handlerFactory] > the real backend router.
  final bool remoteMover;

  /// N4 — pi-as-escalation-rung: the client's permission requester, attached
  /// by the server (dart_acp_toolkit `AcpPermissionRequesting`).
  Future<AcpPermissionOutcome> Function(AcpPermissionRequest request)?
  _permissionRequester;

  /// R7 production #4: the client's move proposer (attached by the
  /// server; in-process tests attach it directly).
  Future<AcpMoveResponse> Function(AcpMoveProposal proposal)? _moveProposer;

  /// Test visibility: the in-flight propose_move completions of a session
  /// (empty after a cancel — no leaked awaits).
  Map<String, Completer<AcpMoveResponse>> sessionsDebugPendingMoves(
    String sessionId,
  ) => _sessions[sessionId]?.pendingMoves ?? const {};

  /// Test visibility: the GOAL world of a session (mechanical edits land
  /// touched-file beats on its goal actor's thread; the verify-tier
  /// derivation reads the same world). Null when no goal world exists yet.
  World? sessionsDebugWorld(String sessionId) =>
      _sessions[sessionId]?.world;

  /// R7 production #5: called on every session activity (create/prompt/
  /// cancel) — the daemon's idle-exit timer resets here.
  void Function()? onActivity;

  /// ADR 0027 amendment — sets the session's bounded consent plan (host
  /// policy; the model never sees it). Deny-by-default outside the plan.
  ///
  /// Consent-scoping integration: the plan is ALSO registered into the
  /// session's [consent.ConsentLedger] as the legacy workspace fallback
  /// (actor `*`, v1 semantics) — every consent path routes through
  /// `ledger.matches` and every answer lands as an actor-keyed
  /// `ConsentAuditEntry`. Resetting the plan resets the ledger's plan set
  /// (use counters start fresh — the old `consentPlanUses = 0` semantic);
  /// the ledger's audit log is preserved (append-only, never rewritten).
  void setConsentPlan(String sessionId, ConsentPlan? plan) {
    final session = _sessions[sessionId];
    if (session == null) return;
    session
      ..consentPlan = plan
      ..consentPlanUses = 0
      ..consentLedger.resetPlans([
        if (plan != null)
          consent.ConsentPlan.v1(
            pathGlob: plan.pathGlob,
            verbs: plan.verbs,
            maxUses: plan.maxUses,
          ),
      ]);
  }

  /// Consent-scoping integration (follow-up 3) — loads a v1-or-v2 consent
  /// DOCUMENT (`{plan}` or `{"plans": [...]}` — see
  /// `parseConsentPlanDocument`) into the session's ledger. A v2 document
  /// carries the workspace `*` fallback and per-actor plans SIDE BY SIDE;
  /// an explicit plan for this session's actor id
  /// (`consent.sessionConsentActor(cwd)`) always beats the `*` fallback
  /// (the ledger enforces precedence). The document REPLACES the ledger's
  /// plan set — include the workspace fallback in `plans` when both are
  /// wanted. A malformed document raises `ConsentPlanError` with a named
  /// code — never a silent fallback.
  void setSessionConsentDocument(String sessionId, Object? document) {
    final session = _sessions[sessionId];
    if (session == null) return;
    session
      ..consentPlan = null
      ..consentPlanUses = 0
      ..consentLedger.resetPlans(consent.parseConsentPlanDocument(document));
  }

  /// Test visibility: the session's consent ledger (the ONE consent
  /// authority for every daemon consent path). Null when no such session.
  consent.ConsentLedger? sessionsDebugConsentLedger(String sessionId) =>
      _sessions[sessionId]?.consentLedger;

  /// ADR 0027 amendment — the session's consent audit log (every
  /// plan-allowed answer lands here as named data; each line carries the
  /// structured `consent-row {…}` rendering of its `ConsentAuditEntry`).
  List<String> consentAudit(String sessionId) =>
      List.unmodifiable(_sessions[sessionId]?.consentLog ?? const []);

  var _permissionSeq = 0;

  /// P1 consent UX hardening — the ONE bounded client permission
  /// round-trip. Races the client's answer against (a) the permission
  /// deadline (deny-on-timeout, `permission_timeout`) and (b) a session
  /// cancel (deny, `permission_cancelled` — [cancelSession] completes the
  /// pending wait; never a dangling Future, the Phase 1.5 bridge-crash
  /// class). The plan path does NOT go through here: a plan answers
  /// BEFORE the client is asked and logs its own single audit line.
  ///
  /// F3 attribution: every answer is audited WITH ITS PATH (`via approver`
  /// / `via timeout` / `via cancel-deny` / `via no-approver`) — a silent
  /// allow is detectable in the audit. A LATE answer (after the deadline
  /// or after a cancel) is LOGGED and IGNORED: the wait already resolved
  /// DENY, and a permission that outlives its deadline can never
  /// retroactively allow (deny-by-default is monotonic in time) — a later
  /// allow requires a NEW round-trip (the deadline is a loop-breaker, not
  /// a policy change).
  ///
  /// Consent-scoping integration: EVERY answer (approver, timeout,
  /// cancel-deny, no-approver, late-ignored) is recorded OUT-OF-BAND in
  /// the session ledger's append-only audit via `auditAppend` — an
  /// actor-keyed `ConsentAuditEntry` — and the consentLog line carries
  /// the structured `consent-row {…}` rendering ([verb] defaults to
  /// `edit`; [consentPath] is the workspace-relative target when the
  /// call site knows it, else the request title as best attribution).
  Future<_PermissionAnswer> _askClientPermission(
    _Session? session, {
    required String sessionId,
    required AcpPermissionRequest request,
    required String subject,
    String verb = 'edit',
    String? consentPath,
  }) async {
    final auditPath = consentPath ?? request.title;
    final requester = _permissionRequester;
    if (requester == null) {
      // No approver wired: deny is structural (never an unconditional
      // allow) — and audited like every other answer.
      final entry = _auditConsentOutcome(session, verb: verb, path: auditPath);
      session?.consentLog.add(
        '$subject DENIED via no-approver (structural)'
        '${entry == null ? '' : ' | ${_consentRow(entry)}'}',
      );
      return (allowed: false, path: 'no-approver', failureClass: '');
    }
    final pending = Completer<_PermissionAnswer>();
    final key = 'perm_${++_permissionSeq}';
    session?.pendingPermissions[key] = pending;
    // Deadline as DATA: on expiry the wait resolves DENY — the model's
    // tool round is never held for the client's full silence.
    final timer = Timer(permissionDeadline, () {
      if (!pending.isCompleted) {
        pending.complete(
          (
            allowed: false,
            path: 'timeout',
            failureClass: 'permission_timeout',
          ),
        );
      }
    });
    // The client's answer is observed TO THE END: a late answer resolves
    // the LOG only (see the doc comment) — never the resolved wait.
    unawaited(() async {
      AcpPermissionOutcome outcome;
      try {
        outcome = await requester(request);
      } on Object {
        // A throwing requester must never dangle the wait (Phase 1.5).
        if (!pending.isCompleted) {
          pending.complete(
            (
              allowed: false,
              path: 'approver',
              failureClass: 'permission_approver_error',
            ),
          );
        }
        return;
      }
      final allowed = outcome == AcpPermissionOutcome.allow;
      if (pending.isCompleted) {
        final lateEntry = _auditConsentOutcome(
          session,
          verb: verb,
          path: auditPath,
          allowed: allowed,
        );
        session?.consentLog.add(
          '$subject LATE ${allowed ? "APPROVED" : "DENIED"} via approver '
          '(IGNORED — the wait already resolved deny; the deadline is a '
          'loop-breaker, not a policy change)'
          '${lateEntry == null ? '' : ' | ${_consentRow(lateEntry)}'}',
        );
        return;
      }
      pending.complete(
        (allowed: allowed, path: 'approver', failureClass: ''),
      );
    }());
    final answer = await pending.future;
    timer.cancel();
    session?.pendingPermissions.remove(key);
    final entry = _auditConsentOutcome(
      session,
      verb: verb,
      path: auditPath,
      allowed: answer.allowed,
    );
    session?.consentLog.add(
      '$subject ${answer.allowed ? "APPROVED" : "DENIED"} via '
      '${answer.path}'
      '${answer.failureClass.isEmpty ? "" : " (${answer.failureClass})"}'
      '${entry == null ? '' : ' | ${_consentRow(entry)}'}',
    );
    return answer;
  }

  /// Consent-scoping integration: records ONE out-of-band consent
  /// outcome (a human approver's answer / timeout / cancel-deny /
  /// no-approver) in the session ledger's append-only audit — the SAME
  /// log `ConsentLedger.matches` writes, keyed by the session's actor id.
  /// Returns the entry (null without a session) for the consentLog line.
  consent.ConsentAuditEntry? _auditConsentOutcome(
    _Session? session, {
    required String verb,
    required String path,
    bool allowed = false,
  }) {
    if (session == null) return null;
    final entry = consent.ConsentAuditEntry(
      actor: session.consentActor,
      verb: verb,
      path: path,
      decision: allowed
          ? const consent.ConsentDecision.allow('approver')
          : const consent.ConsentDecision.deny(
              consent.ConsentReason.approverDenied,
              planId: 'approver',
            ),
      timestamp: session.consentLedger.clock(),
    );
    session.consentLedger.auditAppend(entry);
    return entry;
  }

  /// The structured `consent-row {…}` rendering appended to every
  /// consentLog line — session.consentLog carries the structured rows
  /// while the ledger's audit stays append-only (never rewritten).
  static String _consentRow(consent.ConsentAuditEntry entry) =>
      'consent-row ${jsonEncode(entry.toJson())}';

  /// The uses label of the plan that decided [decision] — consumed/max
  /// from the LEDGER's counters (the single authority; the legacy
  /// `consentPlanUses` display field no longer feeds these paths).
  static String _usesLabel(_Session session, consent.ConsentDecision decision) {
    for (final plan in session.consentLedger.plans) {
      if (plan.planId == decision.planId) {
        return '${plan.maxUses - session.consentLedger.remainingUses(plan.planId)}'
            '/${plan.maxUses}';
      }
    }
    return 'n/a';
  }


  @override
  void attachPermissionRequester(
    Future<AcpPermissionOutcome> Function(AcpPermissionRequest request)
    requester,
  ) {
    _permissionRequester = requester;
  }

  /// R7 production #4 — the server attaches the propose_move round-trip.
  @override
  void attachMoveProposer(
    Future<AcpMoveResponse> Function(AcpMoveProposal proposal) proposer,
  ) {
    _moveProposer = proposer;
  }

  /// Sessions keyed by id; the workspace index maps cwd → session so the
  /// WORLD (and the meaning tree) persists per workspace (R7c).
  final _sessions = <String, _Session>{};
  var _counter = 0;

  @override
  String get name => 'harnessd';

  @override
  String get version => '0.2.0';

  @override
  Map<String, Object?> get agentCapabilities => const {
    // R7c: sessions resume from the per-workspace snapshot store (beats,
    // verdicts, budgets — the tree re-derives, it is never restored).
    'loadSession': true,
  };

  ModelRouter? _buildRouter() =>
      bindings[backend]?.buildRouter(model: model, apiKey: apiKey);

  /// Per-workspace snapshot store path (P5 machinery, R7c restore).
  String _storePath(String cwd) => '$cwd/.dart_tool/harnessd_store';

  @override
  Future<String> createSession(AcpSessionNewRequest request) async {
    onActivity?.call();
    // Server-side tier enforcement (follow-up 1): the tier the client
    // declares at `session/new` (`_meta.sessionTier` — the extension
    // always sends it; non-extension clients may not) is parsed HERE,
    // ONCE per session. Absent/unknown → null = the daemon's current
    // hardcoded read-program defaults (bit-identical); malformed → named
    // bounce (createSession throws, the transport surfaces it as the
    // wire error — defaults stay unchanged).
    final tier = parseSessionTierMeta(request.meta);
    // Per-workspace persistence: a live session for the same workspace
    // CONTINUES (the world — and the meaning tree — stay warm).
    final live = _sessions.values
        .where((s) => s.cwd == request.cwd)
        .firstOrNull;
    if (live != null) return live.id;

    final id = 'sess_${++_counter}';
    final store = SnapshotStore();
    await store.open(_storePath(request.cwd));
    World? restored;
    try {
      restored = await store.load('current');
    } on Object {
      // No snapshot yet (first session for this workspace) — fresh world.
    }
    final session = _Session(
      id: id,
      cwd: request.cwd,
      store: store,
      router: _buildRouter(),
      world: restored,
      tier: tier,
    );
    _sessions[id] = session;
    // ADR 0027 amendment — the WORKSPACE-LEVEL consent policy
    // (`<cwd>/.harnessd/consent.json`) applies to every new session
    // automatically; absent/malformed → deny-by-default unchanged.
    final workspacePlan = ConsentPlan.forWorkspace(Directory(request.cwd));
    if (workspacePlan != null) setConsentPlan(id, workspacePlan);
    return id;
  }

  /// The R7c mechanical tick: re-scan mtime-changed files into the
  /// persistent tree BEFORE the prompt. Zero model tokens; the tree is
  /// re-derived, never snapshotted.
  Future<void> _mechanicalTick(_Session session) async {
    final world = session.world;
    if (world == null) return;
    try {
      if (world.maybeGetResource<MeaningIndex>() == null) return;
    } on Object {
      return;
    }
    final tool = repoEtlTool(
      world,
      Directory(session.cwd),
      state: session.etlState,
    );
    await tool.execute({'action': 'refresh'});
  }

  /// ADR 0027 §1 — the READ WORLD: a lazy, read-verbs-only registry
  /// (repo_etl + the ONE read program — NO edit verbs) over the session's
  /// own ETL state. ADR 0030 §3 graduation: the program REPLACED
  /// meaning_zoom/impact/locate here too — one read dialect everywhere.
  /// Reads never mutate; the task path's single-writer world is untouched.
  /// Its own RepoEtlState keeps the mtime bookkeeping independent.
  Future<void> _ensureReadWorld(_Session session) async {
    if (session.readWorld != null) return;
    final world = World()..addPlugin(AgentPlugin());
    world
      ..upsertResource(ToolRegistryResource())
      ..upsertResource(ModelRouterResource(session.router ?? ModelRouter()));
    final jail = Directory(session.cwd);
    final registry = ToolRegistry();
    final etl = repoEtlTool(world, jail, state: session.readEtlState);
    registry.register(etl);
    // Server-side tier enforcement (follow-up 1): the session's declared
    // tier sources the program's per-op result budget and verdict budget
    // (and the `read` op's default budget through them). Null tier →
    // meaningProgramTool's own hardcoded consts — bit-identical defaults.
    registry.register(
      meaningProgramTool(
        world,
        spanReader: meaningSpanReader(FsToolsRoot(jail.path)),
        perOpResultBudget: session.tier?.perOpReadBudget,
        verdictBudget: session.tier?.verdictBudget,
      ),
    );
    // Mechanical EXECUTION directive (allowlist enforced inside the tool —
    // the same convention prefixes the meaning profile's run uses). A run
    // is not a read (tests write files) — it rides its own classifier.
    registry.register(
      runTool(
        FsToolsRoot(session.cwd),
        allowlist: const [
          ['dart', 'analyze'],
          ['dart', 'test'],
          ['dart', 'run'],
          ['flutter', 'analyze'],
          ['flutter', 'test'],
        ],
      ),
    );
    world.getResource<ToolRegistryResource>().register('default', registry);
    session.readWorld = world;
    // Initial scan so zoom/impact targets exist (mechanical, zero tokens).
    await etl.execute({'action': 'scan'});
  }

  /// Executes the read directives of [text] against the read registry and
  /// streams every result. Mechanical host program — no model involved.
  Future<void> _runReadDirectives(
    _Session session,
    String text,
    void Function(AcpSessionUpdate update) emit,
  ) async {
    final registry = session.readWorld!
        .getResource<ToolRegistryResource>()
        .get('default')!;
    Future<void> run(String name, Map<String, dynamic> args) async {
      final tool = registry.tools[ToolName(name)];
      if (tool == null) {
        emit(
          AgentMessageChunk(
            content: AcpTextBlock('\n[$name] unknown read tool\n'),
          ),
        );
        return;
      }
      final out = await tool.execute(args);
      final s = out ?? '{}';
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[$name] '
            '${s.length > 4000 ? "${s.substring(0, 4000)}…" : s}\n',
          ),
        ),
      );
    }

    if (RegExp(r'\[scan\]').hasMatch(text)) {
      await run('repo_etl', {'action': 'scan'});
    }
    final programs = _ScriptedDaemonActor._payloads(text, 'harness_meaning_program');
    for (final args in programs.items) {
      await run('meaning_program', args);
    }
    final dropped = programs.dropped;
    if (dropped > 0) {
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[read path] $dropped malformed payload(s) dropped — never '
            'guessed (ADR 0027)\n',
          ),
        ),
      );
    }
  }

  /// ADR 0027 amendment — MECHANICAL WRITES: executes `harness_fs_write`
  /// payloads through the review gate (jail-resolve → consent round-trip
  /// → write → tree reconcile). Zero mover, zero grade; no consent
  /// approver wired → refuse (deny-by-default is STRUCTURAL, same law as
  /// write_review). The tool's own validation (dart refusal, payload
  /// shape) is reused — never duplicated here.
  Future<AcpStopReason> _runMechanicalWrites(
    _Session session,
    String text,
    String sessionId,
    void Function(AcpSessionUpdate update) emit,
  ) async {
    if (_permissionRequester == null) {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock(
            '\n[harness_fs_write] refused: no consent approver wired — '
            'deny-by-default is structural\n',
          ),
        ),
      );
      return AcpStopReason.refusal;
    }
    await _ensureReadWorld(session);
    final registry = session.readWorld!
        .getResource<ToolRegistryResource>()
        .get('default')!;
    // P1: the failure class of the LAST permission round-trip (the loop is
    // sequential — the approver answers BEFORE the tool ack streams), so
    // the named class can ride the tool result below.
    var lastDenyClass = '';
    if (!registry.tools.containsKey(const ToolName('write_review'))) {
      final gateway = JailWriteGateway(
        FsToolsRoot(session.cwd),
        mode: WriteGateMode.review,
        approver: (write) async {
          // R9.1 consent inheritance: a workspace-level plan
          // (.harnessd/consent.json) or a session-level grant answers
          // matching writes mechanically — pi's consent is inherited, the
          // human is prompted only OUTSIDE the plan. Consent-scoping
          // integration: the answer IS the session ledger's
          // `matches(actor, verb, path)` — actor-keyed, budget-tracked,
          // every outcome an audited `ConsentAuditEntry`.
          final decision = session.consentLedger.matches(
            actor: session.consentActor,
            verb: 'write',
            path: write.relativePath,
          );
          if (decision.allowed) {
            session.consentLog.add(
              'plan-allowed mechanical write: ${write.relativePath} '
              '(plan: ${decision.planId}, '
              'uses: ${_usesLabel(session, decision)}) | '
              '${_consentRow(session.consentLedger.audit.last)}',
            );
            return true;
          }
          // P1 consent UX hardening: the round-trip is bounded (deadline
          // + cancel) and audited WITH ITS PATH — a silent allow is
          // detectable in the audit (F3 attribution).
          final answer = await _askClientPermission(
            session,
            sessionId: sessionId,
            request: AcpPermissionRequest(
              sessionId: sessionId,
              toolCallId: 'write:${write.hashCode}',
              title: 'write ${write.relativePath}',
              kind: 'edit',
              details: JailWriteGateway.unifiedDiff(write),
            ),
            subject: 'mechanical write ${write.relativePath}',
            verb: 'write',
            consentPath: write.relativePath,
          );
          lastDenyClass = answer.failureClass;
          return answer.allowed;
        },
      );
      registry.register(writeReviewTool(FsToolsRoot(session.cwd), gateway));
    }
    final tool = registry.tools[const ToolName('write_review')]!;
    final payloads = _ScriptedDaemonActor._payloads(text, 'harness_fs_write');
    if (payloads.dropped > 0) {
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[harness_fs_write] ${payloads.dropped} malformed payload(s) '
            'dropped — never guessed (ADR 0027)\n',
          ),
        ),
      );
    }
    var applied = 0;
    for (final args in payloads.items) {
      lastDenyClass = '';
      final out = await tool.execute(args) ?? '{}';
      if (out.contains('"ack":"wrote') || out.startsWith('wrote')) applied++;
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[write_review] '
            '${out.length > 4000 ? "${out.substring(0, 4000)}…" : out}\n',
          ),
        ),
      );
      // P1: the named failure class rides the TOOL RESULT — a timeout or
      // cancel-deny permission wait is visible to the client without
      // re-reading the audit.
      if (lastDenyClass.isNotEmpty) {
        emit(
          AgentMessageChunk(
            content: AcpTextBlock(
              '\n[write_review] failure_class: $lastDenyClass — the '
              'permission wait resolved DENY (a loop-breaker, not a policy '
              'change; re-send the write to retry)\n',
            ),
          ),
        );
      }
    }
    if (applied > 0) {
      // The tree must not lie: reconcile immediately (mechanical — the
      // tree-driven tick stats stored nodes and walks only mtime-moved
      // dirs; a landed write is visible to zoom on the next cut).
      final etl = registry.tools[const ToolName('repo_etl')];
      if (etl != null) {
        final out = await etl.execute({'action': 'refresh'}) ?? '{}';
        emit(
          AgentMessageChunk(
            content: AcpTextBlock('\n[repo_etl refresh] $out\n'),
          ),
        );
      }
    }
    if (session.cancelled) {
      // P1: a cancel during an open permission wait (or anywhere in the
      // mechanical path) ends the turn CANCELLED — the loop idles, the
      // turn never pretends to have completed.
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock('\ncancelled by the client\n'),
        ),
      );
      return AcpStopReason.cancelled;
    }
    emit(
      AgentMessageChunk(
        content: AcpTextBlock(
          '\n[mechanical write path] $applied applied, '
          '${payloads.items.length - applied} refused/dropped — no task, '
          'no grade (ADR 0027 amendment)\n',
        ),
      ),
    );
    return AcpStopReason.endTurn;
  }

  /// ADR 0027 amendment — MECHANICAL RUNS: executes `harness_run {…}`
  /// payloads through the allowlisted run tool (per-file test/analyze
  /// scopes included). Zero mover, zero grade; the allowlist bounces
  /// non-convention commands as named data BEFORE spawning.
  Future<AcpStopReason> _runMechanicalRuns(
    _Session session,
    String text,
    void Function(AcpSessionUpdate update) emit,
  ) async {
    await _ensureReadWorld(session);
    final registry = session.readWorld!
        .getResource<ToolRegistryResource>()
        .get('default')!;
    final tool = registry.tools[const ToolName('run')];
    if (tool == null) {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock('\n[harness_run] run tool missing\n'),
        ),
      );
      return AcpStopReason.refusal;
    }
    final payloads = _ScriptedDaemonActor._payloads(text, 'harness_run');
    if (payloads.dropped > 0) {
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[harness_run] ${payloads.dropped} malformed payload(s) '
            'dropped — never guessed (ADR 0027)\n',
          ),
        ),
      );
    }
    for (final args in payloads.items) {
      final command = args['command'];
      if (command is! List || command.isEmpty) {
        emit(
          AgentMessageChunk(
            content: const AcpTextBlock(
              '\n[harness_run] payload needs command: [argv…] — dropped\n',
            ),
          ),
        );
        continue;
      }
      final out = await tool.execute(args) ?? '{}';
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[run] '
            '${out.length > 4000 ? "${out.substring(0, 4000)}…" : out}\n',
          ),
        ),
      );
    }
    return AcpStopReason.endTurn;
  }

  /// ADR 0027 amendment — the MECHANICAL EDIT DIRECTIVE path: classify,
  /// bounce what is structurally invalid, execute the rest through
  /// [_executeMechanicalEdits]. Zero mover, zero grade; the mover model is
  /// NEVER involved.
  Future<AcpStopReason> _runMechanicalEditDirectives(
    _Session session,
    String text,
    String sessionId,
    void Function(AcpSessionUpdate update) emit,
  ) async {
    final c = classifyMechanicalEditDirective(text);
    final bounced = c.malformed + c.invalid;
    if (c.malformed > 0) {
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[harness_edit] ${c.malformed} malformed payload(s) dropped '
            '— never guessed (ADR 0027)\n',
          ),
        ),
      );
    }
    if (c.invalid > 0) {
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[harness_edit] ${c.invalid} invalid payload(s) bounced — '
            'the mechanical edit union is replace_member_body / '
            'insert_member / apply_executable with a required symbolId '
            'and its action-scoped slots; the mover is never reached for '
            'structurally invalid directives\n',
          ),
        ),
      );
    }
    return _executeMechanicalEdits(
      session,
      c.payloads,
      sessionId: sessionId,
      bounced: bounced,
      emit: emit,
    );
  }

  /// ADR 0027 amendment — MOVER-REFUSAL FALLBACK: a graded edit task that
  /// ended `mover_refusal: empty move` with EXACTLY ONE well-formed
  /// `harness_edit` payload executes that payload mechanically. The
  /// payload was DATA all along; the mover refused to judge it and the
  /// burned root-convention verify only added cost. Null → the prompt
  /// carries no single well-formed payload (the graded verdict stands).
  Future<AcpStopReason?> _runMoverRefusalEditFallback(
    _Session session,
    String text,
    String sessionId,
    void Function(AcpSessionUpdate update) emit,
  ) async {
    if (_permissionRequester == null) return null;
    final extracted = extractEditPayloads(text);
    if (extracted.groups.length != 1) return null;
    final payload = validateMechanicalEditPayload(extracted.groups.single);
    if (payload == null) return null;
    emit(
      AgentMessageChunk(
        content: const AcpTextBlock(
          '\nmover_refusal with a single well-formed harness_edit payload '
          '— executing the payload mechanically (ADR 0027 amendment; the '
          'mover model is never re-asked)\n',
        ),
      ),
    );
    return _executeMechanicalEdits(
      session,
      [payload],
      sessionId: sessionId,
      emit: emit,
    );
  }

  /// ADR 0027 amendment — MECHANICAL EDIT EXECUTION: validated payloads →
  /// consent (the SAME consent-UX machinery the write path uses: consent
  /// plan inheritance, the bounded client round-trip with deadline +
  /// cancel + path attribution) → the SAME edit materializer path a
  /// mover-approved edit uses (`edit_symbol` → SpanEditMaterializer, with
  /// its fences, oracles and auto-revert) → the touched-file beat lands
  /// on the goal actor's thread so the verify-tier derivation sees the
  /// touched set without a mover round-trip. No approver wired → refuse
  /// (deny-by-default is STRUCTURAL, same law as write_review).
  Future<AcpStopReason> _executeMechanicalEdits(
    _Session session,
    List<MechanicalEditPayload> payloads, {
    required String sessionId,
    required void Function(AcpSessionUpdate update) emit,
    int bounced = 0,
  }) async {
    if (_permissionRequester == null) {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock(
            '\n[harness_edit] refused: no consent approver wired — '
            'deny-by-default is structural\n',
          ),
        ),
      );
      return AcpStopReason.refusal;
    }
    await _ensureReadWorld(session);
    final registry = session.readWorld!
        .getResource<ToolRegistryResource>()
        .get('default')!;
    // The edit verb is registered ON DEMAND with the consent approver —
    // the read world stays read-verbs-only for every other route.
    // P1: the failure class of the LAST permission round-trip rides the
    // tool result below (the loop is sequential — the approver answers
    // BEFORE the tool ack streams).
    var lastDenyClass = '';
    if (!registry.tools.containsKey(const ToolName('edit_symbol'))) {
      registry.register(
        editSymbolTool(
          session.readWorld!,
          Directory(session.cwd),
          approver: (plan) async {
            // R9.1 consent inheritance: a workspace-level plan
            // (.harnessd/consent.json) or a session-level grant answers
            // matching edits mechanically — the human is prompted only
            // OUTSIDE the plan. Consent-scoping integration: the answer
            // IS the session ledger's `matches(actor, verb, path)`.
            final target = plan.patches.firstOrNull?.file ?? '';
            final decision = session.consentLedger.matches(
              actor: session.consentActor,
              verb: 'edit',
              path: target,
            );
            if (decision.allowed) {
              session.consentLog.add(
                'plan-allowed mechanical edit: ${plan.description} '
                '(plan: ${decision.planId}, '
                'uses: ${_usesLabel(session, decision)}) | '
                '${_consentRow(session.consentLedger.audit.last)}',
              );
              return true;
            }
            // P1 consent UX hardening: bounded round-trip + path audit
            // (F3 attribution) — the SAME machinery the write path uses.
            final answer = await _askClientPermission(
              session,
              sessionId: sessionId,
              request: AcpPermissionRequest(
                sessionId: sessionId,
                toolCallId: 'edit_symbol:${plan.hashCode}',
                title: plan.description,
                kind: 'edit',
              ),
              subject: 'mechanical edit ${plan.description}',
              verb: 'edit',
              consentPath: target,
            );
            lastDenyClass = answer.failureClass;
            return answer.allowed;
          },
        ),
      );
    }
    final tool = registry.tools[const ToolName('edit_symbol')]!;
    var applied = 0;
    final touchedFiles = <String>{};
    for (final payload in payloads) {
      lastDenyClass = '';
      final out = await tool.execute(payload.args) ?? '{}';
      var ok = false;
      try {
        final decoded = jsonDecode(out);
        if (decoded is Map) {
          ok = decoded['ok'] == true && decoded['reverted'] != true;
          final files = decoded['files'];
          if (files is List) {
            touchedFiles.addAll([
              for (final f in files)
                if (f is String) f,
            ]);
          }
        }
      } on FormatException {
        // Non-JSON tool output: the emitted chunk carries the detail.
      }
      if (ok) applied++;
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[edit_symbol] '
            '${out.length > 4000 ? "${out.substring(0, 4000)}…" : out}\n',
          ),
        ),
      );
      // P1: the named failure class rides the TOOL RESULT — a timeout or
      // cancel-deny permission wait is visible to the client without
      // re-reading the audit (identical in shape to the write path).
      if (lastDenyClass.isNotEmpty) {
        emit(
          AgentMessageChunk(
            content: AcpTextBlock(
              '\n[edit_symbol] failure_class: $lastDenyClass — the '
              'permission wait resolved DENY (a loop-breaker, not a '
              'policy change; re-send the directive to retry)\n',
            ),
          ),
        );
      }
    }
    if (applied > 0) {
      // The touched-file beat lands on the GOAL actor's thread — the
      // same shape a mover-approved edit leaves — so the per-package
      // verify derivation is exercisable end-to-end (the surface-gap
      // finding: the beat never landed because the mutation verb routed
      // through the mover round-trip).
      _landTouchedFileBeat(session, touchedFiles.toList()..sort());
      // The tree must not lie: reconcile immediately (same law as the
      // write path — a landed edit is visible to zoom on the next cut).
      final etl = registry.tools[const ToolName('repo_etl')];
      if (etl != null) {
        final out = await etl.execute({'action': 'refresh'}) ?? '{}';
        emit(
          AgentMessageChunk(
            content: AcpTextBlock('\n[repo_etl refresh] $out\n'),
          ),
        );
      }
    }
    if (session.cancelled) {
      // P1: a cancel during an open permission wait (or anywhere in the
      // mechanical path) ends the turn CANCELLED — identical to the
      // write path.
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock('\ncancelled by the client\n'),
        ),
      );
      return AcpStopReason.cancelled;
    }
    emit(
      AgentMessageChunk(
        content: AcpTextBlock(
          '\n[mechanical edit path] $applied applied, '
          '${payloads.length - applied + bounced} bounced/refused — no '
          'task, no grade, no mover (ADR 0027 amendment)\n',
        ),
      ),
    );
    return AcpStopReason.endTurn;
  }

  /// The touched-file beat (ADR 0023 §2): a beat named `edit_symbol` with
  /// the touched `files` on the GOAL actor's first thread — the exact
  /// shape `sessionTouchedFiles` / the verify-tier planner read. A world
  /// without a goal-carrying actor is bootstrapped minimally (the graded
  /// resume path opens a FRESH decision for the next task, so a
  /// bootstrapped goal never hijacks a later run).
  void _landTouchedFileBeat(_Session session, List<String> files) {
    var world = session.world;
    if (world == null) {
      world = World()..addPlugin(AgentPlugin());
      world.upsertResource(ToolRegistryResource());
      session.world = world;
    }
    Entity? actor;
    Entity? thread;
    final carriers = world.query2<Actor, Goal>().toList();
    if (carriers.isNotEmpty) {
      actor = carriers.first.$1.entity;
      thread = world
          .getEntity(actor!)
          .$1
          .get<ActorThreads>()
          ?.threads
          .firstOrNull;
    }
    if (actor == null || thread == null) {
      final scene = world.spawnComponents([Scene(), SceneFrame()]);
      actor = world.spawnComponents([
        Actor(agentId: AgentId.create()),
        ActorModel(modelId: ModelId.create()),
        ActorThreads(threads: const []),
        ActorTools(registryName: 'default'),
        PresentInScene(sceneEntity: scene),
        Goal(text: 'mechanical edit directives'),
      ]);
      thread = spawnThread(world, actor, scene);
      world.upsertComponent(actor, ActorThreads(threads: [thread]));
      world.flush();
    }
    final beat = world.reserveEmptyEntity().entity;
    final detail = 'mechanical edit landed: ${files.join(", ")}';
    world
        .getEntity(beat)
        .$1
      ..insert(BeatToolCall('edit_symbol', const {}))
      ..insert(
        ToolResultContent(
          name: 'edit_symbol',
          output: {
            'ok': true,
            'mechanical': true,
            'patches': files.length,
            'files': files,
            'detail': detail,
          },
        ),
      )
      ..insert(Speaker(actor))
      ..insert(TextContent(detail))
      ..insert(BeatStatus(BeatStatusEnum.complete))
      ..insert(BeatModality(BeatModalityEnum.toolCall))
      ..insert(BelongsToThread(thread));
    indexBeat(world, beat, const <String>[], thread: thread);
  }

  @override
  Future<AcpStopReason> prompt(
    AcpPromptRequest request, {
    required void Function(AcpSessionUpdate update) emit,
    required bool Function() isCancelled,
  }) async {
    final session = _sessions[request.sessionId];
    if (session == null) {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock('error: unknown session'),
        ),
      );
      return AcpStopReason.refusal;
    }
    session.cancelled = false;
    onActivity?.call();
    await _mechanicalTick(session);

    final text = [
      for (final block in request.prompt)
        if (block is AcpTextBlock) block.text,
    ].join('\n').trim();
    if (text.isEmpty) {
      emit(AgentMessageChunk(content: const AcpTextBlock('empty prompt')));
      return AcpStopReason.refusal;
    }

    // ADR 0027 §1 — READS ARE NOT BUILDS: a directive-only read prompt
    // ([scan]/harness_meaning_program, no mutation payloads,
    // no leftover task prose) executes MECHANICALLY against the session's
    // registry — zero model, zero grade — and the cuts stream back. A
    // `[read-only]`-marked free-form delegation runs as a readOnly task
    // (the real model decides what to zoom; the gate is stamped
    // not-applicable). Everything else routes to the graded task path.
    session.lastMoverRefusal = false;
    if (isReadOnlyDirectivePrompt(text)) {
      final sw = Stopwatch()..start();
      await _ensureReadWorld(session);
      await _runReadDirectives(session, text, emit);
      sw.stop();
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[read path] mechanical — no task, no grade '
            '(ADR 0027); wall ${sw.elapsedMilliseconds} ms\n',
          ),
        ),
      );
      return AcpStopReason.endTurn;
    }
    // ADR 0027 amendment — MECHANICAL WRITES: a directive-only
    // `harness_fs_write {…}` prompt executes through the review gate
    // (consent round-trip to the client) — never through the mover.
    if (isMechanicalWriteDirective(text)) {
      final sw = Stopwatch()..start();
      final stop = await _runMechanicalWrites(
        session,
        text,
        request.sessionId,
        emit,
      );
      sw.stop();
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[write path] mechanical, consent-gated — no task, no grade '
            '(ADR 0027 amendment); wall ${sw.elapsedMilliseconds} ms\n',
          ),
        ),
      );
      return stop;
    }
    // ADR 0027 amendment — MECHANICAL EDITS: a directive-only
    // `harness_edit {…}` prompt executes through the edit materializer
    // with consent — never through the mover. The measured failure this
    // closes: three real `harness_edit` delegations each ended
    // `mover_refusal: empty move` (103 / 117 / 183 s) burning a
    // root-convention fallback verify, the touched-file beat never
    // landing. The payload is DATA; the human is the approver.
    if (isMechanicalEditDirective(text)) {
      final sw = Stopwatch()..start();
      final stop = await _runMechanicalEditDirectives(
        session,
        text,
        request.sessionId,
        emit,
      );
      sw.stop();
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[edit path] mechanical, consent-gated — no task, no grade '
            '(ADR 0027 amendment); wall ${sw.elapsedMilliseconds} ms\n',
          ),
        ),
      );
      return stop;
    }
    // ADR 0027 amendment — MECHANICAL RUNS: a directive-only
    // `harness_run {…}` prompt executes through the allowlisted run tool.
    if (isMechanicalRunDirective(text)) {
      final sw = Stopwatch()..start();
      final stop = await _runMechanicalRuns(session, text, emit);
      sw.stop();
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\n[run path] mechanical, allowlist-gated — no task, no grade '
            '(ADR 0027 amendment); wall ${sw.elapsedMilliseconds} ms\n',
          ),
        ),
      );
      return stop;
    }
    final readOnlyTask = _marksReadOnly(text);

    // D8: the workspace convention decides the criterion — no per-task code.
    CodingAgentTask? task;
    // N4 escalation rung: a budget-exhausted task awaits operator guidance.
    // The next prompt CONTINUES it (restored world, widened monotonic
    // allowance) instead of starting a new task.
    if (session.pendingEscalation != null) {
      final pending = session.pendingEscalation!;
      // Guidance reaches the model through the repair hint — the SAME
      // bounded repair channel the driver already uses, never a new one.
      task = CodingAgentTask(
        id: pending.id,
        prompt: pending.prompt,
        fixtures: pending.fixtures,
        checkers: pending.checkers,
        intents: pending.intents,
        runCommand: pending.runCommand,
        meaningProfile: pending.meaningProfile,
        repairHint:
            'Operator guidance (escalation round '
            '${session.escalationRounds + 1}): $text\n\n'
            // ADR 0027 §3: reasoning REUSE — the failed round's mover
            // reasoning rides the repair hint (truncated tail = the most
            // recent constraints), so the next round builds on it instead
            // of re-deriving. Never re-projected into routine cuts.
            '${session.lastThinking.isEmpty ? "" : "Mover reasoning from the failed round (build on it, do not repeat it):\n${session.lastThinking.length > 1500 ? "…${session.lastThinking.substring(session.lastThinking.length - 1500)}" : session.lastThinking}\n\n"}'
            '${pending.repairHint}',
        systemPrompt: pending.systemPrompt,
      );
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            'escalation round ${session.escalationRounds + 1}: continuing '
            '"${task.prompt}" with guidance\n',
          ),
        ),
      );
    }
    CodingAgentRunResult result;
    try {
      task ??= taskFromSentence(
        text,
        workspace: Directory(session.cwd),
        meaningProfile: meaningProfile,
        readOnly: readOnlyTask,
        // An EMPTY override means "the workspace convention decides" —
        // never an empty command (that would be a degenerate gate).
        // (Local copy: public fields do not promote in Dart.)
        check: (checkCommand == null || checkCommand!.isEmpty)
            ? null
            : checkCommand,
      );
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            'delegated: "${task.prompt}"\ncheck: '
            '${task.runCommand?.join(" ")}\n',
          ),
        ),
      );
      // R7c item 3: the edit/write approver routes to the CLIENT
      // (deny-by-default — no requester wired means no approval path).
      // The consent carries the unified diff (write) / plan description
      // (edit) so the human decides on the CHANGE, not just the path.
      // ADR 0027 amendment — CONSENT PLANS: a session-level bounded grant
      // (host-side, INVISIBLE to the model) answers matching writes/edits
      // without a per-write prompt — autonomous runs keep deny-by-default
      // OUTSIDE the plan and stop stalling INSIDE it. Every plan answer
      // is logged as session data. Consent-scoping integration: the
      // answer IS the session ledger's `matches(actor, verb, path)` —
      // actor-keyed, budget-tracked, every outcome an audited
      // `ConsentAuditEntry` (explicit actor plans beat the `*` fallback;
      // the ledger enforces precedence).
      consent.ConsentDecision planAllows(String path, String kind) =>
          session.consentLedger.matches(
            actor: session.consentActor,
            verb: kind,
            path: path,
          );

      Future<bool> Function(SpanEditPlan)? editApprover;
      // P1: the failure class of the LAST permission round-trip this turn
      // (write/edit paths) — consumed by onToolResult to annotate the
      // generic workspace deny ack with the named class. The loop is
      // sequential: the approver answers BEFORE the tool ack streams.
      var lastWriteDenyClass = '';
      var lastEditDenyClass = '';
      // P1 trusted-author tier: the pack-write consent for authored-body
      // pack executables answers from the consent plan — SYNC, planAllows-
      // style (pack registration runs inside `editSymbolTool`'s sync load
      // loop; the async permission round-trip cannot reach it). The plan
      // path targets the PACK FILE (the workspace-relative path the
      // consent plan scopes); `pack_write` is its own verb — it never
      // rides `write`/`edit`. Deny-by-default: no plan, exhausted uses,
      // or no match → false (the entry skips as named data, tool
      // construction never crashes); every answer lands in the audit log
      // (ledger + the structured consentLog row).
      bool packConsent(EditExecutableWire wire, String authoredBodyDiff) {
        const packPath = '.dart_tool/harnessd/edit_pack.json';
        final decision = planAllows(packPath, 'pack_write');
        final row = _consentRow(session.consentLedger.audit.last);
        session.consentLog.add(
          decision.allowed
              ? 'plan-allowed pack_write: ${wire.id} '
                  '(plan: ${decision.planId}, '
                  'uses: ${_usesLabel(session, decision)}) | $row'
              : 'pack_write REFUSED: ${wire.id} — '
                  '${decision.reason == consent.ConsentReason.noPlan
                      ? "no consent plan"
                      : "outside/exhausted plan"} | $row',
        );
        return decision.allowed;
      }
      if (_permissionRequester != null) {
        editApprover = (plan) async {
          final target = plan.patches.firstOrNull?.file ?? '';
          final decision = planAllows(target, 'edit');
          if (decision.allowed) {
            session.consentLog.add(
              'plan-allowed edit: ${plan.description} '
              '(plan: ${decision.planId}, '
              'uses: ${_usesLabel(session, decision)}) | '
              '${_consentRow(session.consentLedger.audit.last)}',
            );
            return true;
          }
          // P1 consent UX hardening: bounded round-trip + path audit (F3).
          final answer = await _askClientPermission(
            session,
            sessionId: request.sessionId,
            request: AcpPermissionRequest(
              sessionId: request.sessionId,
              toolCallId: 'edit_symbol:${plan.hashCode}',
              title: plan.description,
              kind: 'edit',
            ),
            subject: 'edit ${plan.description}',
            verb: 'edit',
            consentPath: target,
          );
          lastEditDenyClass = answer.failureClass;
          return answer.allowed;
        };
      }
      final baseHandler = scripted
          ? _ScriptedDaemonActor()
          : remoteMover
          ? _RemoteMoverHandler(session, _moveProposer!)
          : handlerFactory != null
          // Scripted/LLM-free tests inject handlers and may carry no
          // router — the factory receives whatever the session has.
          ? handlerFactory!(session.router ?? ModelRouter())
          : DefaultGenerationHandler(router: session.router!);
      result = await runCodingAgentOnce(
        task: task,
        jail: Directory(session.cwd),
        handler: _Telemetry(emit, session, baseHandler),
        backend: '$backend:$model',
        router: session.router,
        actorModelId: session.router?.models.keys.first,
        restoredWorld: session.world,
        allowDeclaredChecks: true,
        // R7c item 5: monotonic widening with a HARD CEILING.
        maxGoalAttempts: min(
          3 + session.escalationRounds,
          maxEscalationCeiling,
        ),
        // N4: the write gate asks the CLIENT (pi/human) per write — the
        // permission round-trip lands as a session/request_permission call.
        writeGateMode: _permissionRequester == null
            ? null
            : WriteGateMode.review,
        writeApprover: _permissionRequester == null
            ? null
            : (write) async {
                final decision = planAllows(write.relativePath, 'write');
                if (decision.allowed) {
                  session.consentLog.add(
                    'plan-allowed write: ${write.relativePath} '
                    '(plan: ${decision.planId}, '
                    'uses: ${_usesLabel(session, decision)}) | '
                    '${_consentRow(session.consentLedger.audit.last)}',
                  );
                  return true;
                }
                // P1 consent UX hardening: bounded round-trip + path
                // audit (F3 attribution — a silent allow is detectable).
                final answer = await _askClientPermission(
                  session,
                  sessionId: request.sessionId,
                  request: AcpPermissionRequest(
                    sessionId: request.sessionId,
                    toolCallId: 'write:${write.hashCode}',
                    title: 'write ${write.relativePath}',
                    kind: 'edit',
                    details: JailWriteGateway.unifiedDiff(write),
                  ),
                  subject: 'write ${write.relativePath}',
                  verb: 'write',
                  consentPath: write.relativePath,
                );
                lastWriteDenyClass = answer.failureClass;
                return answer.allowed;
              },
        editApprover: editApprover,
        packConsent: packConsent,
        onSnapshot: (live) async {
          session.world = live;
          await session.store.save(
            live,
            name: 'current',
            meta: {'cwd': session.cwd},
          );
        },
        // R7 transparency: stream every tool result MID-TURN (patches,
        // verify verdicts, bounce reasons, cuts) — the ACP client sees the
        // mechanical tier as it works, not a silent 30–60s tool call.
        onToolResult: (name, output) {
          var text = '$output';
          // P1: the named failure class rides the TOOL RESULT — a timeout
          // or cancel-deny permission wait is visible in the stream, not
          // only in the audit. The generic workspace deny acks
          // ('REJECTED … by host write policy' for writes,
          // '"failureClass":"permission_denied"' for edits) are annotated
          // when the last permission round-trip of this turn resolved deny
          // with a named class (plain approver denies keep the ack as-is).
          if (lastWriteDenyClass.isNotEmpty && text.startsWith('REJECTED ')) {
            text += '\nfailure_class: $lastWriteDenyClass';
            lastWriteDenyClass = '';
          } else if (lastEditDenyClass.isNotEmpty &&
              text.contains('"failureClass":"permission_denied"')) {
            text += '\nfailure_class: $lastEditDenyClass';
            lastEditDenyClass = '';
          }
          emit(
            AgentMessageChunk(
              content: AcpTextBlock(
                '\n[$name] '
                '${text.length > 4000 ? "${text.substring(0, 4000)}…" : text}\n',
              ),
            ),
          );
        },
      );
    } on _Cancelled {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock('\ncancelled by the client\n'),
        ),
      );
      return AcpStopReason.cancelled;
    } on StateError catch (e) {
      if (session.cancelled) {
        emit(
          AgentMessageChunk(
            content: const AcpTextBlock('\ncancelled by the client\n'),
          ),
        );
        return AcpStopReason.cancelled;
      }
      emit(AgentMessageChunk(content: AcpTextBlock('${e.message}')));
      return AcpStopReason.refusal;
    }
    // R7c item 4: the loop swallows handler errors BY DESIGN (a throwing
    // handler must resolve the task, never hang the harness) — so the
    // cancel flag is observed HERE, at the turn boundary.
    if (session.cancelled) {
      emit(
        AgentMessageChunk(
          content: const AcpTextBlock(
            '\ncancelled by the client (generation aborted)\n',
          ),
        ),
      );
      return AcpStopReason.cancelled;
    }
    // ADR 0027 amendment — MOVER-REFUSAL FALLBACK: a graded edit task that
    // ended `mover_refusal: empty move` with EXACTLY ONE well-formed
    // `harness_edit` payload executes that payload mechanically — the
    // payload was DATA all along, the mover refused to judge it, and the
    // burned verify above must not be the whole answer. The consent UX
    // and the materializer path are the SAME ones a directive-only
    // mechanical edit uses.
    if (!result.passed && session.lastMoverRefusal) {
      final stop = await _runMoverRefusalEditFallback(
        session,
        text,
        request.sessionId,
        emit,
      );
      if (stop != null) return stop;
    }

    emit(
      AgentMessageChunk(
        content: AcpTextBlock(
          '\nverdict: ${result.passed ? "PASS" : "FAIL"} '
          '(decisions ${result.decisions}, rounds ${result.toolRounds}, '
          'tokens ${result.projectionTokens}, '
          'wall ${result.wallClock.inMilliseconds} ms, '
          'moves ${result.moves}'
          '${result.verifyWallMs > 0 ? ", verify wall ${result.verifyWallMs} ms" : ""}'
          '${session.reasoningChars > 0 ? ", reasoning ${session.reasoningChars} chars" : ""}'
          '${task!.readOnly ? ", gate read_only_not_applicable (ADR 0027)" : ""})'
          '${result.failureClass.isEmpty && !session.lastMoverRefusal
              ? ""
              : "\n${session.lastMoverRefusal && result.failureClass.isEmpty
                  ? "mover_refusal: empty move — the mover model refused the "
                      "task text (ADR 0027); phrase fixture payloads neutrally"
                  : result.failureClass}"}',
        ),
      ),
    );
    // Tool results already streamed MID-TURN via onToolResult above —
    // no emit-at-run-end copy (the old truncated transcript list).
    if (result.passed) {
      session
        ..pendingEscalation = null
        ..escalationRounds = 0;
      return AcpStopReason.endTurn;
    }
    // N4 escalation rung: budget exhaustion hands the task to the client
    // (pi/human = the strongest model in the squad) instead of dropping it.
    if (result.attemptsExhausted &&
        session.escalationRounds + 3 < maxEscalationCeiling) {
      session
        ..pendingEscalation = task
        ..escalationRounds += 1;
      emit(
        AgentMessageChunk(
          content: AcpTextBlock(
            '\nescalation: the attempt budget is exhausted. Send a follow-up '
            'prompt with guidance to continue this task (round '
            '${session.escalationRounds + 1}), or start a new task to abandon '
            'it.',
          ),
        ),
      );
      return AcpStopReason.endTurn;
    }
    return AcpStopReason.refusal;
  }

  @override
  Future<AcpPermissionOutcome> requestPermission(
    AcpPermissionRequest request,
  ) async {
    // R7c item 3 — DENY-BY-DEFAULT: route to the attached client requester
    // (the write gate / edit approver); with no approver wired there is NO
    // approval path, so the answer is reject — never an unconditional
    // allow. P1: bounded like every client round-trip — deny-on-timeout,
    // cancel-interruptible, audited with its path.
    final answer = await _askClientPermission(
      _sessions[request.sessionId],
      sessionId: request.sessionId,
      request: request,
      subject: 'request_permission ${request.title}',
    );
    return answer.allowed
        ? AcpPermissionOutcome.allow
        : AcpPermissionOutcome.reject;
  }

  @override
  void cancelSession(String sessionId) {
    // R7c item 4 — cancellation is REAL: the session flag aborts the loop
    // (checked per generation) and the in-flight backend generation is
    // cancelled via the binding's cancel hook (e.g. `xs_fm_cancel`).
    final session = _sessions[sessionId];
    if (session == null) return;
    session.cancelled = true;
    // R7 production #4: unblock a remote-mover decision that is awaiting
    // the client's propose_move response (one decision = one round-trip;
    // cancel must work MID-decision, not only between decisions).
    for (final pending in session.pendingMoves.values) {
      if (!pending.isCompleted) pending.completeError(_Cancelled());
    }
    session.pendingMoves.clear();
    // P1 consent UX hardening: cancel interrupts permission waits — every
    // pending wait resolves as DENY promptly, the tool returns and the
    // loop idles (never a dangling await; Phase 1.5 findings b/F3).
    for (final pending in session.pendingPermissions.values) {
      if (!pending.isCompleted) {
        pending.complete(
          (
            allowed: false,
            path: 'cancel-deny',
            failureClass: 'permission_cancelled',
          ),
        );
      }
    }
    session.pendingPermissions.clear();
    bindings[backend]?.cancelActiveGeneration?.call();
  }

  @override
  Future<void> disposeSession(String sessionId) async {
    _sessions.remove(sessionId);
  }
}

class _Session {
  _Session({
    required this.id,
    required this.cwd,
    required this.store,
    required this.router,
    this.world,
    this.tier,
  });
  final String id;
  final String cwd;
  final SnapshotStore store;
  final ModelRouter? router;

  /// Server-side tier enforcement (follow-up 1): the tier the client
  /// declared at `session/new` (`_meta.sessionTier`, parsed ONCE at
  /// creation). Null → absent/unknown tier = the daemon's current
  /// hardcoded read-program defaults (bit-identical behavior). A tier is
  /// a READING property only — budgets, never capabilities (see
  /// session_tier.dart); the read world threads these budgets into
  /// meaningProgramTool so NON-extension clients get tier-sourced
  /// defaults too.
  final SessionTierProfile? tier;

  /// R7c: the persistent world. The meaning tree lives HERE (built once
  /// per workspace via repo_etl, refreshed by the mechanical tick) and is
  /// never snapshotted — the store persists beats/verdicts/budgets only.
  World? world;

  /// Scan bookkeeping for the mechanical tick (mtime staleness).
  final RepoEtlState etlState = RepoEtlState();

  /// R7c item 4: set by `cancelSession`; checked per generation.
  bool cancelled = false;

  /// R7 production #4: the in-flight `session/propose_move` completions.
  /// `cancelSession` completes them with [_Cancelled] so a decision
  /// blocked awaiting the client's typed tool calls unblocks and the turn
  /// ends cancelled (never a hang).
  final pendingMoves = <String, Completer<AcpMoveResponse>>{};

  /// P1 consent UX hardening: the in-flight permission waits of this
  /// session. `cancelSession` resolves every pending wait as DENY
  /// promptly — never a dangling Future (the Phase 1.5 bridge-crash
  /// class). Keyed by permission-wait id.
  final pendingPermissions = <String, Completer<_PermissionAnswer>>{};

  /// N4 escalation rung: the task whose budget exhausted, awaiting operator
  /// guidance. The next prompt continues it with a widened (monotonic,
  /// hard-capped) attempt allowance.
  CodingAgentTask? pendingEscalation;
  int escalationRounds = 0;

  /// ADR 0027 §1 — the lazy read-verbs-only world (see _ensureReadWorld).
  World? readWorld;
  final RepoEtlState readEtlState = RepoEtlState();

  /// ADR 0027 §3 — reasoning records: total chars (the ledger column), the
  /// latest decision's thinking (reused on escalation as structured
  /// context — never re-projected into routine cuts), and the
  /// `mover_refusal` flag (empty move = the mover model refused).
  int reasoningChars = 0;
  String lastThinking = '';
  bool lastMoverRefusal = false;

  /// ADR 0027 amendment — the session's bounded consent grant (host-side;
  /// the model never sees it) + its usage counter + audit log.
  ///
  /// Consent-scoping integration: `consentPlan`/`consentPlanUses` are the
  /// LEGACY v1 display fields (kept for `setConsentPlan` compatibility);
  /// the LEDGER below is the single consent authority — every daemon
  /// consent path (write_review approver, `planAllows`, `packConsent`,
  /// the client permission round-trip) routes through
  /// `consentLedger.matches(...)` and every outcome lands as an
  /// actor-keyed, append-only `ConsentAuditEntry`.
  ConsentPlan? consentPlan;
  int consentPlanUses = 0;
  final consentLog = <String>[];

  /// The session's CONSENT LEDGER (follow-ups 3+4): registered plans
  /// (the `*` workspace fallback from `setConsentPlan`, plus any explicit
  /// per-actor plans loaded via `setSessionConsentDocument`), per-plan
  /// use counters, and the append-only audit log.
  consent.ConsentLedger consentLedger = consent.ConsentLedger();

  /// The session's stable ACTOR ID for consent purposes — derived from
  /// the workspace path (`harnessd@<cwd>`; sessions are keyed per
  /// workspace, so the derivation is stable across restarts of the same
  /// workspace and distinct across workspaces — see
  /// `consent.sessionConsentActor`). This is the actor every consent
  /// decision of this session is audited under, and the actor a v2 plan
  /// scopes its explicit grants to.
  String get consentActor => consent.sessionConsentActor(cwd);
}

/// Streams one ACP update per generation: the tool calls the actor made and
/// a short text chunk. Pure observation — the response flows unchanged.
///
/// R7 (TASK 3): tool-call ids are UNIQUE PER CALL (`t<n>_<name>`) — the
/// old implementation reused the tool NAME as the id, which collapsed
/// distinct calls in clients. The handler also honors session cancellation
/// (R7c item 4) both before and after delegation.
class _Telemetry implements GenerationHandler {
  _Telemetry(this.emit, this.session, this._inner);
  final void Function(AcpSessionUpdate update) emit;
  final _Session session;
  final GenerationHandler _inner;
  var _callSeq = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (session.cancelled) {
      throw _Cancelled();
    }
    final response = await _inner.generate(world, request);
    for (final call in response.toolCalls) {
      emit(
        ToolCallUpdate(
          // UNIQUE per call (R7 fix — the name-as-id bug collapsed calls).
          toolCallId: 't${++_callSeq}_${call.name.value}',
          status: 'completed',
          title: '${call.name.value}',
        ),
      );
    }
    final text = response.rawOutput;
    if (text.isNotEmpty) {
      emit(AgentMessageChunk(content: AcpTextBlock('$text ')));
    }
    if (session.cancelled) {
      throw _Cancelled();
    }
    return response;
  }
}

/// Cooperative cancellation signal (R7c item 4).
class _Cancelled implements Exception {
  @override
  String toString() => 'cancelled';
}

/// R7 production #4 — the REMOTE MOVER: the daemon's GenerationHandler is
/// a round-trip to the CLIENT (`session/propose_move`). Each generate()
/// call = exactly ONE propose_move: bounded cut out (the request prompt —
/// the projected situation, never file text), the CLOSED tool schemas out,
/// the live budgets out; typed tool calls back. Budgets/consent/cancel
/// stay native to the world — the loop, its budgets and its oracles are
/// unchanged; only WHO decides is pluggable.
class _RemoteMoverHandler implements GenerationHandler {
  _RemoteMoverHandler(this.session, this.proposer);
  final _Session session;
  final Future<AcpMoveResponse> Function(AcpMoveProposal proposal) proposer;
  var _seq = 0;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (session.cancelled) throw _Cancelled();
    final registry = world.getResource<ToolRegistryResource>().get('default');
    final actorWe = world.getEntity(request.actorEntity).$1;
    final proposal = AcpMoveProposal(
      sessionId: session.id,
      decisionId: 'move_${++_seq}',
      prompt: request.prompt,
      // ADR 0027 §3: the daemon CLASSIFIES the decision; the client maps
      // the hint to model/thinking config (none = cheap path).
      reasoning: classifyReasoning(request.prompt),
      toolSchemas: [
        if (registry != null)
          for (final t in registry.tools.values)
            {
              'name': t.name.value,
              'description': t.description,
              // R7 production #7 finding: the schema bundle wraps the
              // properties in a `root` key — clients rendering the bundle
              // verbatim degraded every call ({root: {...}}). The daemon
              // unwraps SERVER-SIDE so every client gets the tool's own
              // parameter shape (the pi driver no longer needs the
              // workaround).
              'parameters':
                  (t.argsSchema.toJson())['root'] ?? t.argsSchema.toJson(),
            },
      ],
      budgets: {
        'tool_rounds': actorWe.get<ToolRoundCount>()?.value ?? 0,
        'total_rounds': actorWe.get<TotalRoundCount>()?.value ?? 0,
        'attempts': actorWe.get<AttemptCount>()?.value ?? 0,
        'max_tool_rounds': 12,
      },
    );
    final pending = Completer<AcpMoveResponse>();
    session.pendingMoves[proposal.decisionId] = pending;
    try {
      // Race the client's answer against a cancellation: `cancelSession`
      // completes [pending] with the cancel signal, so a decision blocked
      // awaiting a hung client still unblocks mid-decision.
      final response = await Future.any<AcpMoveResponse>([
        proposer(proposal),
        pending.future,
      ]);
      if (session.cancelled) throw _Cancelled();
      // ADR 0027 §3 — reasoning capture: measured (chars), kept per-session
      // (reused on escalation), NEVER re-projected into routine cuts.
      if (response.thinking.isNotEmpty) {
        session.reasoningChars += response.thinking.length;
        session.lastThinking = response.thinking;
      }
      // mover_refusal: an empty move (no calls, no text) is a BOUNCE with a
      // named class — the mover model refused the task text (measured on
      // adversarial fixtures); never a silent pass.
      if (response.toolCalls.isEmpty && response.text.trim().isEmpty) {
        session.lastMoverRefusal = true;
      }
      return ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': response.text},
        rawOutput: response.text,
        toolCalls: [
          for (final c in response.toolCalls)
            ToolCall(
              name: ToolName(c.name),
              arguments: Map<String, dynamic>.of(c.arguments),
            ),
        ],
        taskId: request.taskId,
      );
    } finally {
      session.pendingMoves.remove(proposal.decisionId);
    }
  }
}

/// R7 gate mover (production #1 — the structured edit surface): maps the
/// prompt's directives to REAL tool calls over the session's registry
/// (repo_etl / meaning_program / edit_symbol / run /
/// write_review).
///
/// READ verbs with free-text args stay bracketed prose (`[scan]`,
/// `[zoom <query>]`, `[verify]`). Every ID- or SLOT-BEARING verb travels as
/// a STRUCTURED JSON payload — `harness_edit {…}` carries the exact
/// `edit_symbol` args (action, symbolId/classSymbolId, opChain,
/// executableId, executableParams), `harness_meaning_program {…}` the
/// exact read-program args (the closed op set — ADR 0030 §3)
/// (incl. zoom=file, the fs-tier escape-hatch read), and `harness_fs_write
/// {path, content}` the exact `write_review` args (consent-gated). The
/// R7 gate mover (production #1 — the structured edit surface): maps the
/// prompt's directives to REAL tool calls over the session's registry
/// (repo_etl / meaning_program / edit_symbol / run / write_review).
///
/// READ verbs with free-text args stay bracketed prose (`[scan]`,
/// `[verify]`). Every ID- or SLOT-BEARING verb travels as a STRUCTURED
/// JSON payload — `harness_edit {…}` carries the exact `edit_symbol` args
/// (action, symbolId, opChain, executableId, executableParams),
/// `harness_meaning_program {…}` the exact read-program args (the closed
/// locate/zoom/impact/read op set — ADR 0030 §3 graduation), and
/// `harness_fs_write {path, content}` the exact `write_review` args
/// (consent-gated). The mover NEVER resolves or guesses ids — the caller
/// supplies them from program data (the R7d division of labor); a
/// malformed payload is dropped and reported, never repaired into a
/// guess.
class _ScriptedDaemonActor implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final prompt = request.prompt;
    final calls = <ToolCall>[];
    final scan = RegExp(r'\[scan\]').firstMatch(prompt);
    if (scan != null) {
      calls.add(
        ToolCall(
          name: const ToolName('repo_etl'),
          arguments: {'action': 'scan'},
        ),
      );
    }
    // ADR 0030 §3 graduation — the ONE read program carries the closed
    // op set (locate/zoom/impact/read); the payload IS the program args.
    final programs = _payloads(prompt, 'harness_meaning_program');
    for (final args in programs.items) {
      calls.add(
        ToolCall(name: const ToolName('meaning_program'), arguments: args),
      );
    }
    final edits = _payloads(prompt, 'harness_edit');
    for (final args in edits.items) {
      calls.add(ToolCall(name: const ToolName('edit_symbol'), arguments: args));
    }
    // fs-tier escape hatch (ADR 0024 §4): whole-file write through the
    // review gate — the payload carries the exact write_review args.
    final writes = _payloads(prompt, 'harness_fs_write');
    for (final args in writes.items) {
      calls.add(
        ToolCall(name: const ToolName('write_review'), arguments: args),
      );
    }
    if (RegExp(r'\[verify\]').hasMatch(prompt)) {
      calls.add(
        ToolCall(
          name: const ToolName('run'),
          arguments: {
            'command': ['dart', 'analyze'],
            'timeout_ms': 120000,
          },
        ),
      );
    }
    final dropped =
        programs.dropped + edits.dropped + writes.dropped;
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {
        'text': calls.isEmpty
            ? (dropped > 0
                  ? 'malformed payload(s): $dropped — re-send valid JSON'
                  : 'no directive matched the prompt')
            : 'acting',
      },
      rawOutput: calls.isEmpty
          ? (dropped > 0
                ? 'malformed payload(s): $dropped — re-send valid JSON'
                : 'no directive matched the prompt')
          : 'acting on ${calls.length} directive(s)'
                '${dropped > 0 ? " ($dropped malformed dropped)" : ""}',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }

  /// Strips every balanced `{…}` payload following [tag] (plus the tag
  /// itself) — used by the read-directive classifier to detect leftover
  /// task prose (ADR 0027 §1).
  static String stripPayloads(String prompt, String tag) {
    var out = prompt;
    var from = 0;
    while (true) {
      final tagIdx = out.indexOf(tag, from);
      if (tagIdx < 0) break;
      final open = out.indexOf('{', tagIdx);
      if (open < 0) break;
      var depth = 0;
      var closed = false;
      for (var i = open; i < out.length; i++) {
        if (out[i] == '{') depth++;
        if (out[i] == '}') {
          depth--;
          if (depth == 0) {
            out = out.replaceRange(tagIdx, i + 1, '');
            from = tagIdx;
            closed = true;
            break;
          }
        }
      }
      if (!closed) break;
    }
    return out;
  }

  /// Extracts every balanced `{…}` JSON payload following [tag] in the
  /// prompt. A malformed (unbalanced / non-object) payload is DROPPED and
  /// counted — never guessed around.
  static _Payloads _payloads(String prompt, String tag) {
    final payloads = <Map<String, dynamic>>[];
    var dropped = 0;
    var from = 0;
    while (true) {
      final tagIdx = prompt.indexOf(tag, from);
      if (tagIdx < 0) break;
      from = tagIdx + tag.length;
      final open = prompt.indexOf('{', from);
      if (open < 0) break;
      var depth = 0;
      String? payload;
      var closed = false;
      for (var i = open; i < prompt.length; i++) {
        final c = prompt[i];
        if (c == '{') depth++;
        if (c == '}') {
          depth--;
          if (depth == 0) {
            payload = prompt.substring(open, i + 1);
            from = i + 1;
            closed = true;
            break;
          }
        }
      }
      if (!closed || payload == null) {
        dropped++;
        // Rescan AFTER this '{' — a broken group must never swallow a
        // well-formed payload that follows it. Never guess: only decoded
        // JSON objects execute.
        from = open + 1;
        continue;
      }
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          payloads.add(decoded);
        } else {
          dropped++;
        }
      } on FormatException {
        dropped++;
        // Broken JSON — same rescan rule: skip this '{', keep looking.
        from = open + 1;
      }
    }
    return (items: payloads, dropped: dropped);
  }
}

/// Parsed structured payloads + how many malformed ones were dropped.
typedef _Payloads = ({List<Map<String, dynamic>> items, int dropped});
