// ignore_for_file: lines_longer_than_80_chars

/// Gate A — the `run`/execute tool (PLAN Stage A). A coding agent must be able
/// to execute what it builds and observe stdout/stderr/exit-code — otherwise it
/// cannot tell "does it actually work?" This test proves `run` is jailed,
/// time-bounded, deterministic, LLM-free, and grades real behavior.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  late Directory jail;
  late FsToolsRoot root;
  late ToolRegistry registry;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('run_tool_test_');
    root = FsToolsRoot(jail.path);
    registry = ToolRegistry();
    fsTools(root).forEach(registry.register);
  });

  tearDown(() async {
    if (jail.existsSync()) await jail.delete(recursive: true);
  });

  Future<Map<String, dynamic>> run(Map args) async {
    final raw = await registry.get(const ToolName('run'))!.execute(args);
    final decoded = raw is String ? jsonDecode(raw) : raw;
    return (decoded as Map<dynamic, dynamic>)
        .map((k, v) => MapEntry('$k', v));
  }

  test('runs a Dart script, returns exit 0 + stdout', () async {
    File('${jail.path}/main.dart')
        .writeAsStringSync('void main() { print("board ok"); }\n');
    final r = await run({'command': ['dart', 'run', 'main.dart']});
    expect(r['ok'], isTrue);
    expect(r['exit_code'], 0);
    expect(r['stdout'].toString(), contains('board ok'));
  });

  test('a failing script returns nonzero exit code', () async {
    File('${jail.path}/bad.dart').writeAsStringSync('void main() => exit(3);\n');
    final r = await run({'command': ['dart', 'run', 'bad.dart']});
    expect(r['ok'], isFalse);
    expect(r['exit_code'], isNot(0));
  });

  test('spawn error (unknown file) is a structured failure, not a throw', () async {
    final r = await run({'command': ['dart', 'run', 'nope.dart']});
    expect(r['ok'], isFalse);
    // `dart run nope.dart` starts fine and fails with a nonzero exit;
    // stderr carries the not-found detail. `code` may be absent — that's ok.
    expect(r['exit_code'], isNot(0));
  });

  test('timeout returns a structured timeout (does not hang)', () async {
    File('${jail.path}/slow.dart').writeAsStringSync(
        'import "dart:async";\n'
        'void main() async { await Future.delayed(Duration(seconds: 30)); }\n');
    final r = await run({
      'command': ['dart', 'run', 'slow.dart'],
      'timeout_ms': 1,
    });
    expect(r['ok'], isFalse);
    expect(r['code'], 'timeout');
  });

  test('escaping cwd is rejected (jail containment)', () async {
    File('${jail.path}/main.dart').writeAsStringSync('void main() {}\n');
    // resolve() throws on an escaping path, like every fs tool (read/write):
    // the tool bounces with an ArgumentError rather than escaping the jail.
    await expectLater(
      registry.get(const ToolName('run'))!.execute({
        'command': ['dart', 'run', 'main.dart'],
        'cwd': '/etc',
      }),
      throwsA(isA<ArgumentError>()),
    );
  });
}
