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
    this.metadata = const <String, dynamic>{},
  });

  factory FileOperationResult.fromJson(final Map<String, dynamic> json) =>
      FileOperationResult(
        path: jsonDecodeString(json['path']),
        revisionId: jsonDecodeString(json['revision_id']),
        isNew: jsonDecodeBool(json['is_new']),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const <String, dynamic>{},
      );

  final String path;
  final String revisionId;
  final bool isNew;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'path': path,
    'revision_id': revisionId,
    'is_new': isNew,
    'metadata': metadata,
  };

  static FileOperationResult created({
    required final String path,
    final String revisionId = '',
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => FileOperationResult(
    path: path,
    revisionId: revisionId,
    isNew: true,
    metadata: metadata,
  );

  static FileOperationResult updated({
    required final String path,
    final String revisionId = '',
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => FileOperationResult(
    path: path,
    revisionId: revisionId,
    metadata: metadata,
  );

  static FileOperationResult deleted({
    required final String path,
    final String revisionId = '',
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) => FileOperationResult(
    path: path,
    revisionId: revisionId,
    metadata: metadata,
  );
}
