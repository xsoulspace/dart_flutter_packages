// ignore_for_file: lines_longer_than_80_chars

/// P1 gate — the opaque ToolCallError class (the P0 re-run finding,
/// `benchmark/runs/afm_wave_results.md` § P0 RE-RUN).
///
/// A generation whose tool call failed the FRAMEWORK's schema validation
/// (`tool_args_invalid`, named by the bridge) is bounce-class DATA:
///
/// 1. it lands as a NAMED bounce beat on the actor's thread (the tool's
///    required slots per action class — teaching data),
/// 2. it is NEVER a same-cut retry (the retry ladder — RetryCount and its
///    "tighter context" prompt — must not fire; the repair path re-prompts
///    with the bounce text per the B2 dialect),
/// 3. the FAILED generation is a SPENT round: maxToolRounds contains the
///    loop (the 2026-09-06 budgets let 59–109 failed generations through).
///
/// LLM-free: [ScriptedGenerationHandler] scripts the named failure; the
/// world does the rest. Every test ends `expectIdle`.
library;

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

import 'support/agent_harness_support.dart';

/// The bridge-shaped named failure: code + framework detail.
const _argsInvalidError =
    'tool_args_invalid: ToolCallError — arguments failed GenerationSchema '
    'validation for `act_with_project` (missing required slot `symbolId`)';

Future<(World, Entity)> _world({
  required String decisionPrompt,
  GenerationHandler? handler,
  AgencyPolicy? agencyPolicy,
}) async {
  final world = await buildTestWorld(
    handler: handler,
    agencyPolicy: agencyPolicy,
  );
  final scene = spawnScene(world);
  final actor = spawnActor(world, scene, openDecisionPrompt: decisionPrompt);
  world.flush();
  return (world, actor);
}

int _rounds(World world, Entity actor) =>
    world.getEntity(actor).$1.get<ToolRoundCount>()?.value ?? 0;

void main() {
  group('tool_args_invalid bounce class (P1)', () {
    test('a named failure lands as a NAMED bounce beat, not a retry', () async {
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(mode: ScriptedTurnMode.error, errorMessage: _argsInvalidError),
        const ScriptedTurn(text: 'recovered'),
      ]);
      final (world, actor) = await _world(
        handler: handler,
        decisionPrompt: 'edit the symbol',
      );

      // Cycle 1: the scripted generation fails schema validation.
      await runCycle(world, settleDelay: const Duration(milliseconds: 100));
      world.flush();

      // (1) NAMED bounce beat on the actor's thread — the class teaching.
      final bounceBeats = beatsWithText(world, 'tool_args_invalid');
      expect(bounceBeats, isNotEmpty, reason: 'no tool_args_invalid beat');
      final named = world
          .query2<ToolResultContent, TextContent>()
          .where((t) => t.$1.get<ToolResultContent>()?.name == 'tool_args_invalid')
          .toList();
      expect(named, isNotEmpty, reason: 'bounce beat is not NAMED');
      final beatText = named.first.$1.get<TextContent>()?.text ?? '';
      expect(beatText, contains('opChain/executableId'), reason: 'per-class slots missing');
      expect(beatText, contains('body/anchor'), reason: 'per-class slots missing');

      // (2) NOT a same-cut retry: the retry ladder never fired — the
      // repair decision was re-opened with the bounce text (B2 dialect).
      expect(world.getEntity(actor).$1.get<RetryCount>(), isNull,
          reason: 'args-invalid took the generic retry path');
      expect(handler.requests.length, 1);
      expect(world.getEntity(actor).$1.has<OpenDecision>(), isTrue);

      // Recovery: cycle 2 is served the repair prompt and answers with
      // text — fully idle, budgets reset.
      await runCycle(world, settleDelay: const Duration(milliseconds: 100));
      world.flush();
      final repairPrompt = handler.requests[1].prompt;
      expect(repairPrompt, contains('tool_args_invalid'));
      expect(repairPrompt, contains('required slot'));
      expect(repairPrompt, isNot(contains('Retry with tighter context')));
      expect(repairPrompt, contains(_argsInvalidError), reason: 'framework detail lost');
      expectIdle(world);
    });

    test('the args-invalid loop is contained by maxToolRounds', () async {
      // The P0 rows looped 59–109 failed generations. Two failed
      // generations (maxToolRounds: 2) must DROP the decision — not loop.
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(mode: ScriptedTurnMode.error, errorMessage: _argsInvalidError),
      ]);
      final (world, actor) = await _world(
        handler: handler,
        agencyPolicy: AgencyPolicy(maxConcurrent: 1, maxToolRounds: 2),
        decisionPrompt: 'edit the symbol',
      );

      await HarnessLoop(world: world).runUntilIdle();
      world.flush();

      expect(handler.requests.length, 2,
          reason: 'the bounce loop was not contained at maxToolRounds');
      expect(_rounds(world, actor), 2);
      // Containment DROPS the decision (host-ladder repair) — the actor is
      // free, and the retry ladder never fired.
      expect(world.getEntity(actor).$1.has<OpenDecision>(), isFalse);
      expect(world.getEntity(actor).$1.get<RetryCount>(), isNull);
      expect(beatsWithText(world, 'tool_args_invalid'), isNotEmpty);
      expectIdle(world);
    });

    test('a generic failed generation is a spent round too', () async {
      // Clause (c) is CLASS-AGNOSTIC: any FAILED generation burns a round,
      // so an opaque error loop dies at maxToolRounds even before
      // maxRetries would bind (2 rounds < 3 retries here).
      final handler = ScriptedGenerationHandler([
        const ScriptedTurn(mode: ScriptedTurnMode.error),
      ]);
      final (world, actor) = await _world(
        handler: handler,
        agencyPolicy: AgencyPolicy(maxConcurrent: 1, maxToolRounds: 2),
        decisionPrompt: 'do the task',
      );

      await HarnessLoop(world: world).runUntilIdle();
      world.flush();

      expect(handler.requests.length, 2, reason: 'uncontained failure loop');
      expect(_rounds(world, actor), 2);
      expect(world.getEntity(actor).$1.has<OpenDecision>(), isFalse);
      // Class discipline: a generic failure is NOT bounced as args-invalid.
      expect(beatsWithText(world, 'tool_args_invalid'), isEmpty);
      expectIdle(world);
    });
  });
}
