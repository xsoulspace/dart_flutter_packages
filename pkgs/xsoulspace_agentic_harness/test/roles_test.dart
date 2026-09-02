// ignore_for_file: lines_longer_than_80_chars

/// ADR 0020 §5 — model ≠ actor: roles as data. Two actors on the SAME model
/// class with DIFFERENT roles produce role-specific cuts (per-registry
/// composition) and role-specific prompts. LLM-free.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'package:xsoulspace_agentic_harness/src/agent.dart';
import 'package:xsoulspace_agentic_harness/src/events.dart';
import 'package:xsoulspace_agentic_harness/src/handler.dart';
import 'package:xsoulspace_agentic_harness/src/systems/projection/cut_composition.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/squad_driver.dart';

void main() {
  late Directory workspace;
  setUp(() async => workspace = await Directory.systemTemp.createTemp('roles'));
  tearDown(() => workspace.deleteSync(recursive: true));

  test('two roles on one model: per-role cuts and prompts', () async {
    final captured = <String, (List<String>, String)>{};

    final coderRole = const AgentRole(name: 'coder');
    final overseerRole = AgentRole(
      name: 'overseer',
      // A narrow cut: the overseer sees the goal and ONE observation —
      // the summary-style composition (ADR 0020 §5).
      composition: const CutComposition(name: 'overseer', slots: [
        CutSlot(name: 'goal', fill: CutSlotFill.goal, capacity: 1, required: true),
        CutSlot(
          name: 'observations',
          fill: CutSlotFill.observations,
          capacity: 1,
        ),
      ]),
      systemPrompt: 'You are the OVERSEER. Review, do not build.',
    );

    final result = await runSquad(
      workspace: workspace,
      tasks: [
        SquadTask(
          id: 'fix',
          prompt: 'Create fix_note.txt containing fixed.',
          checkCommand: ['dart', 'run', 'check_fix.dart'],
          ownedFiles: ['fix_note.txt'],
          role: coderRole,
          fixtures: [
            SquadFixture(
              path: 'check_fix.dart',
              content: "import 'dart:io';\nvoid main() { if "
                  "(!File('fix_note.txt').existsSync()) exit(1); }\n",
            ),
          ],
        ),
        SquadTask(
          id: 'review',
          prompt: 'Create review_note.txt containing reviewed.',
          checkCommand: ['dart', 'run', 'check_review.dart'],
          ownedFiles: ['review_note.txt'],
          role: overseerRole,
          fixtures: [
            SquadFixture(
              path: 'check_review.dart',
              content: "import 'dart:io';\nvoid main() { if "
                  "(!File('review_note.txt').existsSync()) exit(1); }\n",
            ),
          ],
        ),
      ],
      handlerFor: (actorName) => actorName == 'squad_fix'
          ? _Capture(actorName, captured, 'fix_note.txt', 'fixed')
          : _Capture(actorName, captured, 'review_note.txt', 'reviewed'),
    );

    expect(result.allPassed, isTrue,
        reason: '${[for (final r in result.rows) "${r.actorName}: ${r.verdict}"]}');

    // Both actors worked; both have a2a columns.
    expect(result.rows.map((r) => r.decisions), everyElement(greaterThan(0)));
    expect(result.rows.map((r) => r.projectionTokens), everyElement(greaterThan(0)));

    // ROLE COMPOSITION: the overseer's cut (capacity-1 observations) is
    // narrower than the coder's (capacity-8) for the same world.
    final coderFrags = captured['squad_fix']!.$1;
    final overseerFrags = captured['squad_review']!.$1;
    expect(coderFrags.length, greaterThan(overseerFrags.length));

    // ROLE PROMPT: the overseer's system prompt is its own.
    expect(overseerFrags.join(' '), isNot(contains('work ONLY on your task')));
    expect(
      captured['squad_fix']!.$2,
      isNot(contains('OVERSEER')),
    );
  });
}

class _Capture implements GenerationHandler {
  _Capture(this.name, this.captured, this.noteFile, this.word);
  final String name;
  final Map<String, (List<String>, String)> captured;
  final String noteFile;
  final String word;
  var wrote = false;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    captured[name] = (
      [for (final f in request.contextFragments) f.toString()],
      request.systemPrompt,
    );
    final calls = wrote
        ? const <ToolCall>[]
        : [
            ToolCall(
              name: const ToolName('write'),
              arguments: {'path': noteFile, 'content': '$word\n'},
            ),
          ];
    wrote = true;
    final r = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'ok'},
      rawOutput: 'ok',
      toolCalls: calls,
      taskId: request.taskId,
    );
    world.events.writer<ActorGenerateResponse>().send(r);
    return r;
  }
}
