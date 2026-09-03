// ignore_for_file: lines_longer_than_80_chars

/// R6 — THE gate: a real workspace task passes `dart test` end-to-end
/// through the meaning profile with
/// - ZERO model code tokens (the actor only emits `intent_define` moves), and
/// - ZERO host-authored expectations (the table is derived from the suite).
///
/// LLM-free (scripted actor through the SAME runner an AFM actor uses).
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

/// The scripted actor: reads the DERIVED skeleton from the goal prompt and
/// fills its bounded slots with op rows — exactly what a 2–4k model does
/// (no code tokens, no file writes). Generic for two-param arithmetic
/// intents; the skeleton names come from the ETL, never from this script.
class _ScriptedMeaningActor implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    // Parse the skeleton entry from the goal prompt (the model's bounded
    // slot-filling input): `add(arg0:int, arg1:int) -> int`.
    final prompt = request.prompt;
    final m = RegExp(
      r'(\w+)\(([^)]*)\)\s*->\s*(\w+)',
    ).firstMatch(prompt);
    if (m == null) {
      throw StateError('scripted actor: no skeleton found in prompt:\n$prompt');
    }
    final intent = m.group(1)!;
    final paramNames = [
      for (final p in m.group(2)!.split(',')) p.trim().split(':').first,
    ];
    final specs = [
      for (final p in paramNames)
        {'label': 'load_arg', 'a': p},
      {'label': 'add'},
      {'label': 'return'},
    ];
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {
        'text': 'defining the derived intent $intent with specs',
      },
      rawOutput: 'defining the derived intent',
      toolCalls: [
        ToolCall(
          name: const ToolName('intent_define'),
          arguments: {
            'action': 'define',
            'name': intent,
            'params': [
              for (final p in paramNames) p,
            ],
            'returns': m.group(3),
            'specs': specs,
          },
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<Directory> _jail() async {
  final dir = await Directory.systemTemp.createTemp('ws_oracle_jail_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
name: calc_jail
environment:
  sdk: ^3.0.0
dev_dependencies:
  test: any
''');
  File(
    '${dir.path}/test/calc_test.dart',
  )
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:calc_jail/calc.dart';
import 'package:test/test.dart';
void main() {
  test('add returns the sum', () {
    expect(add(2, 3), 5);
  });
  test('add handles negatives', () {
    expect(add(-1, 1), 0);
  });
}
''');
  // NOTE: lib/calc.dart deliberately ABSENT — the task is to implement it.
  return dir;
}

void main() {
  test(
    'workspace oracle end-to-end: failing suite → derived skeleton → '
    'meaning moves → materialized Dart → dart test PASS '
    '(zero model code tokens, zero host-authored expectations)',
    () async {
    final jail = await _jail();
    addTearDown(() => jail.delete(recursive: true).catchError((_) => jail));
    final r = await runWorkspaceMeaningAgent(
      workspace: jail,
      handler: _ScriptedMeaningActor(),
      backend: 'scripted_llm_free',
    ).timeout(const Duration(minutes: 5));
    expect(
      r.passed,
      isTrue,
      reason: 'final gate: ${r.finalGateDetail}\nmoves: ${r.moves}',
    );
    // The oracle was DERIVED, never authored.
    expect(r.derivedIntents, ['add']);
    expect(r.derivedExpectationCount, 2);
    // The model's moves carry no code tokens: intent_define specs only —
    // no write move ever happened.
    expect(r.moves.keys, everyElement(isNot('write')));
    // The workspace grade is a real dart test run, and the generated file
    // is idiomatic workspace Dart (typed signature), not VM replay.
    expect(r.finalGateDetail, contains('dart test exit=0'));
    final generated = File('${jail.path}/lib/calc.dart').readAsStringSync();
    // Greenfield param names are honestly inferred (arg0/arg1 — the suite
    // literals carry no names). Idiomatic typed Dart, not VM replay.
    expect(generated, contains('int add(int arg0, int arg1)'));
    expect(generated, contains('return (arg0 + arg1);'));
    expect(r.generatedFiles.keys, contains('lib/calc.dart'));
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
