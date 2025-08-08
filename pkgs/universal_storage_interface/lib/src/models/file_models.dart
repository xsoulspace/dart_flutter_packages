/// File and directory data models used across providers.
library;

/// Represents an entry in a directory listing.
class FileEntry {
  FileEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    final DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory FileEntry.fromJson(final Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String? ?? '',
    isDirectory: json['is_directory'] as bool? ?? false,
    size: json['size'] as int? ?? 0,
    modifiedAt: json['modified_at'] != null
        ? DateTime.tryParse(json['modified_at'] as String) ??
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
        path: json['path'] as String? ?? '',
        revisionId: json['revision_id'] as String? ?? '',
        isNew: json['is_new'] as bool? ?? false,
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
