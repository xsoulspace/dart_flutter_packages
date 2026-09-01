// ignore_for_file: lines_longer_than_80_chars

/// Integration: the loop breaker must stop a runaway ReAct loop inside the
/// real CodingSuiteRunner (scripted, no backend) after teach + escalate.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/benchmark_api.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

/// Emits the SAME failing tool call on every turn — the degenerate echo
/// attractor observed on edit_01 (guided arm). (The legacy patch_file tool
/// was hard-cut, B4; the echo vehicle is now a `read` of a missing file,
/// which fails with a structured error every round.)
class EchoLoopHandler implements GenerationHandler {
  static const call = ToolCall(
    name: ToolName('read'),
    arguments: {
      'path': 'missing.dart',
    },
  );

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'patch'},
      rawOutput: 'patch',
      toolCalls: const [call],
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

void main() {
  test(
    'suite integration: identical failing calls stop after teach+escalate',
    () async {
      final task = CodingTask(
        id: 'loop_integration',
        category: TaskCategory.fileEdit,
        prompt: 'rename MAX_USERS',
        fixtures: [
          FixtureFile(path: 'config.dart', content: 'const MAX_USERS = 10;'),
        ],
        checkers: [
          CheckerSpec(
            type: 'contains',
            path: 'config.dart',
            values: ['maxUserLimit'],
          ),
        ],
      );
      final runner = CodingSuiteRunner(
        buildHandler: (_) => EchoLoopHandler(),
        backendLabel: 'loop-integration',
        extraTools: [(root) => readTool(FsToolsRoot(root))],
      );
      final result = await runner.runAll([task]);
      final r = result.results.single;
      // Without the breaker this runs to maxToolRounds (16) + retries.
      expect(
        r.llmCalls,
        lessThanOrEqualTo(6),
        reason:
            'tier-3 must stop the echo loop well before the round budget; '
            'got ${r.llmCalls} calls',
      );
      expect(r.passed, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
