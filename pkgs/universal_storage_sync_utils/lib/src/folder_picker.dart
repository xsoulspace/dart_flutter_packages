import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import 'macos_bookmark_manager.dart';
import 'path_validator.dart';
import 'result.dart';

/// Resolves a [MacOSBookmark] to a [FileSystemEntity].
///
/// This function is used to resolve a [MacOSBookmark] to a [FileSystemEntity]
/// on macOS.
///
/// It's important to call [MacOSBookmarkManager.stopAccessing] when you're done
/// accessing the entity.
Future<FileSystemEntity?> resolvePlatformDirectory({
  required final String path,
  final MacOSBookmark? bookmark,
}) async {
  if (Platform.isMacOS) {
    if (bookmark != null) {
      return MacOSBookmarkManager().resolveBookmark(bookmark);
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
    final status = await Permission.storage.request();
    if (status.isDenied) {
      return PickFailure(FailureReason.permissionDenied);
    }
  }

  // 3. Show the folder picker.
  final path = await getDirectoryPath(initialDirectory: initialDirectory);

  if (path == null) {
    // User cancelled the picker.
    return PickCancelled();
  }

  // 4. Validate writability.
  final isWritable = await PathValidator.isWritable(path);
  if (!isWritable) {
    return PickFailure(FailureReason.pathNotWritable);
  }

  // 5. Create a security-scoped bookmark on macOS
  MacOSBookmark? bookmark;
  if (Platform.isMacOS) {
    final bookmarkManager = MacOSBookmarkManager();
    bookmark = await bookmarkManager.createBookmark(path);
  }

  return PickSuccess(path, macOSBookmark: bookmark);
}
