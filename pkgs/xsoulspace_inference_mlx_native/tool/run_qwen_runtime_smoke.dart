/// Parent deadline covers FFI/GPU hangs and physically settles the child.
library;

import 'dart:convert';
import 'dart:io';

import 'package:universal_tooling_runtime/universal_tooling_runtime.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) throw ArgumentError('BINARY SNAPSHOT EVIDENCE_JSON');
  final result = await runBounded(
    File(args[0]).absolute.path,
    [args[1]],
    deadline: const Duration(minutes: 2),
    maxCapturedBytes: 128 * 1024,
  );
  final evidence = {
    'schema': 'mlx_native.bounded_qwen_smoke.v1',
    'deadlineSeconds': 120,
    'cause': result.cause.name,
    'exitCode': result.exitCode,
    'survivors': result.survivors,
    'settlementProblem': result.settlementProblem,
    'stdout': result.stdout,
    'stderr': result.stderr,
    'ok': result.ok,
    'codingAcceptance': false,
  };
  await File(
    args[2],
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(evidence)}\n');
  stdout.writeln(jsonEncode(evidence));
  if (!result.ok) exitCode = 1;
}
