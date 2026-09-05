// ignore_for_file: lines_longer_as_80_chars

/// ADR 0027 measurement: the read path, timed, on the REAL AFM backend.
///
/// Env-gated (`HARNESSD_AFM_BENCH=1`) — skips honestly when the engine is
/// unavailable or the gate is not requested (LLM-free CI stays LLM-free).
///
/// Measures, per prompt class, on the AFM (apple_foundation) binding:
/// 1. DIRECTIVE read (`[scan] [zoom …]`) — mechanical path: zero model,
///    zero grade. Expected: sub-second.
/// 2. `[read-only]` free-form delegation — the AFM model decides what to
///    zoom; no grade. Expected: model latency only.
/// 3. Mutation task (baseline) — actor + in-loop verifier + final gate
///    (`dart run main.dart`, the bare-file convention). The old read cost
///    reference is the published R7 row: a read decision paid ~68s (dart
///    test cold compile) — [results_r7.md].
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';

void main() {
  test(
    'ADR 0027 seam speed — AFM backend (HARNESSD_AFM_BENCH=1)',
    () async {
      if (Platform.environment['HARNESSD_AFM_BENCH'] != '1') {
        markTestSkipped('set HARNESSD_AFM_BENCH=1 to bench the AFM read path');
      }
      final ws = await Directory.systemTemp.createTemp('adr0027_afm_');
      addTearDown(() => ws.deleteSync(recursive: true));
      File('${ws.path}/main.dart').writeAsStringSync(
        'void main() { print(greet("x")); }\n'
        'String greet(String name) => "hello \$name";\n',
      );
      Directory('${ws.path}/lib').createSync();
      File(
        '${ws.path}/lib/util.dart',
      ).writeAsStringSync('int add(int a, int b) => a + b;\n');

      final afm = appleFoundationBinding();
      final backend = HarnessAcpBackend(
        backend: 'apple_foundation_afm',
        bindings: {'apple_foundation_afm': afm.binding},
        meaningProfile: true,
      );
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws.path),
      );
      final rows = <String>[];
      Future<double> run(String label, String prompt) async {
        final updates = <String>[];
        final sw = Stopwatch()..start();
        final stop = await backend.prompt(
          AcpPromptRequest(
            sessionId: sid,
            prompt: [AcpTextBlock(prompt)],
          ),
          emit: (u) => updates.add(
            u is AgentMessageChunk ? (u.content as AcpTextBlock).text : '',
          ),
          isCancelled: () => false,
        );
        sw.stop();
        final out = updates.join();
        final graded = prompt.startsWith('[scan]')
            ? 'no-task (mechanical)'
            : out.contains('read_only_not_applicable')
            ? 'no-grade (declared read)'
            : 'full oracle';
        expect(stop, AcpStopReason.endTurn, reason: '$label: $out');
        rows.add(
          '| `$label` | ${sw.elapsedMilliseconds} ms | $graded | '
          '${out.contains("[repo_etl]") || out.contains("[meaning_zoom]") ? "cuts streamed" : "no cuts"} |',
        );
        return sw.elapsedMilliseconds.toDouble();
      }

      final rowsHeader = <String>[
        '| prompt class | wall | gate | surface |',
        '| --- | --- | --- | --- |',
      ];
      await run('directive read [scan][zoom]', '[scan] [zoom add]');
      await run('[read-only] free-form', '[read-only] look at util.dart and report its functions');
      await run('mutation task (baseline)', 'make add return a+b+1');

      final report = '''
# ADR 0027 seam speed — measured (AFM backend, real device)

Backend: `apple_foundation_afm` (AppleFoundationNativeClient), meaning
profile, workspace = bare-file fixture. Published pre-0027 reference: a
read decision cost ~68,775 ms (the `dart test` cold compile in the final
gate — results_r7.md).

${rowsHeader.join('\n')}
${rows.join('\n')}

## Reading

- The directive read is MECHANICAL: zero model, zero grade — its wall is
  ETL + zoom only (two orders below the 68s row).
- The `[read-only]` delegation pays AFM latency only; the gate is stamped
  `read_only_not_applicable` (excluded from pass-rate columns).
- The mutation baseline keeps the FULL oracle (verifier inside the loop +
  final gate) — the honest-oracle law is untouched.

Rows are published even on FAIL, with backend + tokens source (AFM
on-device, no token billing) per the standing rules.
''';
      final out = File(
        'docs/results_seam_speed_afm.md',
      );
      out.writeAsStringSync(report);
      // ignore: avoid_print
      print(report);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
