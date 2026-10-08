import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

/// Build hook: builds the native Laya runtime — a Rust cdylib statically
/// linking the pinned mlx 0.32.2 + mlx-c sources (ADR 0051) — and registers
/// it as a CODE asset so the `@Native(assetId:)` bindings resolve without
/// path hunting. The Swift + mlx-swift SPM tree under `native/laya_native`
/// is no longer built on macOS; it stays as the documented iOS reference
/// (ml-explore/mlx#3915 blocks the CMake route there).
///
/// MLX resolves its Metal kernels COLOCATED with the loaded dylib, and a
/// bare dart process has no bundle fallback, so the `mlx.metallib` is copied
/// beside every load candidate: the hook output directory, the resolving
/// workspace's `.dart_tool/lib`, and — as a DATA asset — the application
/// bundle that `dart build cli` produces.
///
/// Toolchain needs (first build only): cargo, cmake, and the Metal Toolchain
/// (`xcodebuild -downloadComponent MetalToolchain`). The mlx/mlx-c cmake
/// builds are incremental — seconds once warm. Honest degradation: when the
/// toolchain is unavailable, the hook registers no asset and prints one
/// warning — the Dart package still analyzes and its scripted tests still
/// pass; the golden test skips with that reason.
void main(List<String> args) async {
  await build(args, (input, output) async {
    // Declare the source tree FIRST — a hook run that early-returns (named
    // skip) must still register its inputs, or the runner caches an
    // input-less result and never re-runs on Rust source edits.
    final packageRoot = input.packageRoot.toFilePath();
    final rustRoot = '$packageRoot/native/laya_rust';
    final sources = Directory('$rustRoot/src');
    if (sources.existsSync()) {
      await for (final entry in sources.list(recursive: true)) {
        if (entry is File && entry.path.endsWith('.rs')) {
          output.dependencies.add(Uri.file(entry.path));
        }
      }
    }
    output.dependencies.add(Uri.file('$rustRoot/Cargo.toml'));
    output.dependencies.add(Uri.file('$rustRoot/build.rs'));
    output.dependencies.add(Uri.file('$rustRoot/Cargo.lock'));

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

    // Resolve from the input's packageRoot, never from a cwd guess.
    final mlxBuildRoot = '$rustRoot/build';
    final dylib = '$rustRoot/target/release/liblaya_native.dylib';
    final metallibSource = '$mlxBuildRoot/mlx-install/lib/mlx.metallib';

    if (!Directory(rustRoot).existsSync()) {
      stderr.writeln(
        '[laya hook] no native tree at $rustRoot; registering no native '
        'asset — the model engine stays unavailable (named skip)',
      );
      return;
    }

    if (buildCode) {
      final probe = await Process.run('cargo', ['--version']);
      if (probe.exitCode != 0) {
        stderr.writeln(
          '[laya hook] cargo unavailable (${probe.exitCode}); registering '
          'no native asset — the model engine stays unavailable (named '
          'skip). Rust installs with: rustup',
        );
        return;
      }
      final bootstrapped = await _ensureMlxArtifacts(mlxBuildRoot);
      if (!bootstrapped) {
        stderr.writeln(
          '[laya hook] mlx/mlx-c build failed (see logs under '
          '$mlxBuildRoot); registering no native asset — the model engine '
          'stays unavailable (named skip). The Metal Toolchain installs '
          'with: xcodebuild -downloadComponent MetalToolchain',
        );
        return;
      }

      final build = await Process.run(
        'cargo',
        ['build', '--release'],
        workingDirectory: rustRoot,
        environment: {'LAYA_MLX_BUILD_DIR': mlxBuildRoot},
      );
      if (build.exitCode != 0) {
        stderr.writeln('[laya hook] cargo build failed:');
        stderr.writeln(build.stdout);
        stderr.writeln(build.stderr);
        stderr.writeln(
          '[laya hook] registering no native asset — the model engine '
          'stays unavailable (named skip)',
        );
        return;
      }
      final built = File(dylib);
      if (!built.existsSync() || built.lengthSync() == 0) {
        stderr.writeln('[laya hook] no dylib after cargo build; registering '
            'no native asset (named skip)');
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
    final metallibFile = await _strippedMetallib(metallibSource);
    var metallibReady = metallibFile != null;
    if (metallibFile != null) {
      await metallibFile.copy(bundledMetallib);
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

/// The metallib to bundle: a cached `metal-strip`ped sibling of [source], or
/// [source] itself when the Metal toolchain lacks `metal-strip` (named
/// warning; GPU ops still work, the bundle just stays fat).
///
/// The cryptex Metal toolchain embeds full per-module AIR in `mlx.metallib`
/// (183.8 MB for the pinned 0.32.2 build); Apple's own reducer —
/// `metal-strip -S -T --compress-sections=MODULE_LIST` — brings it to
/// ~140 MB and the result is golden-proven identical (63/63, prob error 0.0).
/// The strip costs ~50 s, so it runs once per source rebuild: the result is
/// cached beside the source with an mtime+size sentinel and reused until the
/// cmake-built source changes. Idempotent by construction — the sentinel is
/// only rewritten after a successful fresh strip of the current source.
Future<File?> _strippedMetallib(String source) async {
  final src = File(source);
  if (!src.existsSync()) return null;
  final stat = src.statSync();
  final sentinel = '$source.stripped.meta';
  final stripped = File('$source.stripped');
  final sentinelBody = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  if (stripped.existsSync() &&
      stripped.lengthSync() > 0 &&
      File(sentinel).existsSync() &&
      File(sentinel).readAsStringSync() == sentinelBody) {
    return stripped;
  }
  final probe = await Process.run('xcrun', ['-find', 'metal-strip']);
  if (probe.exitCode != 0) {
    stderr.writeln('[laya hook] warning: metal-strip unavailable — bundling '
        'the unstripped metallib (${stat.size ~/ (1024 * 1024)} MB)');
    return src;
  }
  final temp = File('$source.stripped.tmp');
  await src.copy(temp.path);
  final strip = await Process.run(probe.stdout.toString().trim(), [
    '-S',
    '-T',
    '--compress-sections=MODULE_LIST',
    temp.path,
  ]);
  if (strip.exitCode != 0 || !temp.existsSync() || temp.lengthSync() == 0) {
    stderr.writeln('[laya hook] warning: metal-strip failed '
        '(${strip.exitCode}) — bundling the unstripped metallib');
    stderr.writeln(strip.stderr);
    if (temp.existsSync()) temp.deleteSync();
    return src;
  }
  await temp.rename(stripped.path);
  await File(sentinel).writeAsString(sentinelBody);
  return stripped;
}

/// Configures + builds mlx and mlx-c once into `$mlxBuildRoot/{mlx,mlxc}-install`
/// (incremental afterwards). Returns false with named logs on failure.
Future<bool> _ensureMlxArtifacts(String mlxBuildRoot) async {
  if (File('$mlxBuildRoot/mlxc-install/lib/libmlxc.a').existsSync() &&
      File('$mlxBuildRoot/mlx-install/lib/libmlx.a').existsSync() &&
      File('$mlxBuildRoot/mlx-install/lib/mlx.metallib').existsSync()) {
    return true;
  }
  // The pinned sources: the mlx-swift checkout built by the historical
  // SPM path carries the exact mlx 0.32.2 tree the goldens were generated
  // against. When absent (clean checkout), point LAYA_MLX_SOURCE at a
  // matching mlx source tree.
  final sourceRoot = Platform.environment['LAYA_MLX_SOURCE'];
  if (sourceRoot == null || !Directory(sourceRoot).existsSync()) {
    stderr.writeln(
      '[laya hook] LAYA_MLX_SOURCE not set or missing — point it at the '
      'pinned mlx 0.32.2 source tree (the mlx-swift Cmlx checkout: '
      'native/laya_native/.build/checkouts/mlx-swift/Source/Cmlx/mlx); '
      'skipping the native asset (named skip)',
    );
    return false;
  }
  final cmakeProbe = await Process.run('cmake', ['--version']);
  if (cmakeProbe.exitCode != 0) {
    stderr.writeln('[laya hook] cmake unavailable — cannot build mlx (named skip)');
    return false;
  }
  final env = {
    ...Platform.environment,
    'CMAKE_OSX_ARCHITECTURES': 'arm64',
  };
  Future<int> run(String executable, List<String> arguments, String log) =>
      Process.run(executable, arguments,
              workingDirectory: mlxBuildRoot, environment: env)
          .then((result) async {
        await File('$mlxBuildRoot/$log')
            .writeAsString('${result.stdout}\n${result.stderr}');
        return result.exitCode;
      });

  await Directory(mlxBuildRoot).create(recursive: true);
  if (!File('$mlxBuildRoot/mlx-install/lib/libmlx.a').existsSync()) {
    if (await run('cmake', [
          '-S', sourceRoot,
          '-B', 'mlx',
          '-DCMAKE_BUILD_TYPE=Release',
          '-DMLX_BUILD_TESTS=OFF',
          '-DMLX_BUILD_EXAMPLES=OFF',
          '-DMLX_BUILD_BENCHMARKS=OFF',
          '-DMLX_BUILD_PYTHON_BINDINGS=OFF',
          '-DBUILD_SHARED_LIBS=OFF',
          '-DCMAKE_INSTALL_PREFIX=$mlxBuildRoot/mlx-install',
        ], 'mlx-configure.log') !=
        0) {
      return false;
    }
    if (await run('cmake', ['--build', 'mlx', '-j', '8'], 'mlx-build.log') != 0) {
      return false;
    }
    if (await run('cmake', ['--install', 'mlx'], 'mlx-install.log') != 0) {
      return false;
    }
  }
  if (!File('$mlxBuildRoot/mlxc-install/lib/libmlxc.a').existsSync()) {
    final mlxcSource = '$sourceRoot/../mlx-c';
    if (!Directory(mlxcSource).existsSync()) {
      stderr.writeln(
        '[laya hook] mlx-c sources not found next to LAYA_MLX_SOURCE '
        '($mlxcSource) — skipping the native asset (named skip)',
      );
      return false;
    }
    if (await run('cmake', [
          '-S', mlxcSource,
          '-B', 'mlxc',
          '-DCMAKE_BUILD_TYPE=Release',
          '-DCMAKE_PREFIX_PATH=$mlxBuildRoot/mlx-install',
          '-DCMAKE_INSTALL_PREFIX=$mlxBuildRoot/mlxc-install',
        ], 'mlxc-configure.log') !=
        0) {
      return false;
    }
    if (await run('cmake', ['--build', 'mlxc', '-j', '8'], 'mlxc-build.log') != 0) {
      return false;
    }
    if (await run('cmake', ['--install', 'mlxc'], 'mlxc-install.log') != 0) {
      return false;
    }
  }
  return true;
}
