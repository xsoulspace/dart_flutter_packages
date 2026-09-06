// ignore_for_file: lines_longer_than_80_chars

/// ADR 0030 — one decision, one program: the model-emitted READ chain.
///
/// Gates:
/// 1. the chain runs: locate → zoom → read in ONE call, cursor flowing;
/// 2. the cursor law: reads consume cursor.first; explicit focusId
///    overrides;
/// 3. FORMAT BLINDNESS (the law under the law): `read` serves a symbol
///    span and an md section span through the SAME op — the node's class
///    routes the host reader; the program never names a language;
/// 4. fail-fast: an unknown op (and a tool-level error) halt with a named
///    bounce; later ops never run;
/// 5. result-cut: an over-budget op result is CLIPPED to a named marker;
///    the verdict budget stops the program early, honestly.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/agent.dart' show AgentPlugin;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_read_program.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  late World world;
  late List<(String, Map<String, dynamic>)> readerCalls;

  setUp(() {
    readerCalls = [];
    world = World()..addPlugin(AgentPlugin());
    // A tiny meaning graph spanning THREE classes — the program must be
    // class-agnostic over them (ADR 0030 §2).
    addMeaningNode(
      world,
      kind: 'symbol',
      label: 'refreshFsTier',
      id: 'sym_a',
      props: {
        'file': 'lib/fs_etl.dart', 'line': 270, 'class': 'dart',
        'span_start': 100, 'span_end': 400,
      },
    );
    addMeaningNode(
      world,
      kind: 'symbol',
      label: 'refreshFsTierTreeDriven',
      id: 'sym_b',
      props: {
        'file': 'lib/fs_etl.dart', 'line': 300, 'class': 'dart',
        'span_start': 420, 'span_end': 700,
      },
    );
    addMeaningNode(
      world,
      kind: 'section',
      label: 'Refresh tick',
      id: 'sec_1',
      props: {
        'path': 'docs/PLAN.md', 'class': 'md',
        'span_start': 0, 'span_end': 900,
      },
    );
    addMeaningNode(
      world,
      kind: 'key',
      label: 'tick.interval',
      id: 'key_1',
      props: {
        'path': 'config/app.yaml', 'class': 'yaml',
        'span_start': 0, 'span_end': 60,
      },
    );
  });

  /// The host span reader: format-blind — it reports which node class it
  /// was handed, nothing else.
  Map<String, Object?>? reader(Map<String, dynamic> props, int budget) {
    readerCalls.add(('${props['class']}', Map.of(props)));
    return {
      'class': props['class'],
      'span': 'span of ${props['class']} within $budget tokens',
    };
  }

  Future<Map<String, dynamic>> runProgram(List<Object> ops) async {
    final tool = meaningProgramTool(world, spanReader: reader);
    // Production passes DECODED argument maps (the client decodes the wire
    // JSON before the handler) — the test does the same.
    final out = await tool.execute({
      'ops': ops,
    });
    return jsonDecode(out!) as Map<String, dynamic>;
  }

  test(
    'chain: locate → zoom → read runs in ONE call with the cursor flowing',
    () async {
      final verdict = await runProgram([
        {'op': 'locate', 'query': 'refreshFsTier'},
        {'op': 'zoom', 'zoom': 'point', 'budget': 256},
        {'op': 'read'},
      ]);
      expect(verdict['ok'], true);
      expect(verdict['ops_run'], 3);
      // Cursor law: locate set it to the exact-match hit, reads consumed it.
      expect((verdict['cursor'] as List).first, 'sym_a');
      final locateResult = (verdict['results'][0] as Map)['locate'] as Map;
      expect(locateResult['ok'], true);
      final zoomResult = (verdict['results'][1] as Map)['zoom'] as Map;
      expect(zoomResult['ok'], true);
      final readResult = (verdict['results'][2] as Map)['read'] as Map;
      expect(readResult['ok'], true);
      // The read served the node's span through the host reader. The point
      // zoom served it too (read IS a point cut) — both through the SAME
      // class-routed reader.
      expect(readerCalls.length, 2);
      expect(readerCalls.every((r) => r.$1 == 'dart'), isTrue);
    },
  );

  test(
    'format blindness: the SAME read op serves an md section and a yaml '
    'key — the program never names a language',
    () async {
      final md = await runProgram([
        {'op': 'locate', 'query': 'Refresh tick'},
        {'op': 'read', 'budget': 128},
      ]);
      final yaml = await runProgram([
        {'op': 'locate', 'query': 'tick.interval'},
        {'op': 'read', 'budget': 128},
      ]);
      final mdSpan = (md['results'][1] as Map)['read'] as Map;
      final yamlSpan = (yaml['results'][1] as Map)['read'] as Map;
      expect(mdSpan['span']['class'], 'md');
      expect(yamlSpan['span']['class'], 'yaml');
      expect(readerCalls.map((r) => r.$1).toSet(), {'md', 'yaml'});
      // No op ever carried a format parameter.
      expect(
        jsonEncode([md, yaml]).contains('markdown'),
        isFalse,
        reason: 'the format is the node class, never a model parameter',
      );
    },
  );

  test(
    'explicit focusId overrides the cursor; impact reads the named focus',
    () async {
      final verdict = await runProgram([
        {'op': 'locate', 'query': 'refreshFsTier'},
        {'op': 'impact', 'focusId': 'sym_b'},
      ]);
      expect(verdict['ok'], true);
      final impact = (verdict['results'][1] as Map)['impact'] as Map;
      expect(impact['ok'], true);
      expect(impact['focus'], 'sym_b');
    },
  );

  test(
    'fail-fast: an unknown op halts with a named bounce; later ops never run',
    () async {
      final verdict = await runProgram([
        {'op': 'locate', 'query': 'refreshFsTier'},
        {'op': 'edit_symbol', 'name': 'nope'},
        {'op': 'read'},
      ]);
      expect(verdict['ok'], false);
      final halt = verdict['program_halt'] as Map;
      expect(halt['index'], 1);
      expect('${halt['error']}', contains('unknown_op'));
      expect('${halt['error']}', contains('locate, zoom, impact, read'));
      expect(verdict['ops_run'], 1, reason: 'later ops never ran');
      expect((verdict['results'] as List).length, 1);
    },
  );

  test(
    'fail-fast: a tool-level error (unknown focusId) halts with the tool’s '
    'own repair hints',
    () async {
      final verdict = await runProgram([
        {'op': 'impact', 'focusId': 'no_such_node'},
      ]);
      expect(verdict['ok'], false);
      final halt = verdict['program_halt'] as Map;
      expect(halt['index'], 0);
      expect('${halt['error']}', contains('unknown focusId'));
    },
  );

  test(
    'result-cut: an over-budget read is CLIPPED to a named marker, and the '
    'verdict budget stops the program early, honestly',
    () async {
      // A reader whose span is huge → the op result exceeds the per-op cap.
      Map<String, Object?>? hugeReader(Map<String, dynamic> props, int b) => {
        'class': props['class'],
        'span': 'x' * 4096,
      };
      final tool = meaningProgramTool(world, spanReader: hugeReader);
      final out = await tool.execute({
        'ops': [
          {'op': 'locate', 'query': 'refreshFsTier'},
          {'op': 'read', 'budget': 2048},
        ],
      });
      final verdict = jsonDecode(out!) as Map<String, dynamic>;
      final readResult = (verdict['results'][1] as Map)['read'];
      expect(readResult, isNull, reason: 'the fat body never enters context');
      final clipped = verdict['results'][1] as Map;
      expect(clipped['clipped'], true);
      expect(clipped['est_tokens'], greaterThan(perOpResultBudgetTokens));
      expect(
        '${clipped['hint']}',
        contains('exceeded the per-op budget'),
      );
    },
  );

  test(
    'caps: more than programMaxOps is a named halt before anything runs',
    () async {
      final verdict = await runProgram([
        for (var i = 0; i < 9; i++)
          {'op': 'locate', 'query': 'refreshFsTier'},
      ]);
      expect(verdict['ok'], false);
      expect(
        '${(verdict['program_halt'] as Map)['error']}',
        contains('too_many_ops'),
      );
    },
  );
}
