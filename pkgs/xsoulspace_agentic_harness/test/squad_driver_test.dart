// ignore_for_file: lines_longer_than_80_chars

/// Stage N2 — multi-actor squad: two actors, two FILE-DISJOINT tasks, one
/// shared workspace, per-actor run-graded verification. LLM-free (scripted
/// handlers through the SAME loop). Ends expectIdle.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart';
import 'package:xsoulspace_agentic_harness/src/events.dart';
import 'package:xsoulspace_agentic_harness/src/handler.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/squad_driver.dart';

/// Scripted: one write (the task's fix) then a closing text turn.
class _WriteThenDone implements GenerationHandler {
  _WriteThenDone(this.path, this.content);
  final String path;
  final String content;
  bool wrote = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    final calls = wrote
        ? const <ToolCall>[]
        : [
            ToolCall(
              name: const ToolName('write'),
              arguments: {'path': path, 'content': content},
            ),
          ];
    wrote = true;
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': wrote ? 'done' : 'writing'},
      rawOutput: wrote ? 'done' : 'writing',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }
}

SquadTask _task({
  required String id,
  required String noteFile,
  required String word,
}) {
  return SquadTask(
    id: id,
    prompt: 'Create $noteFile containing the word $word.',
    checkCommand: ['dart', 'run', 'check_$id.dart'],
    ownedFiles: [noteFile],
    fixtures: [
      SquadFixture(
        path: 'check_$id.dart',
        content: "import 'dart:io';\n"
            'void main() {\n'
            "  final t = File('$noteFile').readAsStringSync();\n"
            "  if (!t.contains('$word')) {\n"
            "    stderr.writeln('$noteFile missing $word');\n"
            '    exit(1);\n'
            '  }\n'
            '}\n',
      ),
    ],
  );
}

void main() {
  late Directory workspace;

  setUp(() async => workspace = await Directory.systemTemp.createTemp('n2sq'));
  tearDown(() => workspace.deleteSync(recursive: true));

  test('two actors complete two file-disjoint tasks in one world', () async {
    final result = await runSquad(
      workspace: workspace,
      tasks: [
        _task(id: 'a', noteFile: 'a_note.txt', word: 'alpha'),
        _task(id: 'b', noteFile: 'b_note.txt', word: 'beta'),
      ],
      handlerFor: (actorName) => actorName == 'squad_a'
          ? _WriteThenDone('a_note.txt', 'alpha\n')
          : _WriteThenDone('b_note.txt', 'beta\n'),
    );

    expect(result.allPassed, isTrue, reason: '${[for (final r in result.rows) "${r.actorName}: ${r.verdict}"]}');
    expect(result.rows, hasLength(2));
    expect(
      File('${workspace.path}/a_note.txt').readAsStringSync(),
      contains('alpha'),
    );
    expect(
      File('${workspace.path}/b_note.txt').readAsStringSync(),
      contains('beta'),
    );
  });

  test('single-writer: a cross-owner write is rejected and never lands',
      () async {
    final locks = FileLockTable();
    expect(locks.claim('shared.txt', 'owner_1'), isTrue);
    // Same owner re-claims fine.
    expect(locks.claim('shared.txt', 'owner_1'), isTrue);
    // A different owner cannot claim or write it.
    expect(locks.claim('shared.txt', 'owner_2'), isFalse);

    final root1 = FsToolsRoot(workspace.path);
    root1.writeGateway = JailWriteGateway(
      root1,
      locks: locks,
      owner: 'owner_1',
    );
    final root2 = FsToolsRoot(workspace.path);
    root2.writeGateway = JailWriteGateway(
      root2,
      locks: locks,
      owner: 'owner_2',
    );
    // FsToolsRoot resolves symlinks (macOS /var → /private/var) — build
    // paths from the RESOLVED root so lock keys match _rel() output.
    final shared1 = '${root1.rootPath}/shared.txt';
    final shared2 = '${root2.rootPath}/shared.txt';
    expect(root1.rootPath, root2.rootPath);

    final ack1 = await root1.writeGateway!
        .interceptWrite(shared1, 'from owner_1');
    expect(ack1, startsWith('wrote'));

    final ack2 = await root2.writeGateway!
        .interceptWrite(shared2, 'from owner_2');
    expect(ack2, startsWith('REJECTED'));
    expect(ack2, contains('single-writer violation'));
    // owner_1's content is untouched.
    expect(File(shared1).readAsStringSync(), 'from owner_1');

    // Release → owner_2 may proceed.
    locks.release('shared.txt', 'owner_1');
    final ack3 = await root2.writeGateway!
        .interceptWrite(shared2, 'from owner_2');
    expect(ack3, startsWith('wrote'));
  });
}
