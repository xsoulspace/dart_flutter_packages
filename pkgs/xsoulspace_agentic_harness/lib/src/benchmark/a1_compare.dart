// ignore_for_file: avoid_print

/// Builds the A1 fair-comparison artifact from harness+OR and pi+OR JSONL.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  String? harnessPath;
  String? piPath;
  String? outPath;
  var model = 'unknown';
  for (var i = 0; i < args.length; i += 2) {
    switch (args[i]) {
      case '--harness':
        harnessPath = args[i + 1];
      case '--pi':
        piPath = args[i + 1];
      case '--out':
        outPath = args[i + 1];
      case '--model':
        model = args[i + 1];
    }
  }
  if (harnessPath == null || piPath == null || outPath == null) {
    stderr.writeln(
      'usage: a1_compare.dart --harness <jsonl> --pi <jsonl> '
      '--model <id> --out <md>',
    );
    exit(64);
  }

  final harness = _readJsonl(harnessPath);
  final pi = _readJsonl(piPath);
  final byTask = <String, (Map<String, dynamic>?, Map<String, dynamic>?)>{};
  for (final row in harness) {
    byTask[row['task_id'] as String] = (row, byTask[row['task_id']]?.$2);
  }
  for (final row in pi) {
    byTask[row['task_id'] as String] = (byTask[row['task_id']]?.$1, row);
  }

  int passes(List<Map<String, dynamic>> rows) =>
      rows.where((r) => r['passed'] == true).length;
  int sumOf(
    List<Map<String, dynamic>> rows,
    String key,
  ) => rows.fold(0, (sum, r) {
    final value = r[key];
    if (value is num) return sum + value.toInt();
    if (value is Map<String, dynamic>) {
      final total = value['total'];
      if (total is num) return sum + total.toInt();
    }
    return sum;
  });

  final hPass = passes(harness);
  final pPass = passes(pi);
  final hTokens = sumOf(harness, 'cumulative_tokens');
  final pTokens = sumOf(pi, 'token_usage');
  final hWall = sumOf(harness, 'wall_clock_ms');
  final pWall = sumOf(pi, 'wall_clock_ms');

  String pct(int part, int total) =>
      total == 0 ? 'n/a' : '${(part / total * 100).toStringAsFixed(0)}%';

  final b = StringBuffer()
    ..writeln('# A1 Fair Comparison — harness vs pi (same model via OpenRouter)')
    ..writeln()
    ..writeln('- Model: `$model`')
    ..writeln('- Harness decision path: guided schema '
        '(`StructuredToolDecisionHandler`)')
    ..writeln('- pi decision path: native loop (`createAgentSession()`)')
    ..writeln('- Harness tokens: cumulative projection size per decision.')
    ..writeln('- pi tokens: real SDK usage (input+output+cache), asserted '
        'non-null by the driver.')
    ..writeln('- Retry parity: both columns get up to 2 checker-feedback '
        'rounds.')
    ..writeln()
    ..writeln('| task | harness pass | pi pass | harness cum tok | pi tok |')
    ..writeln('|---|---|---|---|---|');
  for (final entry in byTask.entries) {
    final h = entry.value.$1;
    final p = entry.value.$2;
    int? hTok;
    if (h?['cumulative_tokens'] is num) {
      hTok = (h!['cumulative_tokens'] as num).toInt();
    }
    int? pTok;
    if (p?['token_usage'] is Map<String, dynamic>) {
      final total = (p!['token_usage'] as Map<String, dynamic>)['total'];
      if (total is num) pTok = total.toInt();
    }
    b.writeln(
      '| ${entry.key} '
      '| ${h == null ? '—' : h['passed'] == true ? '✅' : '❌'} '
      '| ${p == null ? '—' : p['passed'] == true ? '✅' : '❌'} '
      '| ${hTok ?? '—'} | ${pTok ?? '—'} |',
    );
  }
  b
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| metric | harness+OR | pi+OR |')
    ..writeln('|---|---|---|')
    ..writeln('| pass rate | $hPass/${harness.length} (${pct(hPass, harness.length)}) '
        '| $pPass/${pi.length} (${pct(pPass, pi.length)}) |')
    ..writeln('| total tokens | $hTokens | $pTokens |')
    ..writeln('| wall clock | ${Duration(milliseconds: hWall)} | '
        '${Duration(milliseconds: pWall)} |')
    ..writeln()
    ..writeln('Failures remain data; failure modes live in the source JSONL.');

  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(b.toString());
  print('Wrote $outPath');
}

List<Map<String, dynamic>> _readJsonl(String path) => const LineSplitter()
    .convert(File(path).readAsStringSync())
    .where((line) => line.trim().isNotEmpty)
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();
