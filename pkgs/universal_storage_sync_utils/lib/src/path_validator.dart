// ignore_for_file: avoid_catches_without_on_clauses

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

/// A utility class to validate path properties.
mixin PathValidator {
  /// Checks if a given directory path is writable.
  ///
  /// It attempts to create and delete a temporary file in the directory.
  /// Returns `true` if successful, `false` otherwise.
  static bool isWritable(final String path) {
    if (path.isEmpty) return false;

    final tempDir = Directory(path);
    try {
      if (!tempDir.existsSync()) {
        return false;
      }
      File(
          p.join(
            path,
            '.uss_write_test_${DateTime.now().microsecondsSinceEpoch}',
          ),
        )
        ..createSync()
        ..deleteSync();
      return true;
    } catch (e, stackTrace) {
      debugPrint('Failed to validate path: $e');
      debugPrint('Stack trace: $stackTrace');
      // Catches FileSystemException, etc.
      return false;
    }
  }
}
