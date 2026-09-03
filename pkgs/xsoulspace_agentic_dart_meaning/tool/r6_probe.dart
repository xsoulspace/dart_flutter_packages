import 'dart:io';
import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_dart_meaning/xsoulspace_agentic_dart_meaning.dart';

class ScriptedActor implements GenerationHandler {
  @override
  Future<ActorGenerateResponse> generate(World world, ActorGenerateRequest request) async {
    final m = RegExp(r'(\w+)\(([^)]*)\)\s*->\s*(\w+)').firstMatch(request.prompt)!;
    final intent = m.group(1)!;
    final paramNames = [for (final p in m.group(2)!.split(',')) p.trim().split(':').first];
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'defining $intent'},
      rawOutput: 'defining $intent',
      toolCalls: [
        ToolCall(
          name: const ToolName('intent_define'),
          arguments: {
            'action': 'define', 'name': intent,
            'params': paramNames, 'returns': m.group(3),
            'specs': [
              for (final p in paramNames) {'label': 'load_arg', 'a': p},
              {'label': 'add'},
              {'label': 'return'},
            ],
          },
        ),
      ],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('r6_probe_');
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: calc_jail\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n');
  File('${dir.path}/test/calc_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("import 'package:calc_jail/calc.dart';\nimport 'package:test/test.dart';\nvoid main() {\n  test('add returns the sum', () { expect(add(2, 3), 5); });\n  test('add handles negatives', () { expect(add(-1, 1), 0); });\n}\n");
  final r = await runWorkspaceMeaningAgent(
    workspace: dir, handler: ScriptedActor(), backend: 'scripted_llm_free');
  print('PASSED: ${r.passed}');
  print('decisions: ${r.decisions} | projectionTokens: ${r.projectionTokens} | toolRounds: ${r.toolRounds}');
  print('moves: ${r.moves}');
  print('derived: ${r.derivedIntents} expectations: ${r.derivedExpectationCount}');
  print('wall: ${r.wallClock.inMilliseconds} ms');
  print('gate: ${r.finalGateDetail.split('\n').first}');
  await dir.delete(recursive: true);
}
