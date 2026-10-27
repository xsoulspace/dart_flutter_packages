/// Existing compiler/hook preparation plus qualified producer-closure packing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:universal_tooling_runtime/universal_tooling_runtime.dart';

import 'native_cli_bundle.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    throw ArgumentError('COMPILER PREPARED_PACKAGE_CONFIG OUTPUT TARGET');
  }
  final compiler = File(args[0]).resolveSymbolicLinksSync();
  final config = File(args[1]).absolute;
  final output = Directory(args[2]).absolute;
  final result = await runBounded(
    compiler,
    [
      'build',
      'cli',
      '--packages=${config.path}',
      '--root-package=xsoulspace_inference_mlx_native',
      '--target=${args[3]}',
      '--output=${output.path}',
    ],
    deadline: const Duration(minutes: 10),
    workingDirectory: Directory.current.path,
  );
  if (!result.ok) {
    stderr.write(result.stderr);
    throw StateError(
      'native_cli_build_failed:${result.cause.name}:'
      '${result.exitCode}:${result.settlementProblem}',
    );
  }
  final receipt = await completeNativeCliBundle(
    profile: config.parent,
    bundle: Directory('${output.path}/bundle'),
  );
  stdout.writeln(jsonEncode(receipt));
}
