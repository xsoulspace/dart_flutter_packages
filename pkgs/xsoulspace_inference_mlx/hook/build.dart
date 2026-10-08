import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook: builds the native MLX text runtime (the Swift package under
/// `native/mlx_text_native`, which wraps ml-explore/mlx-swift-lm) and
/// registers the dylib as a CODE asset so the `@Native(assetId:)` bindings
/// resolve without path hunting — the same ADR-0001-pattern hook laya uses.
///
/// MLX resolves its Metal kernels COLOCATED with the loaded dylib, so the
/// Cmlx resource bundle's `default.metallib` is copied beside every load
/// candidate: the hook output directory, the resolving workspace's
/// `.dart_tool/lib`, and — as a DATA asset — the application bundle that
/// `dart build cli` produces.
///
/// Runs automatically on `dart run/build/test`; SPM makes the rebuild
/// incremental (seconds once warm; the first build compiles MLX's C++/Metal
/// core — minutes). Honest degradation: when the Apple toolchain
/// (swiftc) is unavailable, the hook registers no asset and prints one
/// warning — the Dart package still analyzes and its scripted tests still
/// pass; the native test skips with that reason.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // Declare the source tree FIRST — a hook run that early-returns (named
    // skip, failed swift build) must still register its inputs, or the
    // runner caches an input-less result and never re-runs on Swift source
    // edits (paid for twice: laya hook first, then here).
    final packageRoot = input.packageRoot.toFilePath();
    final spmRoot = '$packageRoot/native/mlx_text_native';
    final dylib = '$spmRoot/.build/release/libMlxTextNative.dylib';
    final sources = Directory('$spmRoot/Sources');
    if (sources.existsSync()) {
      await for (final entry in sources.list(recursive: true)) {
        if (entry is File && entry.path.endsWith('.swift')) {
          output.dependencies.add(Uri.file(entry.path));
        }
      }
      output.dependencies.add(Uri.file('$spmRoot/Package.swift'));
    }

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
    if (!Directory(spmRoot).existsSync()) {
      stderr.writeln(
        '[mlx hook] no native tree at $spmRoot; registering no native '
        'asset — the native engine stays unavailable (named skip)',
      );
      return;
    }

    if (buildCode) {
      final probe = await Process.run('swiftc', ['--version']);
      if (probe.exitCode != 0) {
        stderr.writeln(
          '[mlx hook] swiftc unavailable (${probe.exitCode}); registering '
          'no native asset — the native engine stays unavailable (named '
          'skip)',
        );
        return;
      }
      // Serialize exactly like the laya hook: SPM's on-disk build dir
      // tolerates exactly one builder; retry once on racing invalidation.
      final lockFile = File('$spmRoot/.build/hook.lock');
      lockFile.parent.createSync(recursive: true);
      final lock = lockFile.openSync(mode: FileMode.write)
        ..lockSync(FileLock.exclusive);
      var dylibReady = false;
      try {
        for (var attempt = 0; attempt < 2 && !dylibReady; attempt++) {
          final build = await Process.run('swift', [
            'build',
            '-c',
            'release',
            // The native-assets pipeline rewrites the dylib's install name
            // and rpaths to their final (long) paths; without link-time
            // padding the rewrite overflows the Mach-O header and the
            // whole run dies before its first test (paid for in the laya
            // hook first).
            '-Xlinker',
            '-headerpad_max_install_names',
          ], workingDirectory: spmRoot);
          if (build.exitCode != 0) {
            stderr.writeln('[mlx hook] swift build failed:');
            stderr.writeln(build.stdout);
            stderr.writeln(build.stderr);
            if (attempt == 1) {
              stderr.writeln(
                '[mlx hook] registering no native asset — the native '
                'engine stays unavailable (named skip)',
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
        stderr.writeln(
          '[mlx hook] no dylib after build; registering no native asset '
          '(named skip)',
        );
        return;
      }
    }

    // MLX's Metal kernels ship inside mlx-swift's Cmlx resource bundle;
    // find the newest one under the SPM build tree and colocate it.
    final metallibSource = _findMetallib(spmRoot);
    if (metallibSource == null) {
      stderr.writeln(
        '[mlx hook] warning: no Cmlx default.metallib found under '
        '$spmRoot/.build — GPU ops will fail without it',
      );
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
    if (metallibSource != null) {
      await File(metallibSource).copy(bundledMetallib);
      metallibReady = true;
    }

    // Refresh the resolving workspace's `.dart_tool/lib` (the dlopen-
    // preferred candidate the pipeline populates with registered files).
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
      Directory(
        '~/.cache/xsoulspace/mlx_text/native'.replaceFirst(
          '~',
          Platform.environment['HOME'] ?? '/tmp',
        ),
      ),
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
            '${loadDir.path}/.mlx-hook-${DateTime.now().microsecondsSinceEpoch}';
        await File(source).copy(temp);
        await File(temp).rename('${loadDir.path}/$name');
      }
    }

    // Declare the whole source tree so source edits re-trigger the hook.
    // (Also declared at the top for the early-return paths.)

    if (buildCode) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'mlx_text_native',
          file: Uri.file(bundledDylib),
          linkMode: DynamicLoadingBundled(),
        ),
      );
    }
    if (buildData && metallibReady) {
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

/// The newest Cmlx resource-bundle metallib under [spmRoot]/.build.
String? _findMetallib(final String spmRoot) {
  final buildDir = Directory('$spmRoot/.build');
  if (!buildDir.existsSync()) return null;
  String? best;
  var bestModified = DateTime.fromMillisecondsSinceEpoch(0);
  for (final entry in buildDir.listSync(recursive: true)) {
    if (entry is! File) continue;
    if (!entry.path.endsWith(
          '/Cmlx.bundle/Contents/Resources/default.metallib',
        ) &&
        !entry.path.endsWith(
          'Cmlx.bundle/Contents/Resources/default.metallib',
        )) {
      continue;
    }
    final modified = entry.statSync().modified;
    if (best == null || modified.isAfter(bestModified)) {
      best = entry.path;
      bestModified = modified;
    }
  }
  return best;
}
