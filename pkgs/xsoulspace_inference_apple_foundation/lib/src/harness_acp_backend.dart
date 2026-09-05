// ignore_for_file: lines_longer_as_80_chars

/// Stage N3/N4 + R7c — the harness as a long-running ACP agent: `harnessd`.
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
///   aborts the loop and the AFM bridge generation is cancelled via
///   `xs_fm_cancel` (no more no-op);
/// - escalation stays bounded: `maxGoalAttempts = 3 + escalationRounds` is
///   hard-capped at 9 (monotonic widening, never unbounded).
///
/// The daemon is TRANSPORT + host policy — the core learns no ACP (D5).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show JailWriteGateway, WriteGateMode;
import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart'
    show RepoEtlState, SpanEditPlan, repoEtlTool;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart'
    show OpenRouterInferenceClient, OpenRouterModelNames;

import 'coding_agent_runner.dart'
    show
        CodingAgentRunResult,
        CodingAgentTask,
        runCodingAgentOnce,
        taskFromSentence;
import 'native_bridge/native_client.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show runTool;

/// Hard ceiling for the monotonic escalation widening (R7c): 3 base
/// attempts + up to 6 escalation rounds — never unbounded.
const maxEscalationCeiling = 9;

/// The monotonic (hard-capped) attempt allowance for an escalation round:
/// `3 + rounds`, never above [maxEscalationCeiling], never a reset.
int escalationAllowance(int escalationRounds) =>
    min(3 + escalationRounds, maxEscalationCeiling);

class HarnessAcpBackend
    implements AcpAgentBackend, AcpPermissionRequesting, AcpMoveProposing {
  HarnessAcpBackend({
    this.backend = 'open_router',
    this.model = 'deepseek/deepseek-v4-flash-0731',
    this.handlerFactory,
    this.meaningProfile = false,
    this.scripted = false,
    this.remoteMover = false,
    this.apiKey,
    this.checkCommand,
  });

  /// `open_router` (native tool calls) or `apple_foundation_afm`.
  final String backend;
  final String model;

  /// Explicit OpenRouter API key (embedded hosts — e.g. last_answer —
  /// cannot rely on `OPENROUTER_API_KEY` in the process environment).
  /// Null → the environment variable is read, as before.
  final String? apiKey;

  /// Explicit verification criterion overriding the D8 workspace
  /// convention (the CLI spells it `--check`). The product host (agent
  /// docs) declares it as data on the binding. Null → convention decides.
  final List<String>? checkCommand;

  /// R7: when true, delegated tasks run through the MEANING-PROFILE
  /// surface ([repo_etl, meaning_zoom, meaning_impact, edit_symbol, run])
  /// — zero `read`, zero `write`; the tree is the only code interface.
  final bool meaningProfile;

  /// Injectable handler factory (LLM-free tests). Null → the real backend.
  final GenerationHandler Function(ModelRouter router)? handlerFactory;

  /// R7 gate mode: the mover is a SCRIPTED directive interpreter — the
  /// prompt carries bracketed READ directives (`[scan]`,
  /// `[zoom <query>]`, `[verify]`) and STRUCTURED JSON payloads for the
  /// id-bearing verbs (`harness_edit {…}`, `harness_impact {…}` — the
  /// exact registry args, R7 production #1), and the actor emits the
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

  /// R7 production #5: called on every session activity (create/prompt/
  /// cancel) — the daemon's idle-exit timer resets here.
  void Function()? onActivity;

  /// The retained AFM client (when [backend] is the AFM bridge) so
  /// `cancelSession` can reach `xs_fm_cancel`.
  AppleFoundationNativeClient? _afmClient;

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

  ModelRouter? _buildRouter() {
    if (backend == 'open_router') {
      final apiKey = this.apiKey ?? Platform.environment['OPENROUTER_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) return null;
      final router = ModelRouter(
        inferenceClientsBuilders: {
          OpenRouterModelNames.openRouter: () =>
              OpenRouterInferenceClient(apiKey: apiKey, defaultModel: model),
        },
      );
      final modelId = ModelId('harnessd');
      router.models[modelId] = Model(
        id: modelId,
        name: OpenRouterModelNames.openRouter,
      );
      return router;
    }
    // AFM-first (North Star): the retained client is reachable for cancel.
    final client = _afmClient ??= AppleFoundationNativeClient();
    final router = ModelRouter(
      inferenceClientsBuilders: {
        DefaultModelNames.appleFoundation: () => client,
      },
    );
    final modelId = ModelId('harnessd');
    router.models[modelId] = Model(
      id: modelId,
      name: DefaultModelNames.appleFoundation,
    );
    return router;
  }

  /// Per-workspace snapshot store path (P5 machinery, R7c restore).
  String _storePath(String cwd) => '$cwd/.dart_tool/harnessd_store';

  @override
  Future<String> createSession(AcpSessionNewRequest request) async {
    onActivity?.call();
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
    );
    _sessions[id] = session;
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
      Future<bool> Function(SpanEditPlan)? editApprover;
      if (_permissionRequester != null) {
        editApprover = (plan) async {
          final outcome = await _permissionRequester!(
            AcpPermissionRequest(
              sessionId: request.sessionId,
              toolCallId: 'edit_symbol:${plan.hashCode}',
              title: plan.description,
              kind: 'edit',
            ),
          );
          return outcome == AcpPermissionOutcome.allow;
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
                final outcome = await _permissionRequester!(
                  AcpPermissionRequest(
                    sessionId: request.sessionId,
                    toolCallId: 'write:${write.hashCode}',
                    title: 'write ${write.relativePath}',
                    kind: 'edit',
                    details: JailWriteGateway.unifiedDiff(write),
                  ),
                );
                return outcome == AcpPermissionOutcome.allow;
              },
        editApprover: editApprover,
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
          final text = '$output';
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

    emit(
      AgentMessageChunk(
        content: AcpTextBlock(
          '\nverdict: ${result.passed ? "PASS" : "FAIL"} '
          '(decisions ${result.decisions}, rounds ${result.toolRounds}, '
          'tokens ${result.projectionTokens}, '
          'wall ${result.wallClock.inMilliseconds} ms, '
          'moves ${result.moves})'
          '${result.failureClass.isEmpty ? "" : "\n${result.failureClass}"}',
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
    // allow.
    final requester = _permissionRequester;
    if (requester == null) return AcpPermissionOutcome.reject;
    return requester(request);
  }

  @override
  void cancelSession(String sessionId) {
    // R7c item 4 — cancellation is REAL: the session flag aborts the loop
    // (checked per generation) and the in-flight AFM bridge generation is
    // cancelled via xs_fm_cancel (the timeout sweeper's path).
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
    _afmClient?.cancelActiveGeneration();
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
  });
  final String id;
  final String cwd;
  final SnapshotStore store;
  final ModelRouter? router;

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

  /// N4 escalation rung: the task whose budget exhausted, awaiting operator
  /// guidance. The next prompt continues it with a widened (monotonic,
  /// hard-capped) attempt allowance.
  CodingAgentTask? pendingEscalation;
  int escalationRounds = 0;
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
/// (repo_etl / meaning_zoom / meaning_impact / edit_symbol / run /
/// write_review).
///
/// READ verbs with free-text args stay bracketed prose (`[scan]`,
/// `[zoom <query>]`, `[verify]`). Every ID- or SLOT-BEARING verb travels as
/// a STRUCTURED JSON payload — `harness_edit {…}` carries the exact
/// `edit_symbol` args (action, symbolId/classSymbolId, opChain,
/// executableId, executableParams), `harness_impact {…}` the exact
/// `meaning_impact` args, `harness_zoom {…}` the exact `meaning_zoom` args
/// (incl. zoom=file, the fs-tier escape-hatch read), and `harness_fs_write
/// {path, content}` the exact `write_review` args (consent-gated). The
/// mover NEVER resolves or guesses ids — the caller supplies them from
/// zoom/impact data (the R7d division of labor); a malformed payload is
/// dropped and reported, never repaired into a guess.
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
    for (final m in RegExp(r'\[zoom ([^\]]+)\]').allMatches(prompt)) {
      calls.add(
        ToolCall(
          name: const ToolName('meaning_zoom'),
          arguments: {'query': m.group(1)!.trim(), 'zoom': 'local'},
        ),
      );
    }
    // Structured zoom args (incl. zoom=file — the fs-tier escape-hatch
    // read; ADR 0024 §4) travel verbatim, like harness_edit.
    final zooms = _payloads(prompt, 'harness_zoom');
    for (final args in zooms.items) {
      calls.add(
        ToolCall(name: const ToolName('meaning_zoom'), arguments: args),
      );
    }
    final impacts = _payloads(prompt, 'harness_impact');
    for (final args in impacts.items) {
      calls.add(
        ToolCall(name: const ToolName('meaning_impact'), arguments: args),
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
    final dropped = zooms.dropped + impacts.dropped + edits.dropped + writes.dropped;
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
