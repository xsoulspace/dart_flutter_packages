import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'steam_raw_exception.dart';

/// Desktop targets supported by Steamworks runtime loading.
enum SteamDesktopPlatform {
  windows,
  macos,
  linux;

  static SteamDesktopPlatform fromRuntime() {
    if (Platform.isWindows) {
      return SteamDesktopPlatform.windows;
    }
    if (Platform.isMacOS) {
      return SteamDesktopPlatform.macos;
    }
    if (Platform.isLinux) {
      return SteamDesktopPlatform.linux;
    }
    throw const SteamRawException(
      code: SteamRawErrorCode.unsupportedPlatform,
      message: 'Steamworks is supported on Windows, macOS, and Linux only.',
    );
  }
}

/// Loads Steamworks runtime library (`steam_api`) from explicit or default paths.
final class SteamRawLibraryLoader {
  SteamRawLibraryLoader({
    this.librarySearchPaths = const <String>[],
    this.platformOverride,
  });

  final List<String> librarySearchPaths;
  final SteamDesktopPlatform? platformOverride;

  SteamDesktopPlatform get _platform =>
      platformOverride ?? SteamDesktopPlatform.fromRuntime();

  /// Platform library names in resolution order.
  static List<String> libraryNamesFor(final SteamDesktopPlatform platform) {
    switch (platform) {
      case SteamDesktopPlatform.windows:
        return const <String>['steam_api64.dll', 'steam_api.dll'];
      case SteamDesktopPlatform.macos:
        return const <String>['libsteam_api.dylib'];
      case SteamDesktopPlatform.linux:
        return const <String>['libsteam_api.so'];
    }
  }

  /// Default directories searched after explicit overrides.
  List<String> defaultSearchDirectories() {
    final executableDir = p.dirname(Platform.resolvedExecutable);
    final currentDir = Directory.current.path;
    return <String>{currentDir, executableDir}.toList(growable: false);
  }

  /// Candidate full paths that will be attempted by [load].
  List<String> candidateLibraryPaths() {
    final names = libraryNamesFor(_platform);
    final candidates = <String>[];

    void addPath(final String value) {
      if (value.trim().isEmpty) {
        return;
      }
      candidates.add(value);
    }

    for (final rawPath in librarySearchPaths) {
      final candidate = rawPath.trim();
      if (candidate.isEmpty) {
        continue;
      }
      final looksLikeFile = names.any(
        (final libName) =>
            candidate.endsWith(libName) ||
            candidate.toLowerCase().endsWith('.dll') ||
            candidate.toLowerCase().endsWith('.dylib') ||
            candidate.toLowerCase().endsWith('.so'),
      );
      if (looksLikeFile) {
        addPath(candidate);
        continue;
      }
      for (final name in names) {
        addPath(p.join(candidate, name));
      }
    }

    for (final dir in defaultSearchDirectories()) {
      for (final name in names) {
        addPath(p.join(dir, name));
      }
    }

    return candidates.toSet().toList(growable: false);
  }

  /// Loads `steam_api` dynamic library from candidate paths.
  DynamicLibrary load() {
    final failures = <String>[];
    for (final candidate in candidateLibraryPaths()) {
      try {
        return DynamicLibrary.open(candidate);
      } on Object catch (error) {
        failures.add('$candidate -> $error');
      }
    }

    throw SteamRawException(
      code: SteamRawErrorCode.libraryNotFound,
      message:
          'Unable to load Steam runtime library. Checked ${candidateLibraryPaths().length} path(s).',
      cause: failures.join('\n'),
    );
  }
}
