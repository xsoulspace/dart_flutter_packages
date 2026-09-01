// ignore_for_file: avoid_print, lines_longer_than_80_chars

/// Tool-efficiency profiler — run the harness tools through a deterministic
/// sequence and get a per-tool efficiency report (first-use, in-sequence
/// reuse, cost per call, failure streaks).
///
/// ```sh
/// dart run bin/tool_eval_profile.dart
/// ```
///
/// Measures every fs/discovery/edit tool in one scripted episode. This is the
/// "reliably measure tool efficiency" surface (ADR 0014/0015): embed your own
/// registry and run any sequence; the report ranks which descriptions/shapes
/// to simplify by measurement, not intuition.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/observation/tool_metrics.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> main() async {
  final jail = await Directory.systemTemp.createTemp('tool_eval_');
  final root = FsToolsRoot(jail.path);

  // Seed a small workspace.
  final write = {
    'lib/util.dart': 'String greet(String who) => "hi \$who";\n',
    'lib/app.dart': "import 'util.dart';\nfinal m = greet('bob');\n",
    'lib/other.dart': 'void unused() {}\n',
  };
  for (final e in write.entries) {
    final f = File('${jail.path}/${e.key}');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(e.value);
  }

  final base = ToolRegistry();
  fsTools(root).forEach(base.register);
  final ledger = ToolMetricsLedger();
  final registry = instrumentRegistry(base, ledger);

  // A deterministic "agent" sequence: discover, read, grep, fail once, list,
  // write. Includes a deliberate failure (missing file) so the failure-streak
  // / error-code columns are exercised. (The legacy rename_symbol tool was
  // hard-cut; rename flows go through the meaning pipeline.)
  Future<void> call(String name, Map args) {
    final coerced = args.map((k, v) => MapEntry(k.toString(), v));
    return registry.get(ToolName(name))!.execute(coerced);
  }

  await call('glob', {'pattern': '**/*.dart'});
  await call('read', {'path': 'lib/util.dart'});
  await call('grep', {'pattern': 'greet'});
  try {
    await call('read', {'path': 'does_not_exist.dart'}); // deliberate fail
  } on Object {
    // deliberate fail (missing path)
  }
  await call('list_dir', {'path': '.'});
  await call('write', {'path': 'lib/notes.txt', 'content': 'done'});

  final report = analyzeTools(ledger);
  print('Tool efficiency report — ${ledger.calls.length} calls, ${ledger.calls.length} tools exercised');
  print(report.toMarkdown());

  // Serialize the ledger for EV: raw rows (cost per call) and analyzed report.
  final summary = {
    'calls': ledger.calls.length,
    'total_tokens_chars': ledger.calls.fold(0, (a, c) => a + c.totalChars),
    'tools': [
      for (final t in report.tools)
        {
          'tool': t.name,
          'first_ok': t.firstUseOk,
          'success_rate': (t.successRate * 100).toStringAsFixed(0),
          'avg_chars': t.avgChars,
          'avg_ms': t.avgMs,
          'calls': t.total,
          'failures': t.failCount,
          'max_failure_streak': t.maxFailureStreak,
        },
    ],
  };
  print('json: ${jsonEncode(summary)}');

  if (jail.existsSync()) await jail.delete(recursive: true);
}