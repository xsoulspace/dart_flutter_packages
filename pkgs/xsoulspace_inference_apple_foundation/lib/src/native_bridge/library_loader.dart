// Path-based loader for the bridge dylib. The code-asset path
// (`DynamicLibrary.codeAsset`, SDK 3.14+) is not yet available on the
// workspace SDK (3.12); when the SDK is bumped, prefer code assets and keep
// this as fallback.
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the native bridge library.
///
/// Strategy:
/// 1. **Code asset (preferred):** `hook/build.dart` registers
///    `package:xsoulspace_inference_apple_foundation/swift_bridge`; the Dart
///    runtime resolves it via `DynamicLibrary.codeAsset`. Used automatically
///    by `@Native` bindings in `native_bindings.dart` — no code needed here.
/// 2. **Fallback:** explicit path → `XS_FM_BRIDGE_PATH` env var → executable
///    dir / build dir / cwd. Used when code assets can't be loaded (Flutter
///    under Dart 3.13) or for prebuilt dylibs outside the hook.
final class XsFmLibraryLoader {
  XsFmLibraryLoader({this.overridePath});

  final String? overridePath;

  static const String dylibName = 'libxs_fm_bridge.dylib';

  /// Asset ID registered by `hook/build.dart`.
  static const String assetId =
      'package:xsoulspace_inference_apple_foundation/swift_bridge';

  List<String> candidatePaths() {
    final candidates = <String>[
      if (overridePath != null) overridePath!,
      if (Platform.environment['XS_FM_BRIDGE_PATH'] case final envPath?)
        envPath,
      // Build-hook output (preferred — always fresh).
      p.join(Directory.current.path, '.dart_tool', 'lib', dylibName),
      p.join(p.dirname(Platform.resolvedExecutable), dylibName),
      p.join(Directory.current.path, 'build', dylibName),
      p.join(Directory.current.path, dylibName),
    ];
    return candidates.toSet().toList(growable: false);
  }

  /// Opens the bridge library.
  ///
  /// Path-based loading first (works on all supported SDKs). When the
  /// workspace SDK reaches 3.14+ and `DynamicLibrary.codeAsset` exists, the
  /// code-asset path in `native_bindings.dart` takes precedence instead —
  /// see `AppleFoundationNativeClient._b` for the resolution order.
  DynamicLibrary load() => loadFromPath();

  /// Path-based loading only (no code-asset attempt).
  DynamicLibrary loadFromPath() {
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
