import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook: compiles the Swift bridge into a dylib and registers it as a
/// code asset so `@Native(assetId:)` resolves it without manual path hunting.
///
/// Runs automatically on `dart run/build/test`. Output is cached; the hook
/// re-runs only when bridge sources change.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    // Apple Foundation Models is macOS 26.4+ only.
    if (codeConfig.targetOS != OS.macOS ||
        codeConfig.linkModePreference == LinkModePreference.static) {
      return;
    }

    const minMacos = '26.4';
    final arch = switch (codeConfig.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError(
        'Unsupported architecture: ${codeConfig.targetArchitecture}',
      ),
    };
    final target = '$arch-apple-macos$minMacos';

    final libPath =
        '${input.outputDirectory.toFilePath()}/libxs_fm_bridge.dylib';
    final result = await Process.run('swiftc', [
      '-emit-library',
      '-o',
      libPath,
      '-target',
      target,
      '-sdk',
      await _macosSdkPath(),
      '-framework',
      'FoundationModels',
      '-parse-as-library',
      'bridge/src/bridge.swift',
      'bridge/src/DartSchemaMaterializer.swift',
    ]);

    if (result.exitCode != 0) {
      stderr.writeln(result.stdout);
      stderr.writeln(result.stderr);
      throw Exception('swiftc failed with exit code ${result.exitCode}');
    }

    output.dependencies.addAll([
      Uri.file('bridge/src/bridge.swift'),
      Uri.file('bridge/src/DartSchemaMaterializer.swift'),
    ]);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'swift_bridge',
        file: Uri.file(libPath),
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

Future<String> _macosSdkPath() async {
  final result = await Process.run('xcrun', ['--show-sdk-path']);
  if (result.exitCode != 0) {
    throw Exception('xcrun --show-sdk-path failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}
