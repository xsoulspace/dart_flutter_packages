import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'sherpa_onnx_raw_exception.dart';

enum SherpaOnnxRawDesktopPlatform { windows, macos, linux }

final class SherpaOnnxRawRuntimeConfig {
  const SherpaOnnxRawRuntimeConfig({
    this.libraryPath,
    this.librarySearchPaths = const <String>[],
    this.modelsDirectory,
  });

  final String? libraryPath;
  final List<String> librarySearchPaths;
  final String? modelsDirectory;
}

final class SherpaOnnxRawLibraryLoader {
  SherpaOnnxRawLibraryLoader({
    required this.runtimeConfig,
    this.platformOverride,
  });

  final SherpaOnnxRawRuntimeConfig runtimeConfig;
  final SherpaOnnxRawDesktopPlatform? platformOverride;

  static bool isSupportedPlatform() =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  SherpaOnnxRawDesktopPlatform get _platform {
    if (platformOverride != null) {
      return platformOverride!;
    }
    if (Platform.isMacOS) {
      return SherpaOnnxRawDesktopPlatform.macos;
    }
    if (Platform.isLinux) {
      return SherpaOnnxRawDesktopPlatform.linux;
    }
    if (Platform.isWindows) {
      return SherpaOnnxRawDesktopPlatform.windows;
    }
    throw const SherpaOnnxRawException(
      code: 'task_unsupported',
      message: 'Sherpa-ONNX supports macOS, Linux, and Windows only',
    );
  }

  static List<String> libraryNamesFor(
    final SherpaOnnxRawDesktopPlatform platform,
  ) {
    switch (platform) {
      case SherpaOnnxRawDesktopPlatform.macos:
        return const <String>[
          'libsherpa-onnx-c-api.dylib',
          'libsherpa-onnx.dylib',
        ];
      case SherpaOnnxRawDesktopPlatform.linux:
        return const <String>['libsherpa-onnx-c-api.so', 'libsherpa-onnx.so'];
      case SherpaOnnxRawDesktopPlatform.windows:
        return const <String>['sherpa-onnx-c-api.dll', 'sherpa-onnx.dll'];
    }
  }

  List<String> candidateLibraryPaths() {
    final names = libraryNamesFor(_platform);
    final roots = <String>[
      if ((runtimeConfig.libraryPath ?? '').trim().isNotEmpty)
        runtimeConfig.libraryPath!.trim(),
      ...runtimeConfig.librarySearchPaths.where(
        (final value) => value.trim().isNotEmpty,
      ),
      if ((runtimeConfig.modelsDirectory ?? '').trim().isNotEmpty)
        runtimeConfig.modelsDirectory!.trim(),
      Directory.current.path,
      p.dirname(Platform.resolvedExecutable),
    ];
    final candidates = <String>[];
    for (final root in roots) {
      final looksLikeLibrary = names.any((final name) => root.endsWith(name));
      if (looksLikeLibrary) {
        candidates.add(root);
        continue;
      }
      for (final name in names) {
        candidates.add(p.join(root, name));
      }
    }
    return candidates.toSet().toList(growable: false);
  }

  String? resolveExistingLibraryPath() {
    for (final candidate in candidateLibraryPaths()) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  DynamicLibrary load() {
    final failures = <String>[];
    for (final candidate in candidateLibraryPaths()) {
      try {
        return DynamicLibrary.open(candidate);
      } on Object catch (error) {
        failures.add('$candidate -> $error');
      }
    }
    throw SherpaOnnxRawException(
      code: 'engine_unavailable',
      message: 'Unable to load the Sherpa-ONNX runtime library',
      details: failures,
    );
  }
}
