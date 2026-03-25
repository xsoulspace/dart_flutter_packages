import 'dart:developer' as dev;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart' as p;
import 'package:universal_io/io.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync_utils/universal_storage_sync_utils.dart';

import 'macos_bookmark_manager.dart';

/// Disposes a [FilePathConfig] by stopping access to the macOS bookmark.
Future<void> disposePathOfFileConfig(final FilePathConfig config) async {
  if (Platform.isMacOS) {
    final bookmark = config.macOSBookmarkData;
    if (bookmark.isNotEmpty) {
      try {
        await MacOSBookmarkManager().stopAccessing(Directory(bookmark.value));
      } on Exception catch (e, st) {
        dev.log('Failed to dispose path of file config: $e', stackTrace: st);
      }
    }
  }
}

/// Resolves the default path for the application.
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

/// Resolves a [FilePathConfig] to a [Directory] on the current platform.
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

/// Resolves a [MacOSBookmark] to a [Directory] on macOS.
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
    return null;
  }
  return Directory(path);
}

/// Picks a writable directory and returns [PickResult].
Future<PickResult> pickWritableDirectory({
  final BuildContext? context,
  final String? initialDirectory,
}) async {
  // Kept for API compatibility with app call sites that pass context.
  final _ = context;
  if (Platform.isAndroid || Platform.isIOS) {
    return PickFailure(FailureReason.platformNotSupported);
  }

  final path = await getDirectoryPath(initialDirectory: initialDirectory);

  if (path == null) {
    return PickCancelled();
  }

  final isWritable = PathValidator.isWritable(path);
  if (!isWritable) {
    return PickFailure(FailureReason.pathNotWritable);
  }

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
