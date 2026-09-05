// ignore_for_file: avoid_print

/// Pipeline drift check (ADR 0026 §5) — the mechanical guard for the
/// rejection list in `pipeline_coding.md`. Exits non-zero with NAMED
/// violations when the decided layering is being re-implemented:
///
/// 1. Provider packages (`pkgs/xsoulspace_inference_*`) must not depend on
///    the harness engine in their LIBRARY code (composition-root bins may).
/// 2. Provider packages must not carry harness stress/benchmark scenarios.
/// 3. The meaning profile must not register raw `read`/`write`/`grep`/
///    `glob` tools (ADR 0023 §2 demotion).
library;

import 'dart:io';

/// Known provider-side allowances (thin composition helpers only —
/// transport code may still never import the engine).
const _allowedProviderFiles = [
  // The AFM binding helper (ADR 0025 §3): composition-root code shipped in
  // lib so apps one-line-embed. Builds a ModelRouter; no engine logic.
  'pkgs/xsoulspace_inference_apple_foundation/lib/xsoulspace_inference_apple_foundation.dart',
  // Contracts, not a provider transport.
  'pkgs/xsoulspace_inference_core',
];

const _rawToolNames = ["'read'", "'write'", "'grep'", "'glob'"];

void main() {
  final violations = <String>[];

  // 1 — provider library purity: lib/ and test/ must not import the engine.
  final pkgsDir = Directory('pkgs');
  for (final entry in pkgsDir.listSync().whereType<Directory>()) {
    final name = entry.uri.pathSegments.reversed.skip(1).first;
    if (!name.startsWith('xsoulspace_inference_')) continue;
    for (final dir in ['lib', 'test']) {
      final dirPath = '${entry.path}/$dir';
      if (!Directory(dirPath).existsSync()) continue;
      for (final f in Directory(dirPath)
          .listSync(recursive: true)
          .whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (_allowlisted(name, f.path)) continue;
        for (final line in f.readAsLinesSync()) {
          if (line.contains('package:xsoulspace_agentic_harness/')) {
            violations.add(
              'provider-library-impurity: $name imports the harness engine '
              'in $dir (${_rel(f.path)}) — ADR 0025 §4 / 0026 §2: providers '
              'are transports; the wire codec lives in inference_core',
            );
          }
        }
      }
    }
  }

  // 2 — no harness stress/benchmark scenarios in provider packages.
  for (final entry in pkgsDir.listSync().whereType<Directory>()) {
    final name = entry.uri.pathSegments.reversed.skip(1).first;
    if (!name.startsWith('xsoulspace_inference_')) continue;
    for (final suspect in ['stress', 'benchmark', 'pi_driver']) {
      final p = '${entry.path}/bin/$suspect';
      if (Directory(p).existsSync()) {
        violations.add(
          'provider-hoards-scenarios: $name/bin/$suspect — ADR 0026 §4: '
          'scenarios live in xsoulspace_agentic_harness/benchmark',
        );
      }
    }
  }

  // 3 — raw read/write back in the meaning profile (workspace + host).
  for (final pkg in [
    'pkgs/xsoulspace_agentic_workspace',
    'pkgs/xsoulspace_agentic_host',
  ]) {
    for (final f in Directory('$pkg/lib')
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final tool in _rawToolNames) {
        // A raw tool registration: name: ToolName('read') etc.
        if (src.contains('ToolName($tool)') ||
            src.contains('ToolName($tool ')) {
          violations.add(
            'raw-tool-in-meaning-profile: ToolName($tool) in '
            '${_rel(f.path)} — ADR 0023 §2 demoted read/write; use the '
            'meaning profile verbs (repo_etl/meaning_zoom/meaning_impact/'
            'edit_symbol/run)',
          );
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('pipeline drift check: CLEAN (ADR 0025/0026 seams hold)');
    return;
  }
  stderr
    ..writeln('pipeline drift check: ${violations.length} violation(s):')
    ..writeln(violations.join('\n'))
    ..writeln('\nSee pipeline_coding.md § Drift rejection list — you are '
        're-implementing a decided ADR.');
  exit(1);
}

bool _allowlisted(String pkgName, String filePath) =>
    _allowedProviderFiles.any((a) => filePath.endsWith(a));

/// Strip the pkgs/ prefix for readable output.
String _rel(String p) => p.replaceFirst('pkgs/', '');
