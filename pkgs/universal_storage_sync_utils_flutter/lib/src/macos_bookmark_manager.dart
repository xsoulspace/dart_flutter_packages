// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:developer' as dev;

import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:universal_io/io.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// A utility class for managing security-scoped bookmarks on macOS.
class MacOSBookmarkManager {
  final _secureBookmarks = SecureBookmarks();

  /// Creates a security-scoped bookmark for the given [path].
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
      dev.log('Failed to create bookmark: $e', stackTrace: stackTrace);
      return null;
    }
  }

  /// Resolves a security-scoped bookmark and starts access to the resource.
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
      dev.log('Failed to resolve bookmark: $e', stackTrace: stackTrace);
      return null;
    }
  }

  /// Stops accessing a resource that was previously accessed via
  /// [resolveBookmark].
  Future<void> stopAccessing(final FileSystemEntity entity) async {
    try {
      await _secureBookmarks.stopAccessingSecurityScopedResource(entity);
    } catch (e, stackTrace) {
      dev.log('Failed to stop accessing resource: $e', stackTrace: stackTrace);
    }
  }
}
