/// Completes the existing hook's native closure when CLI omits data assets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart';

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Reproduce the SDK's observed macOS CLI relocation on a private copy.
/// Match the complete transformed bytes, never UUID/name-only identity.
Future<String?> _relocatedDigest(File source) async {
  if (!Platform.isMacOS) return null;
  final input = await source.open();
  final magic = await input.read(4);
  await input.close();
  if (magic.length != 4 ||
      magic[0] != 0xcf ||
      magic[1] != 0xfa ||
      magic[2] != 0xed ||
      magic[3] != 0xfe) {
    return null;
  }
  final scratch = await Directory.systemTemp.createTemp('native_cli_derive_');
  var settled = true;
  try {
    final clone = await source.copy('${scratch.path}/libmlx_native.dylib');
    for (final command in [
      [
        '/usr/bin/install_name_tool',
        '-id',
        '@rpath/lib/libmlx_native.dylib',
        clone.path,
      ],
      ['/usr/bin/codesign', '--force', '--sign', '-', clone.path],
    ]) {
      final result = await runBounded(
        command.first,
        command.sublist(1),
        deadline: const Duration(seconds: 30),
      );
      settled = result.survivors.isEmpty && result.settlementProblem == null;
      if (!result.ok) {
        throw StateError(
          'native_bundle_relocation_failed:'
          '${result.cause.name}:${result.exitCode}:retained=${scratch.path}',
        );
      }
    }
    return await _digest(clone);
  } finally {
    if (settled) await scratch.delete(recursive: true);
  }
}

Future<Map<String, Object>> completeNativeCliBundle({
  required Directory profile,
  required Directory bundle,
}) async {
  final image = File('${bundle.path}/lib/libmlx_native.dylib');
  if (!image.existsSync()) throw StateError('native_bundle_image_missing');
  final imageHash = await _digest(image);
  final outputs = Directory(
    '${profile.path}/hooks_runner/xsoulspace_inference_mlx_native',
  );
  final matches = <String, Map<String, Object>>{};
  if (outputs.existsSync()) {
    await for (final entry in outputs.list(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('/output.json')) continue;
      final output = jsonDecode(await entry.readAsString()) as Map;
      for (final asset in output['assets'] as List? ?? const []) {
        final encoding = (asset as Map)['encoding'] as Map?;
        if (encoding?['id'] !=
            'package:xsoulspace_inference_mlx_native/mlx_native') {
          continue;
        }
        final source = File(encoding!['file'] as String);
        if (!source.existsSync()) continue;
        final producerHash = await _digest(source);
        final relocated = producerHash != imageHash;
        if (relocated && await _relocatedDigest(source) != imageHash) continue;
        final metal = File('${source.parent.path}/mlx.metallib');
        if (!metal.existsSync()) {
          throw StateError('native_bundle_producer_metal_missing');
        }
        final metalHash = await _digest(metal);
        matches[metalHash] = {
          'producerOutput': entry.path,
          'producerOutputSha256': await _digest(entry),
          'producerImage': source.path,
          'producerMetal': metal.path,
          'nativeImageSha256': imageHash,
          'producerImageSha256': producerHash,
          'sdkRelocation': relocated
              ? 'macos-cli-id-and-adhoc-sign-v1'
              : 'none',
          'metalSha256': metalHash,
        };
      }
    }
  }
  if (matches.isEmpty) throw StateError('native_bundle_producer_unmatched');
  if (matches.length != 1) throw StateError('native_bundle_producer_ambiguous');
  final receipt = matches.values.single;
  final source = File(receipt['producerMetal']! as String);
  final destination = File('${image.parent.path}/mlx.metallib');
  final temporary = File('${destination.path}.prepare-$pid');
  try {
    await source.copy(temporary.path);
    if (await _digest(temporary) != receipt['metalSha256'] ||
        await _digest(source) != receipt['metalSha256'] ||
        await _digest(image) != imageHash ||
        await _digest(File(receipt['producerImage']! as String)) !=
            receipt['producerImageSha256'] ||
        await _digest(File(receipt['producerOutput']! as String)) !=
            receipt['producerOutputSha256']) {
      throw StateError('native_bundle_producer_changed');
    }
    await temporary.rename(destination.path);
  } finally {
    if (temporary.existsSync()) await temporary.delete();
  }
  final manifest = {
    'schema': 'mlx_native.cli_native_closure.v1',
    ...receipt,
    'nativeImage': image.path,
    'colocatedMetal': destination.path,
  };
  await File(
    '${bundle.path}/native_closure.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  return manifest;
}
