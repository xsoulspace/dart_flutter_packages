// ignore_for_file: lines_longer_than_80_chars

/// Tool efficiency measurement (ADR 0014 follow-up) — reliably measure how
/// tools behave: first-use, in-sequence reuse, cost per call, and long-term
/// reliability.
///
/// The seam is a **measuring wrapper over a [ToolRegistry]**. Every tool call
/// — native or guided — funnels through the registry, so wrapping it here
/// captures 100% of calls with zero world changes. Each call records
/// (name, sequence index, first-use flag, success, error code, arg/result
/// size, latency) into a [ToolMetricsLedger]; [analyzeTools] then produces an
/// efficiency report answering, per tool:
///
/// - **cost**: chars billed per call (arg+result ≈ tokens) and latency;
/// - **first use**: works on the first-ever call or stumbles;
/// - **reuse**: after a first success, reuse stays reliable or drifts;
/// - **sequence**: what leads into this tool, and does the agent alternate /
///   loop (a proxy for a confusing surface);
/// - **long-term**: max failure streak as calls grow (drift).
///
/// Embedding is domain-agnostic (ADR 0015): a host wraps its registry the
/// same way and reads its own report.
library;

import 'dart:convert';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ToolDef, ToolRegistry;

/// One measured tool call.
class ToolCallRecord {
  ToolCallRecord({
    required this.seq,
    required this.tool,
    required this.isFirstUse,
    required this.ok,
    required this.latencyMs,
    required this.argChars,
    required this.resultChars,
    this.errorCode,
  });

  final int seq;
  final String tool;

  /// True if this was the first call to [tool] in the measured episode.
  final bool isFirstUse;
  final bool ok;
  final int latencyMs;
  final int argChars;

  /// Size of the structured result the model saw.
  final int resultChars;
  final String? errorCode;

  /// Chars billed for this call (arg+result ≈ prompt+generated tokens).
  int get totalChars => argChars + resultChars;
}

extension on List<ToolCallRecord> {
  ToolCallRecord? get firstOrNull => isEmpty ? null : first;
}

/// Append-only ledger of measured calls. Cheap; always attach.
class ToolMetricsLedger {
  final List<ToolCallRecord> calls = [];
  int _seq = 0;
  final Set<String> _seenTools = {};

  void record(ToolCallRecord r) {
    _seenTools.add(r.tool);
    calls.add(r);
  }

  int nextSeq() => _seq++;

  bool isFirstUseOf(String tool) => _seenTools.add(tool);
  bool get isEmpty => calls.isEmpty;
  int get length => calls.length;
}

/// Wrap [ToolDef] so every execution is recorded into [ledger], returning a
/// tool that behaves identically but writes a [ToolCallRecord] first.
ToolDef instrumentTool(ToolDef tool, ToolMetricsLedger ledger) => ToolDef(
  name: tool.name,
  description: tool.description,
  argsSchema: tool.argsSchema,
  execute: (args) async {
    final sw = Stopwatch()..start();
    final firstUse = ledger.isFirstUseOf(tool.name.value);
    final argStr = args is String ? args : _encode(args);
    String? err;
    dynamic value;
    try {
      value = await tool.execute(args);
    } on Object catch (e) {
      err = '$e';
    }
    final result = value is String
        ? value
        : (value == null ? '' : _encode(value));
    // A tool "fails" if it threw OR returned a structured error, so
    // first-use-ok / success-rate stay honest about tools that report failure
    // through their result shape (e.g. {'ok': false, 'code': ...}).
    final structuredCode = err == null ? _errorCode(result) : null;
    final failed = err != null || structuredCode != null;
    final code = err != null
        ? 'exception: $err'
        : structuredCode;
    ledger.record(
      ToolCallRecord(
        seq: ledger.nextSeq(),
        tool: tool.name.value,
        isFirstUse: firstUse,
        ok: !failed,
        latencyMs: sw.elapsedMilliseconds,
        argChars: argStr.length,
        resultChars: result.length,
        errorCode: code,
      ),
    );
    if (err != null) throw _ToolInstrumentationError(err);
    return value;
  },
);

String _encode(Object? v) => v is String ? v : jsonEncode(v);

/// Pull a structured `code` (e.g. `anchor_not_unique`) from a result, if any.
String? _errorCode(String result) {
  try {
    final m = jsonDecode(result);
    if (m is Map && m['code'] is String) return m['code'] as String;
  } on FormatException {
    // non-JSON
  }
  return null;
}

class _ToolInstrumentationError implements Exception {
  _ToolInstrumentationError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Wrap a whole registry so every registered tool is measured.
///
/// Hand this to the harness (`register('default', wrapped)`) to capture a full
/// episode's tool calls with no app changes.
ToolRegistry instrumentRegistry(ToolRegistry registry, ToolMetricsLedger ledger) {
  final out = ToolRegistry();
  for (final entry in registry.tools.entries) {
    out.register(instrumentTool(entry.value, ledger));
  }
  return out;
}

/// Stat for one tool over a measured episode.
class ToolStat {
  ToolStat({required this.name, required this.calls});
  final String name;
  final List<ToolCallRecord> calls;

  int get total => calls.length;
  int get okCount => calls.where((c) => c.ok).length;
  int get failCount => total - okCount;
  double get successRate => total == 0 ? 0 : okCount / total;

  /// Does the tool succeed on its first-ever call?
  bool get firstUseOk => calls.firstOrNull?.ok ?? false;

  /// Average call cost in chars (arg+result ≈ prompt+generated).
  int get avgChars => total == 0
      ? 0
      : calls.fold<int>(0, (a, c) => a + c.totalChars) ~/ total;

  /// Average latency in ms.
  int get avgMs => total == 0
      ? 0
      : calls.fold<int>(0, (a, c) => a + c.latencyMs) ~/ total;

  /// Longest consecutive-failure streak (drift signal if high).
  int get maxFailureStreak {
    var cur = 0;
    var best = 0;
    for (final c in calls) {
      if (c.ok) {
        cur = 0;
      } else {
        cur++;
        if (cur > best) best = cur;
      }
    }
    return best;
  }
}

/// Where a tool appears in the call sequence (rank ordering).
class ToolPositionStat {
  ToolPositionStat(this.name, this.sequencePositions);
  final String name;
  final List<int> sequencePositions;
  int get firstCallAt => sequencePositions.isEmpty ? -1 : sequencePositions.first;
  int get lastCallAt => sequencePositions.isEmpty ? -1 : sequencePositions.last;
  int get totalUses => sequencePositions.length;
}

/// Report over a measured episode.
class ToolEfficiencyReport {
  ToolEfficiencyReport({required this.tools, required this.positions, required this.transitions});
  final List<ToolStat> tools;
  final List<ToolPositionStat> positions;
  final Map<String, Map<String, int>> transitions; // prev_tool → next_tool counts

  ToolStat? stat(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  String toMarkdown() {
    final b = StringBuffer()..writeln('| tool | first-ok | success | cost | latency | calls | fails | drift |');
    b.writeln('|---|---|---|---|---|---|---|---|');
    for (final t in tools) {
      b.writeln(
        '| ${t.name} | ${t.firstUseOk ? '✅' : '❌'} | '
        '${(t.successRate * 100).toStringAsFixed(0)}% | '
        '${t.avgChars} | ${t.avgMs}ms | ${t.calls.length} | '
        '${t.failCount} | ${t.maxFailureStreak} |',
      );
    }
    b.writeln();
    if (positions.isNotEmpty) {
      b.writeln('First-use → last-use sequence ranks:');
      for (final p in positions) {
        b.writeln('  ${p.name}: first@${p.firstCallAt} last@${p.lastCallAt} (${p.totalUses})');
      }
    }
    if (transitions.isNotEmpty) {
      final rankedTypes = transitions.entries.toList()
        ..sort((a, b) => a.value.values.fold(0, (s, v) => s + v)
            .compareTo(b.value.values.fold(0, (s, v) => s + v)));
      b.writeln('In-sequence transitions (most common):');
      for (final e in rankedTypes.take(6)) {
        final pairs = e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final top = pairs.take(2).map((p) => '${p.key}×${p.value}').join(', ');
        b.writeln('  ${e.key} → $top');
      }
    }
    return b.toString();
  }
}

/// Analyze a measured [ledger] into a [ToolEfficiencyReport].
ToolEfficiencyReport analyzeTools(ToolMetricsLedger ledger) {
  final byName = <String, List<ToolCallRecord>>{};
  final positions = <String, List<int>>{};
  final transitions = <String, Map<String, int>>{};
  ToolCallRecord? prev;
  for (final c in ledger.calls) {
    (byName[c.tool] ??= []).add(c);
    (positions[c.tool] ??= []).add(c.seq);
    if (prev != null && prev.tool != c.tool) {
      (transitions[prev.tool] ??= {})[c.tool] =
          ((transitions[prev.tool] ??= {})[c.tool] ?? 0) + 1;
    }
    prev = c;
  }
  final tools = <ToolStat>[];
  final names = byName.keys.toList()
    ..sort((a, b) => (positions[a]?.first ?? 1 << 30)
        .compareTo(positions[b]?.first ?? 1 << 30));
  for (final n in names) {
    tools.add(ToolStat(name: n, calls: byName[n]!));
  }
  return ToolEfficiencyReport(
    tools: tools,
    positions: [
      for (final e in positions.entries) ToolPositionStat(e.key, e.value),
    ],
    transitions: transitions,
  );
}
