// Demo laya-compatible decision server in pure Dart: binds 127.0.0.1:8000
// (the documented laya-serve default) and answers the linear-chain script
// the harness and Last Answer fixtures pin — no Python, no model weights.
//
// Point clients at it explicitly or let them default:
//   LAYA_DECISION_ENDPOINT=http://127.0.0.1:8000/v1/systemone
// The engine is DETERMINISTIC: decisions are fixture answers, not model
// inference. Swap in a real engine on LayaDecisionEngine for live weights.
import 'dart:io';

import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

Future<void> main(final List<String> args) async {
  final port = args.isEmpty ? 8000 : int.parse(args.first);
  var served = 0;
  final server = LayaDecisionServer(
    engine: ScriptedLayaDecisionEngine(_linearChainScript()),
    port: port,
  );
  server.onRequest = (query) {
    served++;
    stdout.writeln(
      '[${DateTime.now().toIso8601String()}] decision #$served: '
      '${query.questions.keys.join(', ')}',
    );
    for (final entry in query.questions.entries) {
      final criteria = entry.value.criteria.entries
          .map((e) => '${e.key}=${e.value}')
          .join(' | ');
      stdout.writeln(
        '    ${entry.key}: ${entry.value.instructions} :: '
        '${criteria.length > 300 ? '${criteria.substring(0, 300)}…' : criteria}',
      );
    }
  };
  await server.start();
  stdout.writeln(
    'laya demo server (scripted engine) on ${server.url} — '
    'POST ${server.url}/v1/systemone, ctrl-c to stop',
  );
  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}

List<LayaDecisionPin> _linearChainScript() => [
  const LayaDecisionPin('tool', 'edit_symbol:', isPrefix: true),
  const LayaDecisionPin('value:opChain.0.label', '"load_arg"'),
  const LayaDecisionPin('value:opChain.1.label', '"literal"'),
  const LayaDecisionPin('value:opChain.2.label', '"literal"'),
  const LayaDecisionPin('value:opChain.3.label', '"literal"'),
  const LayaDecisionPin('value:opChain.4.label', '"literal"'),
  const LayaDecisionPin('value:opChain.5.label', '"add"'),
  const LayaDecisionPin('value:opChain.6.label', '"add"'),
  const LayaDecisionPin('value:opChain.7.label', '"add"'),
  const LayaDecisionPin('value:opChain.8.label', '"add"'),
  const LayaDecisionPin('value:opChain.9.label', '"return"'),
];
