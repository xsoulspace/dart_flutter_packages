import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart' as p;
import 'package:universal_io/io.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'macos_bookmark_manager.dart';
import 'models/pick_result.dart';
import 'path_validator.dart';

/// Disposes a [FilePathConfig] by stopping access to the macOS bookmark.
Future<void> disposePathOfFileConfig(final FilePathConfig config) async {
  if (Platform.isMacOS) {
    final bookmark = config.macOSBookmarkData;
    if (bookmark.isNotEmpty) {
      try {
        await MacOSBookmarkManager().stopAccessing(Directory(bookmark.value));
      } catch (e, st) {
        debugPrint('Failed to dispose path of file config: $e $st');
      }
    }
  }
}

/// Resolves the default path for the application.
///
/// This function will:
/// 1. Get the application documents directory.
/// 2. Create a security-scoped bookmark for persistent access on macOS.
/// 3. Return a [FilePathConfig] with the path and bookmark.
///
/// It returns a [FilePathConfig] which can be used to initialize a
/// [FileSystemConfig].
Future<FilePathConfig> resolveDefaultPath() async {
  final path = await p.getApplicationDocumentsDirectory();
  MacOSBookmark? bookmark;
  if (Platform.isMacOS) {
    bookmark = await MacOSBookmarkManager().createBookmark(path.path);
  }
  return FilePathConfig.create(
    path: path.path,
    macOSBookmarkData: bookmark ?? MacOSBookmark.empty,
  );
}

/// Resolves a [FilePathConfig] to a [Directory].
///
/// This function is used to resolve a [FilePathConfig] to a [Directory] on the
/// current platform.
///
/// It's important to call [MacOSBookmarkManager.stopAccessing] when you're done
/// accessing the entity.
Future<Directory?> resolvePlatformDirectoryOfConfig(
  final FilePathConfig config,
) async {
  final path = config.path.path;
  if (path.isEmpty) return null;
  final directory = await resolvePlatformDirectory(
    path: path,
    bookmark: config.macOSBookmarkData,
  );
  if (directory != null && directory.existsSync()) {
    return directory;
  }
  return null;
}

/// Resolves a [MacOSBookmark] to a [FileSystemEntity].
///
/// This function is used to resolve a [MacOSBookmark] to a [FileSystemEntity]
/// on macOS.
///
/// It's important to call [MacOSBookmarkManager.stopAccessing] when you're done
/// accessing the entity.
Future<Directory?> resolvePlatformDirectory({
  required final String path,
  final MacOSBookmark? bookmark,
}) async {
  if (path.isEmpty) return null;
  if (Platform.isMacOS) {
    if (bookmark != null) {
      final resolved = await MacOSBookmarkManager().resolveBookmark(bookmark);
      if (resolved is Directory) {
        return resolved;
      }
      return null;
    }
    // if no bookmark, return null since we don't have a way to resolve it
    return null;
  }
  return Directory(path);
}

/// A convenience function that handles the entire process of picking a writable
/// directory.
///
/// This function will:
/// 1. Check if folder picking is supported on the current platform.
/// 2. Request necessary permissions on mobile if applicable
/// (though currently unsupported).
/// 3. Show the folder picker to the user.
/// 4. Validate that the selected path is a writable directory.
/// 5. On macOS, create a security-scoped bookmark for persistent access.
///
/// It returns a [PickResult] which can be one of [PickSuccess],
/// [PickFailure], or [PickCancelled].
Future<PickResult> pickWritableDirectory({
  final BuildContext? context,
  final String? initialDirectory,
}) async {
  // 1. Request permissions if needed.
  // On desktop, this is generally not required for the picker itself, but
  // good practice if the app needs broader file access.
  if (Platform.isAndroid || Platform.isIOS) {
    // Currently not supported on mobile platforms
    return PickFailure(FailureReason.platformNotSupported);
  }

  // 3. Show the folder picker.
  final path = await getDirectoryPath(initialDirectory: initialDirectory);

  if (path == null) {
    // User cancelled the picker.
    return PickCancelled();
  }

  // 4. Validate writability.
  final isWritable = PathValidator.isWritable(path);
  if (!isWritable) {
    return PickFailure(FailureReason.pathNotWritable);
  }

  // 5. Create a security-scoped bookmark on macOS
  MacOSBookmark? bookmark;
  if (Platform.isMacOS) {
    final bookmarkManager = MacOSBookmarkManager();
    bookmark = await bookmarkManager.createBookmark(path);
  }

  return PickSuccess(
    FilePathConfig.create(
      path: path,
      macOSBookmarkData: bookmark ?? MacOSBookmark.empty,
    ),
  );
}
