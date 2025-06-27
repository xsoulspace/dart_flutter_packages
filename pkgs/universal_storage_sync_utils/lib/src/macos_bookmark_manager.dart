// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';

/// A utility class for managing security-scoped bookmarks on macOS.
///
/// This class provides methods to create a bookmark for a given folder path
/// and resolve a stored bookmark to regain persistent access to the folder.
///
/// Currently a wrapper for [SecureBookmarks] from [macos_secure_bookmarks]
/// package.
class MacOSBookmarkManager {
  final _secureBookmarks = SecureBookmarks();

  /// Creates a security-scoped bookmark for the given [path].
  ///
  /// Returns the bookmark as a Base64 encoded string, which can be stored
  /// securely. Returns `null` if the path is invalid or bookmarking fails.
  Future<MacOSBookmark?> createBookmark(final String path) async {
    final entity = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : File(path);
    if (!entity.existsSync()) {
      return null;
    }

    try {
      final bookmarkData = await _secureBookmarks.bookmark(entity);
      return MacOSBookmark.fromBase64(bookmarkData);
    } catch (e, stackTrace) {
      // Log the error or handle it as needed
      debugPrint('Failed to create bookmark: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Resolves a security-scoped bookmark to get the folder path.
  ///
  /// The [bookmark] should be a Base64 encoded string obtained from
  /// [createBookmark]. This method also starts access to the resource.
  ///
  /// Remember to call `stopAccessingSecurityScopedResource` when you're done.
  Future<FileSystemEntity?> resolveBookmark(
    final MacOSBookmark bookmark,
  ) async {
    try {
      final resolvedEntity = await _secureBookmarks.resolveBookmark(
        bookmark.value,
      );
      await _secureBookmarks.startAccessingSecurityScopedResource(
        resolvedEntity,
      );
      final stats = resolvedEntity.statSync();
      return switch (stats.type) {
        FileSystemEntityType.directory => Directory.fromUri(resolvedEntity.uri),
        FileSystemEntityType.file => File.fromUri(resolvedEntity.uri),
        FileSystemEntityType.link => Link.fromUri(resolvedEntity.uri),
        _ => resolvedEntity,
      };
    } catch (e, stackTrace) {
      // Log the error or handle it as needed
      debugPrint('Failed to resolve bookmark: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Stops accessing a resource that was previously accessed via
  /// [resolveBookmark].
  ///
  /// It's important to release access to the resource when you no longer need
  /// it.
  Future<void> stopAccessing(final FileSystemEntity entity) async {
    try {
      await _secureBookmarks.stopAccessingSecurityScopedResource(entity);
    } catch (e, stackTrace) {
      // Log the error or handle it as needed
      debugPrint('Failed to stop accessing resource: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
}
