import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// The harness flatness probe (ADR 0028/0030 measurement instrument).
///
/// Measures the North Star claim — flat tokens/decision — against the
/// NATIVE truth (`model.tokenCount(for:)` / `model.contextSize`, emitted
/// by the bridge as `context:` stderr traces), not the chars/4 estimator.
///
/// Modes:
/// - `per-move` (default): ONE decision forced through several sequential
///   native tool rounds — the pre-contract accumulation curve. Still the
///   bridge-level canary: after ADR 0028 the harness never runs this
///   shape, but the bridge must keep its per-round traces honest.
/// - `sequential`: N decisions, ONE executed move each (the ADR 0028
///   contract shape). Per-decision `context:` lines show the flat
///   per-decision native context; the CURVE summary compares total
///   token-rounds against the per-move mode.
///
/// Usage:
/// ```
/// dart run tool/afm_flatness_probe.dart              # per-move
/// dart run tool/afm_flatness_probe.dart sequential 3 # N one-move decisions
/// ```
/// Requires macOS 26.4+ with Apple Intelligence enabled. On-device smoke —
/// never a CI gate.
Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'per-move' : args.first;
  final rounds = args.length > 1 ? int.parse(args[1]) : 3;
  if (mode == 'sequential') {
    await _sequential(rounds);
  } else {
    await _perMove(rounds);
  }
}

// Teaching-prompt-sized instructions (~1,600-token envelope) — the fixed
// surface the meaning profile budget-gates.
String _teachingBlock() => List.generate(
      16,
      (i) =>
          'Rule ${i + 1}: edit code through the meaning tree — never file '
          'reads, never code tokens. Discover with zoom, read budgeted cuts, '
          'act through edit moves the host materializes and verifies. '
          'Bounces carry repair hints; follow them, never guess ids.',
    ).join(' ');

// Cut-sized prompt — the budgeted zoom cut, framed in prose (the AFM
// language gate fails on JSON-dominant prompts — delegation_r9 finding 14).
String _cutPrompt({required int rounds, required bool oneMovePerDecision}) {
  final cut = List.generate(
    28,
    (i) =>
        '{"id":"sym_fixture_$i","kind":"symbol","label":"fn_$i",'
        '"props":{"file":"lib/util_$i.dart","line":${i * 7 + 3},"decl":"method"}}',
  ).join('\n');
  final contract = oneMovePerDecision
      ? 'Contract: ONE tool call per response — after its result, end the '
          'turn; the next decision continues.'
      : 'Work the task in $rounds steps: probe_list, then probe_read for '
          'sym_fixture_0 (and sym_fixture_1 if needed), then answer with '
          'ONLY the word DONE. One tool call per step.';
  return 'You are working a small code fixture from a budgeted meaning-tree '
      'cut. Below is the cut: a JSON lines listing of symbols. $contract\n\n'
      'Cut begins here:\n$cut\nCut ends here.';
}

ToolRegistry _registry({
  required void Function() onList,
  required void Function() onRead,
}) =>
    ToolRegistry()
      ..register(
        ToolDef(
          name: const ToolName('probe_list'),
          description:
              'List the fixture symbols. Returns a JSON array of ids. '
              'Call this FIRST; the read tool needs an id from this result.',
          argsSchema: SchemaBundle(
            root: FM.object(
              'probe_list',
              properties: () => [FM.prop('limit', FM.integer())],
            ),
          ),
          execute: (args) async {
            onList();
            return jsonEncode({
              'ok': true,
              'ids': [for (var i = 0; i < 12; i++) 'sym_fixture_$i'],
              'note': 'pass one id to probe_read',
            });
          },
        ),
      )
      ..register(
        ToolDef(
          name: const ToolName('probe_read'),
          description:
              'Read one fixture symbol by id (from probe_list). Returns the '
              'symbol body — sizeable, like a budgeted meaning cut.',
          argsSchema: SchemaBundle(
            root: FM.object(
              'probe_read',
              properties: () => [FM.prop('id', FM.string())],
            ),
          ),
          execute: (args) async {
            onRead();
            final id = args is Map ? '${args['id']}' : 'unknown';
            return jsonEncode({
              'id': id,
              'body': List.generate(
                24,
                (i) =>
                    'line $i of $id: {kind: symbol, refs: [a, b, c], '
                    'span: ${i * 13}-${i * 13 + 12}}',
              ).join('\n'),
            });
          },
        ),
      );

Future<void> _perMove(int rounds) async {
  var listCalls = 0;
  var readCalls = 0;
  final registry = _registry(onList: () => listCalls++, onRead: () => readCalls++);
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability() || !client.isAvailable) {
    // ignore: avoid_print
    print('CURVE unavailable: Apple Intelligence not reachable');
    exit(2);
  }
  final sw = Stopwatch()..start();
  final result = await client.infer(
    InferenceRequest(
      prompt: _cutPrompt(rounds: rounds, oneMovePerDecision: false),
      systemPrompt: _teachingBlock(),
      task: InferenceTask.text,
    ),
    toolRegistry: registry,
  );
  sw.stop();
  _summary(
    mode: 'per-move (pre-contract accumulation curve)',
    sw: sw,
    result: result,
    listCalls: listCalls,
    readCalls: readCalls,
  );
  exit(result.success ? 0 : 1);
}

Future<void> _sequential(int decisions) async {
  var listCalls = 0;
  var readCalls = 0;
  final registry = _registry(
    onList: () => listCalls++,
    onRead: () => readCalls++,
  );
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability() || !client.isAvailable) {
    // ignore: avoid_print
    print('CURVE unavailable: Apple Intelligence not reachable');
    exit(2);
  }
  final sw = Stopwatch()..start();
  var ok = true;
  for (var d = 1; d <= decisions; d++) {
    // One decision = one infer = one fresh native session (ADR 0028): the
    // task names exactly ONE move; the driver loop is the harness.
    final step = switch (d) {
      1 => 'Step: call probe_list, then END YOUR TURN.',
      _ => 'Step: call probe_read for sym_fixture_0, then END YOUR TURN.',
    };
    final result = await client.infer(
      InferenceRequest(
        prompt:
            '${_cutPrompt(rounds: decisions, oneMovePerDecision: true)}\n\n'
            'This decision: $step',
        systemPrompt: _teachingBlock(),
        task: InferenceTask.text,
      ),
      toolRegistry: registry,
    );
    ok = ok && result.success;
    final err = result.error?.code ?? '';
    // ignore: avoid_print
    print(
      'CURVE decision $d/$decisions ok=${result.success} '
      '${err.isEmpty ? '' : 'error=$err '}'
      'listCalls=$listCalls readCalls=$readCalls',
    );
  }
  sw.stop();
  _summary(
    mode: 'sequential (ADR 0028 contract shape)',
    sw: sw,
    result: null,
    ok: ok,
    listCalls: listCalls,
    readCalls: readCalls,
    decisions: decisions,
  );
  exit(ok ? 0 : 1);
}

void _summary({
  required String mode,
  required Stopwatch sw,
  required InferenceResult<InferenceResponse>? result,
  required int listCalls,
  required int readCalls,
  int? decisions,
  bool? ok,
}) {
  final success = ok ?? result?.success ?? true;
  // ignore: avoid_print
  print(
    'CURVE probe done in ${sw.elapsedMilliseconds} ms | mode=$mode | '
    'ok=$success | decisions=${decisions ?? 1} | '
    'listCalls=$listCalls readCalls=$readCalls',
  );
  // ignore: avoid_print
  print(
    'CURVE read the per-round/per-decision growth above (grep "context:") — '
    'native tokenCount truth, never the estimator. Per ADR 0030 the '
    'graduation row compares THIS per-move curve against the '
    'program-chained mode.',
  );
}
