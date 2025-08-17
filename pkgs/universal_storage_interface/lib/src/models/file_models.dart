/// File and directory data models used across providers.
library;

import 'package:from_json_to_json/from_json_to_json.dart';

/// Represents an entry in a directory listing.
class FileEntry {
  FileEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    final DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory FileEntry.fromJson(final Map<String, dynamic> json) => FileEntry(
    name: jsonDecodeString(json['name']),
    isDirectory: jsonDecodeBool(json['is_directory']),
    size: jsonDecodeInt(json['size']),
    modifiedAt: json['modified_at'] != null
        ? DateTime.tryParse(jsonDecodeString(json['modified_at'])) ??
              DateTime.fromMillisecondsSinceEpoch(0)
        : null,
  );

  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'is_directory': isDirectory,
    'size': size,
    'modified_at': modifiedAt.toIso8601String(),
  };
}

/// Unified result for file operations (create/update/delete).
class FileOperationResult {
  const FileOperationResult({
    required this.path,
    this.revisionId = '',
    this.isNew = false,
  });

  factory FileOperationResult.fromJson(final Map<String, dynamic> json) =>
      FileOperationResult(
        path: jsonDecodeString(json['path']),
        revisionId: jsonDecodeString(json['revision_id']),
        isNew: jsonDecodeBool(json['is_new']),
      );

  final String path;
  final String revisionId;
  final bool isNew;

  Map<String, dynamic> toJson() => {
    'path': path,
    'revision_id': revisionId,
    'is_new': isNew,
  };

  static FileOperationResult created({
    required final String path,
    final String revisionId = '',
  }) => FileOperationResult(path: path, revisionId: revisionId, isNew: true);

  static FileOperationResult updated({
    required final String path,
    final String revisionId = '',
  }) => FileOperationResult(path: path, revisionId: revisionId);

  static FileOperationResult deleted({
    required final String path,
    final String revisionId = '',
  }) => FileOperationResult(path: path, revisionId: revisionId);
}
