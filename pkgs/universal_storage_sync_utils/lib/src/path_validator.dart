import 'dart:io';

import 'package:path/path.dart' as p;

/// A utility class to validate path properties.
mixin PathValidator {
  /// Checks if a given directory path is writable.
  ///
  /// It attempts to create and delete a temporary file in the directory.
  /// Returns `true` if successful, `false` otherwise.
  static Future<bool> isWritable(final String path) async {
    final tempDir = Directory(path);
    try {
      if (!tempDir.existsSync()) {
        return false;
      }
      final tempFile = File(
        p.join(path, '.usspw'),
      ); // Universal Storage Sync Path Writable
      await tempFile.create();
      await tempFile.delete();
      return true;
    } catch (_) {
      // Catches FileSystemException, etc.
      return false;
    }
  }
}
