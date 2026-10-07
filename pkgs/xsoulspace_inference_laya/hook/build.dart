import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook: builds the native Laya runtime (the Swift + MLX SPM package
/// under `native/laya_native`) and registers the dylib as a CODE asset so
/// the `@Native(assetId:)` bindings resolve without path hunting — the
/// ADR 0001 pattern, proven in `universal_capture_macos`.
///
/// MLX resolves its Metal kernels COLOCATED with the loaded dylib, and a
/// bare dart process has no SwiftPM bundle for the bundle fallback, so the
/// `mlx.metallib` is copied beside every load candidate: the hook output
/// directory, the resolving workspace's `.dart_tool/lib` (the dlopen-
/// preferred candidate the pipeline populates), and — as a DATA asset —
/// the application bundle that `dart build cli` produces.
///
/// Runs automatically on `dart run/build/test`; SPM makes the rebuild
/// incremental (seconds once warm). Honest degradation: when the Apple
/// toolchain (swiftc + Metal Toolchain) is unavailable, the hook registers
/// no asset and prints one warning — the Dart package still analyzes and
/// its scripted tests still pass; the golden test skips with that reason.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final buildCode = input.config.buildCodeAssets;
    final buildData = input.config.buildDataAssets;
    if (!buildCode && !buildData) return;

    if (buildCode) {
      final codeConfig = input.config.code;
      if (codeConfig.targetOS != OS.macOS ||
          codeConfig.linkModePreference == LinkModePreference.static) {
        return;
      }
    }

    // Resolve the SPM tree from the input's packageRoot, never from a cwd
    // guess: a wrong workingDirectory turns the `swift build` invocation
    // into "No such file or directory" and crashes the hook instead of
    // skipping.
    final packageRoot = input.packageRoot.toFilePath();
    final spmRoot = '$packageRoot/native/laya_native';
    final dylib = '$spmRoot/.build/release/libLayaNative.dylib';
    final metallibSource =
        '$spmRoot/.build/release/mlx-swift_Cmlx.bundle/Contents/Resources/'
        'default.metallib';

    if (!Directory(spmRoot).existsSync()) {
      stderr.writeln(
        '[laya hook] no native tree at $spmRoot; registering no native '
        'asset — the model engine stays unavailable (named skip)',
      );
      return;
    }

    if (buildCode) {
      final probe = await Process.run('swiftc', ['--version']);
      if (probe.exitCode != 0) {
        stderr.writeln(
          '[laya hook] swiftc unavailable (${probe.exitCode}); registering '
          'no native asset — the model engine stays unavailable (named '
          'skip)',
        );
        return;
      }
      // The hook may be invoked concurrently (build + test lanes share the
      // workspace .dart_tool); SPM's on-disk build dir tolerates exactly
      // one builder. Serialize, and retry once when a racing build
      // invalidated SPM's state mid-run ("File modified during build").
      final lockFile = File('$spmRoot/.build/hook.lock');
      lockFile.parent.createSync(recursive: true);
      final lock = lockFile.openSync(mode: FileMode.write)
        ..lockSync(FileLock.exclusive);
      var dylibReady = false;
      try {
        for (var attempt = 0; attempt < 2 && !dylibReady; attempt++) {
          final build = await Process.run('swift', ['build', '-c', 'release'],
              workingDirectory: spmRoot);
          if (build.exitCode != 0) {
            stderr.writeln('[laya hook] swift build failed:');
            stderr.writeln(build.stdout);
            stderr.writeln(build.stderr);
            if (attempt == 1) {
              stderr.writeln(
                '[laya hook] registering no native asset — the model engine '
                'stays unavailable (named skip). The Metal Toolchain '
                'installs with: xcodebuild -downloadComponent '
                'MetalToolchain',
              );
              return;
            }
            continue;
          }
          final built = File(dylib);
          dylibReady = built.existsSync() && built.lengthSync() > 0;
        }
      } finally {
        lock.unlockSync();
        lock.closeSync();
        lockFile.deleteSync();
      }
      if (!dylibReady) {
        stderr.writeln('[laya hook] no dylib after build; registering no '
            'native asset (named skip)');
        return;
      }
    }

    // Colocate dylib + metallib in the hook output directory.
    final dylibName = dylib.split('/').last;
    final bundledDylib = '${input.outputDirectory.toFilePath()}/$dylibName';
    final bundledMetallib =
        '${input.outputDirectory.toFilePath()}/mlx.metallib';
    if (buildCode) {
      await File(dylib).copy(bundledDylib);
    }
    var metallibReady = false;
    if (File(metallibSource).existsSync()) {
      await File(metallibSource).copy(bundledMetallib);
      metallibReady = true;
    } else {
      stderr.writeln('[laya hook] warning: no metallib at $metallibSource '
          '— GPU ops will fail without it');
    }

    // Refresh the resolving workspace's `.dart_tool/lib` (the dlopen-
    // preferred candidate the pipeline populates with registered files).
    // Atomic temp+rename: a concurrent pipeline copy must never observe a
    // truncated file.
    Directory? dartTool;
    var dir = input.outputDirectory.toFilePath();
    while (dir != Directory(dir).parent.path) {
      dir = Directory(dir).parent.path;
      if (dir.endsWith('.dart_tool/') || dir.endsWith('.dart_tool')) {
        dartTool = Directory(dir);
        break;
      }
    }
    final refreshTargets = <Directory>[
      if (dartTool != null) Directory('${dartTool.path}/lib'),
      // The fleet cache is the deploy-free load location for preloads
      // (`dart compile exe` has no code-asset manifest; the engine's
      // resolver ends here).
      Directory('~/.cache/xsoulspace/laya/native'.replaceFirst(
          '~', Platform.environment['HOME'] ?? '/tmp')),
    ];
    for (final loadDir in refreshTargets) {
      if (!loadDir.existsSync()) {
        loadDir.createSync(recursive: true);
      }
      for (final source in [
        if (buildCode) bundledDylib,
        if (metallibReady) bundledMetallib,
      ]) {
        final name = source.split('/').last;
        final temp =
            '${loadDir.path}/.$name.laya-hook-${DateTime.now().microsecondsSinceEpoch}';
        await File(source).copy(temp);
        await File(temp).rename('${loadDir.path}/$name');
      }
    }

    // Declare the whole source tree so source edits re-trigger the hook.
    await for (final entry
        in Directory('$spmRoot/Sources').list(recursive: true)) {
      if (entry is File && entry.path.endsWith('.swift')) {
        output.dependencies.add(Uri.file(entry.path));
      }
    }
    output.dependencies.add(Uri.file('$spmRoot/Package.swift'));

    if (buildCode) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'laya_native',
          file: Uri.file(bundledDylib),
          linkMode: DynamicLoadingBundled(),
        ),
      );
    }
    if (buildData && metallibReady) {
      // Registered as a DATA asset so application builders bundle the
      // metallib with the app (`dart build cli` places it beside the
      // dynamic libraries) and MLX finds its kernels wherever the bundle
      // lands.
      output.assets.data.add(
        DataAsset(
          package: input.packageName,
          name: 'mlx.metallib',
          file: Uri.file(bundledMetallib),
        ),
      );
    }
  });
}
