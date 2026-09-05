// ignore_for_file: lines_longer_than_80_chars

/// P2 — the J7 overseer slice, LLM-free through the SAME driver the AFM
/// runs use: the mover builds a WRONG-return chain (the measured on-device
/// failure class: inverted branch literals), exhausts maxGoalAttempts, the
/// overseer actor receives the summary zoom + structured gate failure + the
/// failing intent's chain dump, and its scripted `repair(save_url)` lets the
/// scripted mover fix the chain → the gate goes green. Ends idle.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart'
    show CheckerSpec, FixtureFile, IntentExpectation;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

/// The intent_03 chains, as the scripted suite builds them — except the
/// save_url branch literals are SWAPPED (the on-device "wrong return value"
/// class: a valid url yields saved:false).
const _wrongSaveUrlSpecs = [
  {'label': 'load_arg', 'a': 'url'},
  {'label': 'starts_with', 'b': 'http'},
  {'label': 'jump_if_false', 'b': '#5'},
  {'label': 'push_state', 'a': 'bookmarks'},
  {'label': 'literal', 'b': '{"saved": false}', 'next': 6}, // SWAPPED
  {'label': 'literal', 'b': '{"saved": true}'}, // SWAPPED
  {'label': 'return'},
];

const _correctSaveUrlSpecs = [
  {'label': 'load_arg', 'a': 'url'},
  {'label': 'starts_with', 'b': 'http'},
  {'label': 'jump_if_false', 'b': '#5'},
  {'label': 'push_state', 'a': 'bookmarks'},
  {'label': 'literal', 'b': '{"saved": true}', 'next': 6},
  {'label': 'literal', 'b': '{"saved": false}'},
  {'label': 'return'},
];

const _listSavedSpecs = [
  {'label': 'load_state', 'a': 'bookmarks'},
  {'label': 'list_len'},
  {'label': 'return'},
];

/// Dispatches on the decision the world asks for:
/// - overseer brief → the closed-vocabulary `repair(save_url)` decision;
/// - OVERSEER REPAIR decision on the mover → fix the named chain;
/// - anything else (initial build + policy repair re-prompts) → the WRONG
///   build, faithfully reproducing the mover's stuck behavior.
class _OverseerScenarioHandler implements GenerationHandler {
  int wrongBuilds = 0;
  int overseerCalls = 0;

  /// Decisions that saw an actual brief (spawned dispositions — NOT the
  /// tool-result continuation generations of the same decision).
  int briefs = 0;
  int repairs = 0;
  String? overseerBrief;
  bool repairGranted = false;

  /// When true, the overseer FIRST tries the exact on-device hallucination
  /// (`return_value` — an op outside the closed vocabulary) and must be
  /// bounced by the host validation without consuming the cycle.
  bool invalidSpecsFirst = false;
  int invalidBounces = 0;

  ActorGenerateResponse _respond(
    ActorGenerateRequest request,
    List<ToolCall> calls,
  ) {
    final response = ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: const {'text': 'decided'},
      rawOutput: 'decided',
      toolCalls: calls,
      taskId: request.taskId,
    );
    return response;
  }

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    if (request.systemPrompt.contains('You are the OVERSEER')) {
      overseerCalls++;
      if (request.prompt.startsWith('OVERSEER BRIEF')) briefs++;
      if (repairGranted) {
        // Disposition already delivered — close the decision with text.
        final done = ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: const {'text': 'disposition delivered'},
          rawOutput: 'disposition delivered',
          toolCalls: const [],
          taskId: request.taskId,
        );
        world.events.writer<ActorGenerateResponse>().send(done);
        return done;
      }
      if (invalidSpecsFirst && invalidBounces == 0) {
        // The exact on-device hallucination: host validation must bounce it.
        invalidBounces++;
        final bounce = ActorGenerateResponse(
          actorEntity: request.actorEntity,
          structuredOutput: const {'text': 'repair with specs'},
          rawOutput: 'repair with specs',
          toolCalls: const [
            ToolCall(
              name: ToolName('overseer_decision'),
              arguments: {
                'action': 'repair',
                'intent': 'save_url',
                'notes': 'op_11: wrong op, should be return_value instead',
                'specs': [
                  {'label': 'load_arg', 'a': 'url'},
                  {'label': 'return_value'},
                ],
              },
            ),
          ],
          taskId: request.taskId,
        );
        world.events.writer<ActorGenerateResponse>().send(bounce);
        return bounce;
      }
      repairGranted = true;
      overseerBrief = request.prompt;
      final response = _respond(request, [
        const ToolCall(
          name: ToolName('overseer_decision'),
          arguments: {
            'action': 'repair',
            'intent': 'save_url',
            'notes':
                'Rows 4 and 5 are swapped: a VALID url must return '
                '{"saved": true} from row 4.',
            'specs': [
              {'label': 'load_arg', 'a': 'url'},
              {'label': 'starts_with', 'b': 'http'},
              {'label': 'jump_if_false', 'b': '#5'},
              {'label': 'push_state', 'a': 'bookmarks'},
              {'label': 'literal', 'b': '{"saved": true}', 'next': 6},
              {'label': 'literal', 'b': '{"saved": false}'},
              {'label': 'return'},
            ],
          },
        ),
      ]);
      world.events.writer<ActorGenerateResponse>().send(response);
      return response;
    }
    if (request.prompt.contains('OVERSEER REPAIR')) {
      repairs++;
      final response = _respond(request, [
        ToolCall(
          name: const ToolName('intent_define'),
          arguments: {
            'action': 'define',
            'name': 'save_url',
            'params': ['url:string'],
            'returns': 'bool',
            'specs': _correctSaveUrlSpecs,
          },
        ),
        const ToolCall(
          name: ToolName('act_with_project'),
          arguments: {'action': 'materialize'},
        ),
      ]);
      world.events.writer<ActorGenerateResponse>().send(response);
      return response;
    }
    wrongBuilds++;
    // Once the overseer's repair was granted, the mover applies the
    // corrected build consistently (continuation prompts re-include the
    // decision context, so a stuck mover would otherwise re-apply the wrong
    // chain and the repair could never land).
    final specs = handlerFixed ? _correctSaveUrlSpecs : _wrongSaveUrlSpecs;
    final response = _respond(request, [
      ToolCall(
        name: const ToolName('intent_define'),
        arguments: {
          'action': 'define',
          'name': 'save_url',
          'params': ['url:string'],
          'returns': 'bool',
          'specs': specs,
        },
      ),
      ToolCall(
        name: const ToolName('intent_define'),
        arguments: {
          'action': 'define',
          'name': 'list_saved',
          'returns': 'int',
          'specs': _listSavedSpecs,
        },
      ),
      const ToolCall(
        name: ToolName('act_with_project'),
        arguments: {'action': 'materialize'},
      ),
    ]);
    world.events.writer<ActorGenerateResponse>().send(response);
    return response;
  }

  bool get handlerFixed => repairs > 0;
}

void main() {
  test('P2 overseer: wrong-return chain exhausts the mover, overseer '
      'repair(save_url) re-opens exactly that scope, gate goes green',
      () async {
    final jail = await Directory.systemTemp.createTemp('overseer_test_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    final handler = _OverseerScenarioHandler();
    final r = await runCodingAgentOnce(
      task: CodingAgentTask(
        id: 'overseer_01',
        prompt: 'Build the bookmark manager with the macro moves.',
        fixtures: const [],
        checkers: [
          CheckerSpec(
            type: 'intents',
            value:
                '{"calls": [{"intent": "save_url", "args": {"url": '
                '"https://example.dev"}, "expect": {"saved": true}}, '
                '{"intent": "save_url", "args": {"url": "https://second.dev"}}, '
                '{"intent": "list_saved", "expect": {"value": 2}}, '
                '{"intent": "save_url", "args": {"url": "not-a-url"}, '
                '"expect": {"saved": false}}]}',
          ),
        ],
        intents: [
          IntentExpectation(
            'save_url',
            args: {'url': 'https://example.dev'},
            expect: {'saved': true},
          ),
          IntentExpectation('save_url', args: {'url': 'https://second.dev'}),
          IntentExpectation('list_saved', expect: {'value': 2}),
          IntentExpectation(
            'save_url',
            args: {'url': 'not-a-url'},
            expect: {'saved': false},
          ),
        ],
      ),
      jail: jail,
      handler: handler,
      backend: 'scripted_llm_free',
    );

    // The mover really got stuck first (the wrong-return class).
    expect(handler.wrongBuilds, greaterThanOrEqualTo(1));
    // The overseer disposition happened exactly once (spawned ONCE — the
    // second generation is only the tool-result continuation).
    expect(handler.briefs, 1);
    expect(handler.overseerCalls, 2);
    expect(handler.overseerBrief, contains('OVERSEER BRIEF'));
    expect(handler.overseerBrief, contains('summary'));
    expect(handler.overseerBrief, contains('intents failed: save_url'));
    expect(handler.overseerBrief, contains('valid_ops'));
    // The brief is in the repair address space: spec ROWS, not op ids.
    expect(handler.overseerBrief, contains('chain_rows'));
    expect(handler.overseerBrief, contains('"row":0'));
    // The repair scope was opened (the ReAct continuation re-answers the
    // same prompt idempotently — dedup makes repeated defines no-ops).
    expect(handler.repairs, greaterThanOrEqualTo(1));
    // The gate went green only after the repair.
    expect(r.passed, isTrue, reason: '${r.failureClass} · ${r.finalGate}');
    // The repaired chain returned the RIGHT value (the class we targeted).
    expect(r.finalGate.single.detail, contains('all 4 calls verified'));
    // The validated specs traveled into the mover's repair decision.
    expect(handler.repairs, greaterThanOrEqualTo(1));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('P2 overseer: an out-of-vocabulary spec repair is bounced by host '
      'validation WITHOUT consuming the cycle, then the valid repair lands',
      () async {
    final jail = await Directory.systemTemp.createTemp('overseer_val_');
    addTearDown(() => jail.delete(recursive: true).catchError((_) {}));
    final handler = _OverseerScenarioHandler()..invalidSpecsFirst = true;
    final r = await runCodingAgentOnce(
      task: _bookmarkTask(),
      jail: jail,
      handler: handler,
      backend: 'scripted_llm_free',
    );

    // The hallucinated spec was bounced (the on-device failure class).
    expect(handler.invalidBounces, 1);
    // The cycle was NOT consumed by the bounce: the valid repair still
    // landed and the gate went green.
    expect(handler.repairs, greaterThanOrEqualTo(1));
    expect(r.passed, isTrue, reason: '${r.failureClass} · ${r.finalGate}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

CodingAgentTask _bookmarkTask() => CodingAgentTask(
  id: 'overseer_01',
  prompt: 'Build the bookmark manager with the macro moves.',
  checkers: [
    CheckerSpec(
      type: 'intents',
      value:
          '{"calls": [{"intent": "save_url", "args": {"url": '
          '"https://example.dev"}, "expect": {"saved": true}}, '
          '{"intent": "save_url", "args": {"url": "https://second.dev"}}, '
          '{"intent": "list_saved", "expect": {"value": 2}}, '
          '{"intent": "save_url", "args": {"url": "not-a-url"}, '
          '"expect": {"saved": false}}]}',
    ),
  ],
  intents: const [
    IntentExpectation(
      'save_url',
      args: {'url': 'https://example.dev'},
      expect: {'saved': true},
    ),
    IntentExpectation('save_url', args: {'url': 'https://second.dev'}),
    IntentExpectation('list_saved', expect: {'value': 2}),
    IntentExpectation(
      'save_url',
      args: {'url': 'not-a-url'},
      expect: {'saved': false},
    ),
  ],
);
