import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves and loads the native bridge dylib.
///
/// Search order:
/// 1. explicit [overridePath]
/// 2. `XS_FM_BRIDGE_PATH` environment variable
/// 3. executable directory, then working directory, for the platform name
final class XsFmLibraryLoader {
  XsFmLibraryLoader({this.overridePath});

  final String? overridePath;

  static const String dylibName = 'libxs_fm_bridge.dylib';

  List<String> candidatePaths() {
    final candidates = <String>[
      if (overridePath != null) overridePath!,
      if (Platform.environment['XS_FM_BRIDGE_PATH'] case final envPath?)
        envPath,
      p.join(p.dirname(Platform.resolvedExecutable), dylibName),
      p.join(Directory.current.path, 'build', dylibName),
      p.join(Directory.current.path, dylibName),
    ];
    return candidates.toSet().toList(growable: false);
  }

  DynamicLibrary load() {
    final failures = <String>[];
    for (final candidate in candidatePaths()) {
      try {
        return DynamicLibrary.open(candidate);
      } on Object catch (error) {
        failures.add('$candidate -> $error');
      }
    }
    throw StateError(
      'Unable to load $dylibName. Checked ${candidatePaths().length} path(s):\n'
      '${failures.join('\n')}',
    );
  }
}
