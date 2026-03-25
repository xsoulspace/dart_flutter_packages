import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'whisper_cpp_raw_exception.dart';

enum WhisperCppRawDesktopPlatform { windows, macos, linux }

final class WhisperCppRawRuntimeConfig {
  const WhisperCppRawRuntimeConfig({
    this.libraryPath,
    this.librarySearchPaths = const <String>[],
    this.modelsDirectory,
  });

  final String? libraryPath;
  final List<String> librarySearchPaths;
  final String? modelsDirectory;
}

final class WhisperCppRawLibraryLoader {
  WhisperCppRawLibraryLoader({
    required this.runtimeConfig,
    this.platformOverride,
  });

  final WhisperCppRawRuntimeConfig runtimeConfig;
  final WhisperCppRawDesktopPlatform? platformOverride;

  static bool isSupportedPlatform() =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  WhisperCppRawDesktopPlatform get _platform {
    if (platformOverride != null) {
      return platformOverride!;
    }
    if (Platform.isMacOS) {
      return WhisperCppRawDesktopPlatform.macos;
    }
    if (Platform.isLinux) {
      return WhisperCppRawDesktopPlatform.linux;
    }
    if (Platform.isWindows) {
      return WhisperCppRawDesktopPlatform.windows;
    }
    throw const WhisperCppRawException(
      code: 'task_unsupported',
      message: 'whisper.cpp supports macOS, Linux, and Windows only',
    );
  }

  static List<String> libraryNamesFor(
    final WhisperCppRawDesktopPlatform platform,
  ) {
    switch (platform) {
      case WhisperCppRawDesktopPlatform.macos:
        return const <String>['libwhisper.dylib', 'libwhisper_cpp.dylib'];
      case WhisperCppRawDesktopPlatform.linux:
        return const <String>['libwhisper.so', 'libwhisper_cpp.so'];
      case WhisperCppRawDesktopPlatform.windows:
        return const <String>['whisper.dll', 'whisper_cpp.dll'];
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
    throw WhisperCppRawException(
      code: 'engine_unavailable',
      message: 'Unable to load the whisper.cpp runtime library',
      details: failures,
    );
  }
}
