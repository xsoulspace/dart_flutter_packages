import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'vosk_raw_exception.dart';

enum VoskRawDesktopPlatform { windows, macos, linux }

final class VoskRawRuntimeConfig {
  const VoskRawRuntimeConfig({
    this.libraryPath,
    this.librarySearchPaths = const <String>[],
    this.modelDirectory,
  });

  final String? libraryPath;
  final List<String> librarySearchPaths;
  final String? modelDirectory;
}

final class VoskRawLibraryLoader {
  VoskRawLibraryLoader({required this.runtimeConfig, this.platformOverride});

  final VoskRawRuntimeConfig runtimeConfig;
  final VoskRawDesktopPlatform? platformOverride;

  static bool isSupportedPlatform() =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  VoskRawDesktopPlatform get _platform {
    if (platformOverride != null) {
      return platformOverride!;
    }
    if (Platform.isMacOS) {
      return VoskRawDesktopPlatform.macos;
    }
    if (Platform.isLinux) {
      return VoskRawDesktopPlatform.linux;
    }
    if (Platform.isWindows) {
      return VoskRawDesktopPlatform.windows;
    }
    throw const VoskRawException(
      code: 'task_unsupported',
      message: 'Vosk supports macOS, Linux, and Windows only',
    );
  }

  static List<String> libraryNamesFor(final VoskRawDesktopPlatform platform) {
    switch (platform) {
      case VoskRawDesktopPlatform.macos:
        return const <String>['libvosk.dylib'];
      case VoskRawDesktopPlatform.linux:
        return const <String>['libvosk.so'];
      case VoskRawDesktopPlatform.windows:
        return const <String>['vosk.dll', 'libvosk.dll'];
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
      if ((runtimeConfig.modelDirectory ?? '').trim().isNotEmpty)
        runtimeConfig.modelDirectory!.trim(),
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
    throw VoskRawException(
      code: 'engine_unavailable',
      message: 'Unable to load the Vosk runtime library',
      details: failures,
    );
  }
}
