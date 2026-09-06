import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// R9.1 INVESTIGATION A probe — native AFM session context accumulation.
///
/// Runs ONE decision (one `infer` → one `LanguageModelSession`) whose task
/// forces several SEQUENTIAL native tool rounds, mirroring the meaning
/// profile's decision shape (teaching-prompt-sized instructions, ~2k-token
/// cut as the prompt, tools with real schemas and cut-sized results).
///
/// The bridge emits `context:` traces to stderr: the per-decision baseline
/// (window, instructions, prompt, tools, schema) and the PER-ROUND transcript
/// token count — the actual context the model re-reads on every tool round.
/// The growth curve across rounds is the accumulation tell (a flat harness
/// cut does not imply a flat native context).
///
/// Usage: `dart run bin/afm_context_probe.dart 2>&1 | grep -E 'context:|CURVE'`
/// Requires macOS 26.4+ with Apple Intelligence enabled.
Future<void> main(List<String> args) async {
  final rounds = args.isEmpty ? 3 : int.parse(args.first);

  // Teaching-prompt-sized instructions (~1,600 tokens ≈ 6,400 chars) — the
  // fixed surface the meaning profile budget-gates at 1,600 tokens.
  final teachingBlock = List.generate(
    16,
    (i) =>
        'Rule ${i + 1}: edit code through the meaning tree — never file '
        'reads, never code tokens. Discover with zoom, read budgeted cuts, '
        'act through edit moves the host materializes and verifies. '
        'Bounces carry repair hints; follow them, never guess ids.',
  ).join(' ');

  // Cut-sized prompt (~2,048 tokens ≈ 8,200 chars) — the budgeted zoom cut.
  final cut = List.generate(
    28,
    (i) =>
        '{"id":"sym_fixture_$i","kind":"symbol","label":"fn_$i",'
        '"props":{"file":"lib/util_$i.dart","line":${i * 7 + 3},"decl":"method"}}',
  ).join('\n');

  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability() || !client.isAvailable) {
    stderr.writeln('CURVE unavailable: Apple Intelligence not reachable');
    exit(2);
  }

  // Sequential dependency: list → read ids → summarize. Each round's
  // arguments depend on the previous round's result, so the native tool
  // loop cannot collapse into one round.
  var listCalls = 0;
  var readCalls = 0;
  final registry = ToolRegistry()
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
          listCalls++;
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
          readCalls++;
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

  final prompt =
      'You are working a small code fixture from a budgeted meaning-tree '
      'cut. Below is the cut: a JSON lines listing of symbols. Read it, '
      'then work the task in $rounds steps. Step 1: call probe_list. '
      'Step 2: call probe_read for sym_fixture_0 (and sym_fixture_1 if '
      'needed). Step 3: answer with ONLY the word DONE. Make one tool '
      'call per step, in order.\n\nCut begins here:\n$cut\nCut ends here.';

  final sw = Stopwatch()..start();
  final result = await client.infer(
    InferenceRequest(
      prompt: prompt,
      systemPrompt: teachingBlock,
      task: InferenceTask.text,
    ),
    toolRegistry: registry,
  );
  sw.stop();

  final ok = result.success;
  final raw = result.data?.rawOutput ?? result.error?.message ?? '';
  // ignore: avoid_print
  print(
    'CURVE probe done in ${sw.elapsedMilliseconds} ms | '
    'ok=$ok | listCalls=$listCalls readCalls=$readCalls | '
    'output=${raw.length > 120 ? raw.substring(0, 120) : raw}',
  );
  // ignore: avoid_print
  print(
    'CURVE read the per-round growth above (grep "context:") — '
    'decision_final transcriptTokens is the accumulated native context '
    'for ONE decision; compare per-round deltas against the flat '
    'harness cut (baselineTranscriptTokens + promptTokens + toolTokens).',
  );
  exit(ok ? 0 : 1);
}
