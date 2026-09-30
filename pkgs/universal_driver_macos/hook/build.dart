import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook: compiles the Swift accessibility driver bridge into a dylib
/// and registers it as a code asset so `@Native(assetId:)` resolves it
/// without manual path hunting (the ADR 0001 pattern, proven in
/// `universal_capture_macos`).
///
/// Runs automatically on `dart run/build/test`. Output is cached; the hook
/// re-runs only when bridge sources change. Non-macOS targets are a no-op.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final codeConfig = input.config.code;
    if (codeConfig.targetOS != OS.macOS ||
        codeConfig.linkModePreference == LinkModePreference.static) {
      return;
    }

    const minMacos = '13.0';
    final arch = switch (codeConfig.targetArchitecture) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'x86_64',
      _ => throw UnsupportedError(
        'Unsupported architecture: ${codeConfig.targetArchitecture}',
      ),
    };
    final target = '$arch-apple-macos$minMacos';

    final libPath =
        '${input.outputDirectory.toFilePath()}/libxs_ax_driver.dylib';
    final result = await Process.run('swiftc', [
      '-emit-library',
      '-o',
      libPath,
      '-target',
      target,
      '-sdk',
      await _macosSdkPath(),
      '-framework',
      'ApplicationServices',
      '-framework',
      'CoreGraphics',
      '-framework',
      'ImageIO',
      '-framework',
      'Foundation',
      '-parse-as-library',
      'bridge/src/driver_bridge.swift',
    ]);

    if (result.exitCode != 0) {
      stderr
        ..writeln(result.stdout)
        ..writeln(result.stderr);
      throw Exception('swiftc failed with exit code ${result.exitCode}');
    }

    // Keep the path-loader's preferred candidate fresh (the stale-dylib
    // finding from ADR 0001): the loader resolves `.dart_tool/lib/`
    // FIRST, but only the code-asset path is updated by the native-assets
    // pipeline. If the code asset is used, this copy is simply ignored.
    final staleCandidate = Directory('.dart_tool/lib');
    if (staleCandidate.existsSync()) {
      try {
        await File(
          libPath,
        ).copy('${staleCandidate.path}/libxs_ax_driver.dylib');
      } on Object catch (e) {
        stderr.writeln(
          '[xs_ax_driver hook] stale-candidate refresh skipped: $e',
        );
      }
    }

    output.dependencies.addAll([Uri.file('bridge/src/driver_bridge.swift')]);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'xs_ax_driver',
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
