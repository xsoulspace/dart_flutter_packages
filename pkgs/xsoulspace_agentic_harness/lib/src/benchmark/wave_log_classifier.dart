// ignore_for_file: lines_longer_than_80_chars

/// Wave-log classifier — the repeatable, LLM-free benchmark analyzer
/// (PLAN P2: "the analyzer runs on every wave re-run; summary rows carry
/// the class split").
///
/// Parses a wave run log (`benchmark/runs/afm_wave_*_run*.log`) into
/// per-run classification rows. Recognized sections per run block:
/// the `coding_agent run — task:` header, `--- harness pulse (J1.5.3) ---`,
/// `--- flight recorder ---`, and `--- tool results (truncated per beat) ---`.
///
/// A **burned step** is any published failure beat:
/// - a tool result with `"ok":false` (or the pseudo-JSON `ok: false`
///   variant) in the tool-results section — one beat per line,
/// - a named runner beat in the pulse/recorder sections
///   (`decision_dropped`, `Error: backend_failed`) — no tool result
///   exists for these, so the pulse/recorder line IS the beat,
/// - a final-gate miss (`final gate (outer oracle, once): FAIL` in the
///   run header) — exactly one per failing run.
///
/// Recorder echoes of tool results are NEVER counted (only the
/// tool-results section is authoritative for tool beats) — this keeps
/// the count deterministic against the truncated-echo duplication.
///
/// Pure parsing: zero I/O in [classifyWaveLog] — every number comes from
/// the log text, never guessed. Anything that fails to match a named
/// class publishes as the `unparseable` class (never swallowed).
///
/// The (a)/(b) boundary is a DATA edit: [kWaveLogClasses]
/// `.mechanicallyResolvable` decides `mechanically_resolvable` vs
/// `composition_required` per class. Per the DECIDED measurement
/// (2026-09-08, `benchmark/runs/afm_wave_results.md`): 0% of failed steps
/// required model composition — the frontier resolver (repair a) covers
/// the entire measured surface; window-class failures
/// (`decision_dropped`/`backend_failed`) are also mechanically
/// resolvable (surface convergence, ADR 0030/0033);
/// `composition_required` stays 0 until a class with NO mechanical
/// repair appears and is marked `mechanicallyResolvable: false` here.
library;

/// Classification spec for one named failure class.
///
/// [mechanicallyResolvable] IS the (a)/(b) boundary as data: flipping it
/// to `false` re-routes the class to `composition_required` (repair b —
/// tier escalation) with zero code changes.
class WaveLogClassSpec {
  const WaveLogClassSpec({
    required this.patterns,
    required this.mechanicallyResolvable,
    required this.note,
  });

  /// Substrings that identify the class in a failure beat. First table
  /// entry (insertion order) with any matching pattern wins.
  final List<String> patterns;

  /// The (a)/(b) boundary — see the library doc.
  final bool mechanicallyResolvable;

  /// The NAMED mechanical repair (or why none exists today).
  final String note;
}

/// The class table — the (a)/(b) boundary lives HERE, not in code logic.
///
/// Order matters: it is the tie-break order for the per-run failure class.
const Map<String, WaveLogClassSpec> kWaveLogClasses = {
  'unknown_id': WaveLogClassSpec(
    patterns: ['unknown focusId', 'unknown symbol id', 'no_focus'],
    mechanicallyResolvable: true,
    note:
        'invented/missing focus or symbol id — the frontier resolver '
        '(repair a) resolves prompt-named ids mechanically and every '
        'bounce carries candidate ids (locate-hints law)',
  ),
  'unknown_op': WaveLogClassSpec(
    patterns: ['unknown_op'],
    mechanicallyResolvable: true,
    note:
        'program op outside the closed set — the bounce teaches the '
        'closed vocabulary; the ready decision carries a legal op',
  ),
  'tree_state': WaveLogClassSpec(
    patterns: ['tree_empty', 'tree already built'],
    mechanicallyResolvable: true,
    note:
        'read on an empty/stale tree — scan is an idempotent ensure '
        'and reconcile covers refresh mechanically',
  ),
  'slot_scoping': WaveLogClassSpec(
    patterns: ['slot_scoping', 'slots are ACTION-SCOPED'],
    mechanicallyResolvable: true,
    note:
        'action-scoped slot misuse — compose opChain over the closed '
        'vocabulary (the host compiles it); a data-shaped repair',
  ),
  'command_not_allowed': WaveLogClassSpec(
    patterns: ['command_not_allowed'],
    mechanicallyResolvable: true,
    note:
        'surface runs only the workspace-convention commands — file '
        'mutation goes through the edit verbs (named in the hint)',
  ),
  'tool_args_invalid': WaveLogClassSpec(
    patterns: ['tool_args_invalid'],
    mechanicallyResolvable: true,
    note:
        'schema-invalid call bounced as named data (P1 fix) — a named '
        'beat with required slots, never a same-cut retry',
  ),
  'program_bounce': WaveLogClassSpec(
    patterns: ['"bounce":true'],
    mechanicallyResolvable: true,
    note:
        'generic edit/program bounce carrying a named repair hint '
        '(e.g. "append {label: return}") — the bounce ladder teaches '
        'mechanically; specific classes above match first',
  ),
  'decision_dropped': WaveLogClassSpec(
    patterns: ['decision_dropped'],
    mechanicallyResolvable: true,
    note:
        'window-class drop (ADR 0033) — surface convergence (ADR 0030 '
        'profile shrink) is the named repair; attempts unburned',
  ),
  'backend_failed': WaveLogClassSpec(
    patterns: ['backend_failed'],
    mechanicallyResolvable: true,
    note:
        'legacy window-class "tighter context" retry loop (pre-0033 '
        'shape) — superseded by decision_dropped; same surface repair',
  ),
  'final_gate_miss': WaveLogClassSpec(
    patterns: ['final gate'],
    mechanicallyResolvable: true,
    note:
        'row-level outer-oracle miss — every observed instance traced '
        'to mechanically resolvable upstream classes (early-stop or '
        'read-side id composition, per the DECIDED audit)',
  ),
  'verify_fail': WaveLogClassSpec(
    patterns: ['verify_wall_ms', 'run failed exit='],
    mechanicallyResolvable: true,
    note:
        'step-level verify beat failed (test/analyze exit != 0) — the '
        'failing command output feeds the attempt ladder as data',
  ),
  'unparseable': WaveLogClassSpec(
    patterns: [],
    mechanicallyResolvable: false,
    note:
        'a published failure beat matching NO named pattern — '
        'conservative: counts composition_required until it is named '
        'here (parse failures are data, never swallowed)',
  ),
};

/// Classification rows for one wave run log (which may contain several
/// run blocks).
class WaveLogReport {
  const WaveLogReport({required this.runs, required this.classes});

  /// One row per `coding_agent run — task:` block, in log order.
  final List<WaveRunRow> runs;

  /// Merged class counts across all runs.
  final Map<String, int> classes;

  int get burnedSteps => runs.fold(0, (sum, r) => sum + r.burnedSteps);
  int get mechanicallyResolvable =>
      runs.fold(0, (sum, r) => sum + r.mechanicallyResolvable);
  int get compositionRequired =>
      runs.fold(0, (sum, r) => sum + r.compositionRequired);

  /// JSON-encodable summary row for the wave driver / ledger.
  Map<String, Object?> toSummary() => <String, Object?>{
    'burned_steps': burnedSteps,
    'mechanically_resolvable': mechanicallyResolvable,
    'composition_required': compositionRequired,
    'classes': Map<String, int>.of(classes),
    'runs': runs.map((r) => r.toSummary()).toList(),
  };
}

/// Per-run classification row.
class WaveRunRow {
  const WaveRunRow({
    required this.runIndex,
    required this.task,
    required this.verdict,
    required this.gateFailed,
    required this.classes,
  });

  /// 1-based position of the run block within the log.
  final int runIndex;

  /// Task name from the `coding_agent run — task:` header.
  final String task;

  /// Header `verdict:` value, if published.
  final String? verdict;

  /// Whether the header published `final gate (outer oracle, once): FAIL`.
  final bool gateFailed;

  /// Class name → burned-step count for this run.
  final Map<String, int> classes;

  int get burnedSteps => classes.values.fold(0, (sum, n) => sum + n);

  int get mechanicallyResolvable {
    var sum = 0;
    classes.forEach((name, n) {
      final spec = kWaveLogClasses[name];
      if (spec != null && spec.mechanicallyResolvable) sum += n;
    });
    return sum;
  }

  int get compositionRequired => burnedSteps - mechanicallyResolvable;

  /// Derived run-level failure class — deterministic, data-driven:
  /// - `clean`: nothing burned and the gate did not fail,
  /// - `early_stop`: the gate failed but NOTHING else burned (the model
  ///   stopped before engaging — the published md/yaml class),
  /// - otherwise the most frequent burned class (ties broken by
  ///   [kWaveLogClasses] table order).
  String get failureClass {
    final nonGate = Map<String, int>.of(classes)..remove('final_gate_miss');
    if (nonGate.isEmpty) {
      return gateFailed ? 'early_stop' : 'clean';
    }
    var best = 'unparseable';
    var bestCount = 0;
    for (final name in kWaveLogClasses.keys) {
      final n = nonGate[name] ?? 0;
      if (n > bestCount) {
        best = name;
        bestCount = n;
      }
    }
    return best;
  }

  /// JSON-encodable summary row.
  Map<String, Object?> toSummary() => <String, Object?>{
    'run': runIndex,
    'task': task,
    'verdict': verdict,
    'gate_failed': gateFailed,
    'burned_steps': burnedSteps,
    'mechanically_resolvable': mechanicallyResolvable,
    'composition_required': compositionRequired,
    'failure_class': failureClass,
    'classes': Map<String, int>.of(classes),
  };
}

/// Parse a wave run log (the full text of one `afm_wave_*.log` file).
WaveLogReport classifyWaveLog(String log) {
  final lines = log.split('\n');
  final rows = <WaveRunRow>[];
  var blockStart = -1;
  for (var i = 0; i < lines.length; i++) {
    if (!_isRunHeader(lines[i])) continue;
    if (blockStart >= 0) {
      rows.add(_parseRun(lines.sublist(blockStart, i), rows.length + 1));
    }
    blockStart = i;
  }
  if (blockStart >= 0) {
    rows.add(_parseRun(lines.sublist(blockStart), rows.length + 1));
  }
  final merged = <String, int>{};
  for (final row in rows) {
    row.classes.forEach((name, n) {
      merged[name] = (merged[name] ?? 0) + n;
    });
  }
  return WaveLogReport(runs: rows, classes: merged);
}

bool _isRunHeader(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('coding_agent run') && trimmed.contains('task:');
}

WaveRunRow _parseRun(List<String> block, int runIndex) {
  // Header: the task name lives on the first line after `task:`.
  var task = '(unnamed)';
  final first = block.first;
  final taskIdx = first.indexOf('task:');
  if (taskIdx >= 0 && first.substring(taskIdx + 5).trim().isNotEmpty) {
    task = first.substring(taskIdx + 5).trim();
  }

  String? verdict;
  var gateFailed = false;
  final classes = <String, int>{};

  void burn(String className) {
    classes[className] = (classes[className] ?? 0) + 1;
  }

  // 0 = header, 1 = pulse, 2 = recorder, 3 = tool results.
  var section = 0;
  for (var i = 0; i < block.length; i++) {
    final line = block[i];
    if (line.startsWith('--- harness pulse')) {
      section = 1;
      continue;
    } else if (line.startsWith('--- flight recorder')) {
      section = 2;
      continue;
    } else if (line.startsWith('--- tool results')) {
      section = 3;
      continue;
    }
    if (section == 0) {
      final trimmed = line.trim();
      if (trimmed.startsWith('verdict:')) {
        verdict = trimmed.substring('verdict:'.length).trim();
      } else {
        const gateMarker = 'final gate (outer oracle, once): ';
        final gateIdx = line.indexOf(gateMarker);
        if (gateIdx >= 0) {
          gateFailed =
              line.substring(gateIdx + gateMarker.length).trim() == 'FAIL';
          if (gateFailed) burn('final_gate_miss');
        }
      }
    } else if (section == 1 || section == 2) {
      // Named runner beats: no tool result exists for a dropped
      // decision or a failed generation, so this line IS the beat.
      // (Tool-result echoes live in the recorder but are counted only
      // from section 3 — never here.)
      if (line.contains('decision_dropped')) burn('decision_dropped');
      if (line.contains('Error: backend_failed')) burn('backend_failed');
    } else if (section == 3) {
      final beat = _parseToolBeat(line);
      if (beat == null) continue; // continuation / ok:true / no verdict
      burn(_classifyBeat(beat));
    }
  }
  return WaveRunRow(
    runIndex: runIndex,
    task: task,
    verdict: verdict,
    gateFailed: gateFailed,
    classes: classes,
  );
}

/// The failed-tool-result content of a beat line, or null when the line
/// is not a burned beat (continuation line, or the beat's top-level
/// verdict is ok).
String? _parseToolBeat(String line) {
  final match = _toolPrefix.firstMatch(line);
  if (match == null) return null;
  // The TOP-LEVEL verdict is the FIRST ok occurrence in the line —
  // nested op results may be ok while the program halted (and vice
  // versa), so earliest index wins.
  final jsonOk = _jsonOk.firstMatch(line);
  final pseudoOk = _pseudoOk.firstMatch(line);
  Match? earliest;
  if (jsonOk != null && pseudoOk != null) {
    earliest = jsonOk.start <= pseudoOk.start ? jsonOk : pseudoOk;
  } else {
    earliest = jsonOk ?? pseudoOk;
  }
  if (earliest == null) return null;
  final value = earliest.group(1);
  if (value != 'false') return null;
  return line.substring(match.end);
}

final RegExp _toolPrefix = RegExp(r'^[A-Za-z0-9_.\-]+:\s');
final RegExp _jsonOk = RegExp(r'"ok"\s*:\s*(true|false)');
final RegExp _pseudoOk = RegExp(r'\bok:\s*(true|false)');

String _classifyBeat(String content) {
  for (final entry in kWaveLogClasses.entries) {
    for (final pattern in entry.value.patterns) {
      if (content.contains(pattern)) return entry.key;
    }
  }
  return 'unparseable';
}
