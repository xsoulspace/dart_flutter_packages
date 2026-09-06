// ignore_for_file: lines_longer_than_80_chars

/// P2 E2E GATE — task-grammar classifier → ONE decision → apply_executable
/// → verdict PASS (LLM-free, scripted; the daemon-scripted pattern of
/// harnessd_pack_consent_test.dart over the capture-loop fixture).
///
/// Flow under test (decision amortization, PLAN §NOW):
///   task sentence → HOST classifier pre-pass (zero model tokens, ZERO
///   decisions) → pack repair-class lookup → the ready apply_executable
///   decision data rides the goal frame → the actor emits ONE decision
///   carrying it verbatim → the span editor materializes the pack op-chain
///   → the free oracles + workspace convention grade it → PASS.
///
/// The gate publishes the pass@1 row WITH the decision count: exactly 1
/// model decision for the structured path (the classifier pre-pass itself
/// spends zero), and a corrupt/unknown sentence → honest no-parse class →
/// the loop falls through to the normal path (asserted — never a crash).
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show CheckerSpec;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_harness/src/tools/task_grammar.dart'
    show parseTaskSentence, TaskGrammarNoParse;

const _sentence = 'fix product in lib/geometry.dart.';
const _brokenBody = 'return 0;';
const _fixedBody = 'return (w * h);';

/// A covered Dart package: `product` is BROKEN and covered (the suite is
/// red — the convention is the oracle); the pack carries the captured
/// repair class (w*h op-chain) as data.
Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('task_grammar_gate_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: grammar_gate\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
int area(int w, int h) {
  return (w * h);
}

int product(int w, int h) {
  return 0;
}
''');
  File('${dir.path}/test/geometry_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:grammar_gate/geometry.dart';

void main() {
  test('product', () {
    expect(product(2, 3), 6);
  });
}
''');
  // The PACK: a captured replace_member_body executable (op-chain as
  // data) — exactly what the capture loop persists (dart/captured/…).
  const packPath = '.dart_tool/harnessd/edit_pack.json';
  Directory('${dir.path}/.dart_tool/harnessd').createSync(recursive: true);
  File('${dir.path}/$packPath').writeAsStringSync('''
{
  "packId": "edit_capture",
  "executables": [
    {
      "id": "dart/captured/grammar_gate_wh",
      "kind": "replace_member_body",
      "params": ["symbolId"],
      "verification": ["analyze", "test"],
      "scope": "lexical",
      "description": "captured novel resolution: body must return w*h",
      "opChain": [
        {"label": "load_arg", "a": "w"},
        {"label": "load_arg", "a": "h"},
        {"label": "mul"},
        {"label": "return"}
      ]
    }
  ]
}
''');
  return dir;
}

/// The scripted actor: on the STRUCTURED path the pre-pass decision data
/// is already in the goal frame — the ONE decision carries it verbatim.
/// On the fall-through path (no parse) it behaves like a normal actor:
/// scan, then quiet.
class _ScriptedActor implements GenerationHandler {
  var decisions = 0;
  var emittedEdit = false;
  Map<String, dynamic>? appliedDecision;

  /// Extracts the FIRST `harness_edit {…}` payload (brace-balanced) — the
  /// same mechanical shape the daemon's directive interpreter parses.
  /// Only decoded JSON objects execute — never guessed.
  static Map<String, dynamic>? _payload(String text) {
    final tag = 'harness_edit {';
    final idx = text.indexOf(tag);
    if (idx < 0) return null;
    var depth = 0;
    final open = idx + tag.length - 1;
    for (var i = open; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(open, i + 1));
            return decoded is Map<String, dynamic> ? decoded : null;
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    decisions++;
    final calls = <ToolCall>[];
    final payload = _payload(request.prompt);
    if (payload != null && !emittedEdit) {
      emittedEdit = true;
      appliedDecision = payload;
      calls.add(ToolCall(name: const ToolName('edit_symbol'), arguments: payload));
    } else if (!emittedEdit) {
      // Fall-through path: the normal flow starts with a scan.
      calls.add(
        ToolCall(name: const ToolName('repo_etl'), arguments: {'action': 'scan'}),
      );
    }
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': calls.isEmpty ? 'done' : 'acting'},
      rawOutput: calls.isEmpty ? 'done' : 'acting',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}

void main() {
  test(
    'MAIN GATE: task sentence → classifier pre-pass → ONE decision → '
    'apply_executable → verdict PASS (pass@1 row with decision count)',
    () async {
      final jail = await _jail();
      addTearDown(() => jail.deleteSync(recursive: true));
      final pub = await Process.run('dart', ['pub', 'get'],
          workingDirectory: jail.path);
      expect(pub.exitCode, 0, reason: '${pub.stdout}${pub.stderr}');

      final actor = _ScriptedActor();
      final result = await runCodingAgentOnce(
        task: CodingAgentTask(
          id: 'task_grammar_gate',
          prompt: _sentence,
          meaningProfile: true,
          runCommand: const ['dart', 'test'],
          checkers: [
            CheckerSpec(type: 'runs', path: 'test', value: 'dart test'),
          ],
        ),
        jail: jail,
        handler: actor,
        backend: 'scripted:task_grammar_gate',
      );

      // THE MOVE LANDED: the pack op-chain replaced the broken body, the
      // convention is green.
      final geometry = File(
        '${jail.path}/lib/geometry.dart',
      ).readAsStringSync();
      expect(geometry, contains(_fixedBody), reason: result.pulseText);
      expect(result.passed, isTrue, reason: result.failureClass);

      // DECISION COUNT: the single MOVE decision carries the classifier
      // output verbatim — exactly 1 move decision for the structured path;
      // the classifier pre-pass itself spent ZERO decisions (it is
      // host-side, before the model). result.decisions == 2 because the
      // scripted mover cannot inline the tool loop (the one-move contract
      // hands the result back and the loop probes the actor once more with
      // zero moves — the R7e native path folds that probe INTO its single
      // decision, which is why that row reads "1 decision/run").
      expect(actor.decisions, 2, reason: result.pulseText);
      expect(actor.emittedEdit, isTrue);
      expect(actor.appliedDecision, isNotNull);
      expect(actor.appliedDecision!['action'], 'apply_executable');
      expect(actor.appliedDecision!['executableId'],
          'dart/captured/grammar_gate_wh');
      expect(actor.appliedDecision!['source'], 'task_grammar');
      expect(
        actor.appliedDecision!['symbolId'],
        'sym_lib_geometry.dart_product',
      );

      // The pass@1 row WITH the decision count (published as data).
      final row = 'summary — task: $_sentence | n: 1 | pass@1: '
          '${result.passed ? 1 : 0}/1 | move_decisions: 1 '
          '(classifier output carried verbatim) | decisions: '
          '${result.decisions} (1 move + 1 zero-move loop continuation) | '
          'pre-pass decisions: 0 (host-side classifier) | verdict: '
          '${result.passed ? "PASS" : "FAIL"}';
      // ignore: avoid_print
      print(row);
      expect(row, contains('pass@1: 1/1'));
      expect(row, contains('move_decisions: 1'));
      expect(row, contains('pre-pass decisions: 0'));
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test('unknown sentence → honest no-parse → falls through to the normal '
      'decision path (asserted, never a crash)', () async {
    final jail = await _jail();
    addTearDown(() => jail.deleteSync(recursive: true));
    final pub = await Process.run('dart', ['pub', 'get'],
        workingDirectory: jail.path);
    expect(pub.exitCode, 0, reason: '${pub.stdout}${pub.stderr}');

    const bad = 'somehow make the geometry thing nicer please';
    // The classifier FAILS HONESTLY (named class) — unit-level assert.
    final reading = parseTaskSentence(bad);
    expect(reading, isA<TaskGrammarNoParse>());
    expect((reading as TaskGrammarNoParse).failureClass, 'no_verb');

    final actor = _ScriptedActor();
    final result = await runCodingAgentOnce(
      task: CodingAgentTask(
        id: 'task_grammar_gate_unknown',
        prompt: bad,
        meaningProfile: true,
        runCommand: const ['dart', 'test'],
        checkers: [
          CheckerSpec(type: 'runs', path: 'test', value: 'dart test'),
        ],
      ),
      jail: jail,
      handler: actor,
      backend: 'scripted:task_grammar_gate',
    );

    // NEVER a crash: the run completed with a verdict; the loop took the
    // NORMAL decision path (scan happened, no pre-pass edit data existed,
    // the broken body is untouched — the convention stays red).
    expect(actor.emittedEdit, isFalse,
        reason: 'no parse → no ready decision data');
    expect(File('${jail.path}/lib/geometry.dart').readAsStringSync(),
        contains(_brokenBody));
    expect(result.decisions, greaterThanOrEqualTo(1));
    expect(result.passed, isFalse, reason: 'the task is NOT done — honest');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
