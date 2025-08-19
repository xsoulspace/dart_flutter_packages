// ignore_for_file: avoid_annotating_with_dynamic

import 'package:from_json_to_json/from_json_to_json.dart';

import 'macos_bookmark.dart';

/// {@template file_path}
/// Extension type that wraps a file system path string.
///
/// Provides type safety and JSON serialization for file paths.
/// {@endtemplate}
extension type const FilePath(String path) {
  /// Creates a [FilePath] from JSON data.
  ///
  /// Expects the JSON data to be a string representing the file path.
  factory FilePath.fromJson(final dynamic jsonData) {
    final str = jsonDecodeString(jsonData);
    return FilePath(str);
  }
}

/// {@template file_path_config}
/// Extension type that represents the workspace path configuration.
///
/// Stores both the file system path and macOS security-scoped bookmark data
/// for persistent access to directories across app launches on macOS.
///
/// This configuration is essential for maintaining access to user-selected
/// directories, especially on macOS where security-scoped bookmarks are
/// required for persistent file system access.
/// {@endtemplate}
extension type const FilePathConfig(Map<String, dynamic> value) {
  /// Creates a [FilePathConfig] from JSON data.
  ///
  /// Expects the JSON data to be a map containing 'path' and
  /// 'macOSBookmarkData' keys.
  factory FilePathConfig.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return FilePathConfig(map);
  }

  /// Creates a new [FilePathConfig] with the specified path and bookmark data.
  ///
  /// [path] is the file system path to the directory.
  /// [macOSBookmarkData] is the security-scoped bookmark for macOS persistence.
  factory FilePathConfig.create({
    required final String path,
    required final MacOSBookmark macOSBookmarkData,
  }) => FilePathConfig({'path': path, 'macOSBookmarkData': macOSBookmarkData});

  /// Gets the file system path from the configuration.
  FilePath get path => FilePath.fromJson(value['path']);

  /// Gets the macOS security-scoped bookmark data from the configuration.
  ///
  /// This bookmark is used on macOS to maintain persistent access to
  /// user-selected directories across app launches.
  MacOSBookmark get macOSBookmarkData =>
      MacOSBookmark.fromBase64(jsonDecodeString(value['macOSBookmarkData']));

  /// Converts the configuration to a JSON-serializable map.
  Map<String, dynamic> toJson() => value;

  /// An empty configuration with no path or bookmark data.
  static const empty = FilePathConfig({});
}
