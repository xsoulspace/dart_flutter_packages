// ignore_for_file: lines_longer_than_80_chars

/// Execution as meaning (PLAN §NOW P2 / Directions item 2).
///
/// A process is a meaning — but ONLY its declaration is tree state:
///
/// - **The `run` DECLARATION is an intent node** (re-derivable): node kind
///   `'intent'` with props `{run_command, allowlist_scope}`, registered the
///   first time a run executes over a workspace (idempotent — a second run
///   of the same command template RE-USES the node).
/// - **The run OUTCOME is a BEAT** — append-only, NEVER tree state. A
///   process outcome is not re-derivable (re-deriving the tree would never
///   reproduce yesterday's exit code), so it must not lie in the tree:
///   exit code, duration and timestamp ride the existing beat channel as
///   graph events (same shape as `goal_verify` beats).
/// - **stdout/stderr are SPAN ANCHORS read BUDGETED** (like md sections):
///   output is stored in a bounded [RunSpanStore] resource keyed by the run
///   beat; [runSpanCut] serves a budgeted TAIL of it. Output NEVER enters
///   context except as a span cut — the chars cap is enforced mechanically
///   at WRITE time ([RunMeaningRecorder.spanCharBudget]) before anything is
///   stored anywhere.
/// - **Composability seam (data only, no new loop)**: a run node's props
///   may name a follow-up intent ([linkRunFollowUp] writes the
///   `follow_up_intent` prop + a `call` edge) — pipelines are intent chains
///   calling run intents. Speculative worlds branch AT RUN NODES: a
///   speculative verify actor speculates past the declaration, and any
///   branch ROLLS BACK at the next run-node boundary (outcomes are beats,
///   so rollback = dropping beats after the branch point; the tree itself
///   never recorded the outcome). The speculator itself is NOT built here —
///   the seam is named so it can land without reshaping the tree.
///
/// **Safety: the allowlist law stands — zero bypass.** Nothing in this
/// library spawns a process or decides what may run. The allowlist check
/// happens BEFORE any node/beat is written ([RunMeaningRecorder] is called
/// by the `run` tool only after `command_not_allowed` could not fire).
library;

import 'package:ecsly/ecsly.dart';

import '../data_models/components.dart' show ToolResultContent;
import '../narrative/components.dart'
    show BeatModality, BeatModalityEnum, BeatStatus, BeatStatusEnum,
    BeatToolCall, TextContent;
import '../narrative/facet_index.dart' show indexBeat;
import '../systems/projection/relevance.dart' show keywordsOf;
import 'meaning_tree.dart'
    show MeaningIndex, addMeaningNode, hasMeaningNode, linkMeaning,
    meaningComponentOf, setMeaningProp, MeaningNode, MeaningProps;

/// The mechanical chars cap for stored run output (write-time budget law).
///
/// stdout/stderr are clipped to their TAIL (the error summary lives at the
/// end) before entering the span store; [runSpanCut] can only narrow this
/// cap, never widen it. Output never enters context except as a span cut.
const defaultRunSpanCharBudget = 4000;

/// FNV-1a 32-bit — a stable, dependency-free hash so run declaration ids
/// survive process restarts (String.hashCode is not contractually stable).
int _stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

String _sanitize(String part) =>
    part.replaceAll(RegExp('[^a-zA-Z0-9]'), '_');

/// Stable, deterministic tree id for a run declaration node — derived from
/// the command template so `ensureDeclaration` is idempotent BY CONSTRUCTION
/// (same command → same id → node re-use, never a duplicate).
String runDeclarationId(List<String> command) {
  final joined = command.join(' ');
  final slug = command.map(_sanitize).join('_').replaceAll(RegExp('_+'), '_');
  final slugPart = slug.length > 40 ? slug.substring(0, 40) : slug;
  return 'run_${slugPart}_${_stableHash(joined).toRadixString(36)}';
}

/// Keep the TAIL of [s] within [max] chars (the marker counts against the
/// cap — the stored string is NEVER longer than the budget), recording
/// truncation honestly.
(String kept, int total, bool truncated) _tail(String s, int max) {
  if (s.length <= max) return (s, s.length, false);
  return ('…${s.substring(s.length - max + 1)}', s.length, true);
}

// ---------------------------------------------------------------------------
// The span store — bounded output, keyed by the run beat (NEVER tree state)
// ---------------------------------------------------------------------------

/// One bounded run output span (stdout/stderr tails). Plain data — the
/// model never reads this directly, only via [runSpanCut].
class RunOutputSpan {
  RunOutputSpan({
    required this.spanKey,
    required this.runNodeId,
    required this.exitCode,
    required this.durationMs,
    required this.timestampIso,
    required this.timedOut,
    required this.stdoutTail,
    required this.stderrTail,
    required this.stdoutTotalChars,
    required this.stderrTotalChars,
  });

  /// Stable key (`run_span_N`) — carried by the outcome beat's
  /// `ToolResultContent.output['span_key']` so beat ⇄ span linkage is data.
  final String spanKey;
  final String runNodeId;
  final int exitCode;
  final int durationMs;
  final String timestampIso;
  final bool timedOut;

  /// Write-time-tail-clipped output (each ≤ the recorder's chars budget).
  final String stdoutTail;
  final String stderrTail;

  /// Full pre-clip sizes — the green-screen truth of what was NOT stored.
  final int stdoutTotalChars;
  final int stderrTotalChars;

  bool get truncated => stdoutTotalChars > stdoutTail.length ||
      stderrTotalChars > stderrTail.length;

  Map<String, dynamic> toJson() => {
    'span_key': spanKey,
    'run_node': runNodeId,
    'exit_code': exitCode,
    'duration_ms': durationMs,
    'timestamp': timestampIso,
    if (timedOut) 'timed_out': true,
    'stdout': stdoutTail,
    'stderr': stderrTail,
    'stdout_total_chars': stdoutTotalChars,
    'stderr_total_chars': stderrTotalChars,
    if (truncated) 'truncated': true,
  };
}

/// A world RESOURCE (not tree state, not a component): the bounded span
/// store for run outputs, keyed by span key and indexed by run node.
///
/// Why a resource and not props on the run node: outcomes are not
/// re-derivable, so they must never lie in the tree (PLAN Directions item
/// 2). The store is append-only; [runSpanCut] is its only model-facing
/// reader, and it serves budgeted tails.
class RunSpanStore extends Resource {
  final Map<String, RunOutputSpan> spans = {};
  final Map<String, List<String>> _spanKeysByRunNode = {};
  int _seq = 0;

  /// Number of stored spans (all runs, all outcomes).
  int get length => spans.length;

  /// Allocates the next span key (monotonic, append-only).
  String nextKey() => 'run_span_${++_seq}';

  /// Appends a span (write-time budget already enforced by the caller).
  RunOutputSpan append(RunOutputSpan span) {
    spans[span.spanKey] = span;
    (_spanKeysByRunNode[span.runNodeId] ??= []).add(span.spanKey);
    return span;
  }

  /// Latest span for [runNodeId], or null.
  RunOutputSpan? latestFor(String runNodeId) {
    final keys = _spanKeysByRunNode[runNodeId];
    if (keys == null || keys.isEmpty) return null;
    return spans[keys.last];
  }

  /// All span keys for [runNodeId] in outcome order (append-only).
  List<String> keysFor(String runNodeId) =>
      List.unmodifiable(_spanKeysByRunNode[runNodeId] ?? const []);
}

RunSpanStore _storeOf(World world) {
  try {
    return world.getResource<RunSpanStore>();
  } on StateError {
    final store = RunSpanStore();
    world.upsertResource(store);
    world.flush();
    return store;
  }
}

// ---------------------------------------------------------------------------
// The recorder — called by the `run` tool AFTER the allowlist check passed
// ---------------------------------------------------------------------------

/// Bridges real executions into the meaning layer (PLAN Directions item 2).
///
/// The host (or a test) constructs this over a [World] and hands it to
/// `runTool(meaning: …)`. It performs exactly two writes per execution:
///
/// 1. [ensureDeclaration] — the idempotent intent node (tree state,
///    re-derivable).
/// 2. [recordOutcome] — ONE append-only beat + ONE bounded span
///    (never tree state).
///
/// SAFETY: this class never spawns anything and never gates anything. The
/// allowlist check stays in the run tool, BEFORE any node/beat write — a
/// non-allowlisted command leaves the world untouched.
class RunMeaningRecorder {
  RunMeaningRecorder(this.world, {this.spanCharBudget = defaultRunSpanCharBudget})
    : assert(spanCharBudget > 0);

  final World world;

  /// The mechanical chars cap for stored stdout/stderr tails (write-time).
  final int spanCharBudget;

  /// Registers (or re-uses) the run DECLARATION node for [command].
  ///
  /// Node: kind `'intent'`, props `{run_command: <argv>, allowlist_scope:
  /// <matched prefix>}`. Idempotent: the node id is derived from the command
  /// template ([runDeclarationId]), so a second identical run RE-USES the
  /// node. An existing node whose recorded scope differs is corrected in
  /// place (the scope is part of the re-derivable declaration, unlike the
  /// outcome). Returns the stable node id.
  String ensureDeclaration({
    required List<String> command,
    required String allowlistScope,
  }) {
    final id = runDeclarationId(command);
    if (hasMeaningNode(world, id)) {
      final entity = world.getResource<MeaningIndex>().entityOf(id)!;
      final props = meaningComponentOf<MeaningProps>(world, entity);
      if (props != null && props.props['allowlist_scope'] != allowlistScope) {
        setMeaningProp(
          world,
          id: id,
          key: 'allowlist_scope',
          value: allowlistScope,
        );
      }
      return id;
    }
    addMeaningNode(
      world,
      kind: 'intent',
      label: 'run ${command.join(' ')}',
      props: {'run_command': List<String>.of(command), 'allowlist_scope': allowlistScope},
      id: id,
    );
    return id;
  }

  /// Records ONE run outcome: declaration (idempotent) + append-only beat +
  /// bounded output span. Returns the span key.
  ///
  /// The beat rides the existing beat channel (same shape as the
  /// `goal_verify` verification beat: [BeatToolCall] + [ToolResultContent] +
  /// status/modality), threadless — a workspace-level execution is world
  /// context, not one actor's memory. stdout/stderr NEVER enter the beat or
  /// the tree: only metadata + the [RunOutputSpan.spanKey] do.
  String recordOutcome({
    required List<String> command,
    required String allowlistScope,
    required int exitCode,
    required int durationMs,
    required String stdout,
    required String stderr,
    bool timedOut = false,
  }) {
    final runNodeId = ensureDeclaration(
      command: command,
      allowlistScope: allowlistScope,
    );
    final store = _storeOf(world);
    // Write-time budget: clip BEFORE anything is stored anywhere.
    final (outTail, outTotal, _) = _tail(stdout, spanCharBudget);
    final (errTail, errTotal, _) = _tail(stderr, spanCharBudget);
    final span = store.append(
      RunOutputSpan(
        spanKey: store.nextKey(),
        runNodeId: runNodeId,
        exitCode: exitCode,
        durationMs: durationMs,
        timestampIso: DateTime.now().toUtc().toIso8601String(),
        timedOut: timedOut,
        stdoutTail: outTail,
        stderrTail: errTail,
        stdoutTotalChars: outTotal,
        stderrTotalChars: errTotal,
      ),
    );
    final summary =
        'run ${command.join(' ')}: exit=$exitCode (${durationMs}ms)'
        '${timedOut ? ' TIMEOUT' : ''}';

    final beat = world.reserveEmptyEntity().entity;
    world.getEntity(beat).$1
      ..insert(BeatToolCall('run', {'command': command, 'run_node': runNodeId}))
      ..insert(
        ToolResultContent(
          name: 'run',
          output: {
            'exit_code': exitCode,
            'duration_ms': durationMs,
            'timed_out': timedOut,
            'run_node': runNodeId,
            'span_key': span.spanKey,
          },
        ),
      )
      ..insert(TextContent(summary))
      ..insert(BeatStatus(BeatStatusEnum.complete))
      ..insert(BeatModality(BeatModalityEnum.toolCall));
    // Threadless on purpose (workspace-level execution); indexed so
    // locate/projection can ray-trace to the outcome.
    indexBeat(world, beat, keywordsOf('run outcome $summary'));
    world.flush();
    return span.spanKey;
  }
}

// ---------------------------------------------------------------------------
// Read path — the ONLY way output reaches a model: a budgeted span cut
// ---------------------------------------------------------------------------

/// A budgeted TAIL cut of the latest output span for [runNodeId] (the
/// zoom/point read seam for run output — same law as md section spans).
///
/// [maxChars] can only NARROW the budget; the write-time cap
/// ([RunMeaningRecorder.spanCharBudget]) is the hard ceiling. Returns null
/// when the run node has no recorded outcome (or does not exist).
Map<String, dynamic>? runSpanCut(
  World world,
  String runNodeId, {
  int maxChars = defaultRunSpanCharBudget,
}) {
  final span = _storeOf(world).latestFor(runNodeId);
  if (span == null) return null;
  final (out, _, _) = _tail(span.stdoutTail, maxChars);
  final (err, _, _) = _tail(span.stderrTail, maxChars);
  return {
    'run_node': span.runNodeId,
    'span_key': span.spanKey,
    'exit_code': span.exitCode,
    'duration_ms': span.durationMs,
    'timestamp': span.timestampIso,
    if (span.timedOut) 'timed_out': true,
    'stdout': out,
    'stderr': err,
    'stdout_total_chars': span.stdoutTotalChars,
    'stderr_total_chars': span.stderrTotalChars,
    'truncated': span.truncated || out.length < span.stdoutTail.length ||
        err.length < span.stderrTail.length,
  };
}

// ---------------------------------------------------------------------------
// Composability seam (data only, no new loop)
// ---------------------------------------------------------------------------

/// Names [followUpIntentId] as the run node's follow-up intent: writes the
/// `follow_up_intent` prop and a `call` edge (run node → intent node).
///
/// Pipelines are intent chains calling run intents — this is DATA ONLY: no
/// executor, no loop, no scheduling. The follow-up intent must already
/// exist (create it with [addMeaningNode]); a dangling name returns false
/// and writes nothing. Speculative worlds branch at run nodes (see the
/// library doc); the speculator is not built here.
bool linkRunFollowUp(
  World world, {
  required String runNodeId,
  required String followUpIntentId,
}) {
  final linked = linkMeaning(
    world,
    from: runNodeId,
    relation: 'call',
    to: followUpIntentId,
  );
  if (!linked) return false;
  return setMeaningProp(
    world,
    id: runNodeId,
    key: 'follow_up_intent',
    value: followUpIntentId,
  );
}

/// Whether [id] is a run declaration node in [world]'s tree (kind check for
/// hosts/tests; the model sees nodes only through budgeted cuts).
bool isRunDeclaration(World world, String id) {
  final entity = world.getResource<MeaningIndex>().entityOf(id);
  if (entity == null) return false;
  return meaningComponentOf<MeaningNode>(world, entity)?.kind == 'intent';
}
