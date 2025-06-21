import '../storage_exceptions.dart';

/// {@template version_control_capable}
/// Mixin for storage providers that support version control operations.
/// Provides standardized version control functionality like commits, history,
/// and branching.
/// {@endtemplate}
mixin VersionControlCapable {
  /// Indicates if the provider supports version control
  bool get supportsVersionControl => true;

  /// Creates a commit with the specified message
  Future<String> commit(final String message, {final List<String>? files}) {
    throw const UnsupportedOperationException(
      'Commit operation must be implemented by the provider',
    );
  }

  /// Gets the commit history for a file or the entire repository
  Future<List<CommitInfo>> getHistory({
    final String? filePath,
    final int? limit,
    final String? since,
  }) {
    throw const UnsupportedOperationException(
      'getHistory must be implemented by the provider',
    );
  }

  /// Gets information about a specific commit
  Future<CommitInfo?> getCommit(final String commitId) {
    throw const UnsupportedOperationException(
      'getCommit must be implemented by the provider',
    );
  }

  /// Gets the content of a file at a specific commit
  Future<String?> getFileAtCommit(
    final String filePath,
    final String commitId,
  ) {
    throw const UnsupportedOperationException(
      'getFileAtCommit must be implemented by the provider',
    );
  }

  /// Gets the differences between two commits
  Future<List<FileDiff>> getDiff({
    final String? fromCommit,
    final String? toCommit,
    final String? filePath,
  }) {
    throw const UnsupportedOperationException(
      'getDiff must be implemented by the provider',
    );
  }

  /// Reverts changes to a specific commit
  Future<void> revert(final String commitId, {final String? message}) {
    throw const UnsupportedOperationException(
      'revert must be implemented by the provider',
    );
  }

  /// Creates a new branch
  Future<void> createBranch(
    final String branchName, {
    final String? fromCommit,
  }) {
    throw const UnsupportedOperationException(
      'createBranch must be implemented by the provider',
    );
  }

  /// Switches to a different branch
  Future<void> switchBranch(final String branchName) {
    throw const UnsupportedOperationException(
      'switchBranch must be implemented by the provider',
    );
  }

  /// Lists all available branches
  Future<List<String>> listBranches() {
    throw const UnsupportedOperationException(
      'listBranches must be implemented by the provider',
    );
  }

  /// Gets the current branch name
  Future<String> getCurrentBranch() {
    throw const UnsupportedOperationException(
      'getCurrentBranch must be implemented by the provider',
    );
  }

  /// Merges another branch into the current branch
  Future<void> mergeBranch(final String branchName, {final String? message}) {
    throw const UnsupportedOperationException(
      'mergeBranch must be implemented by the provider',
    );
  }

  /// Deletes a branch
  Future<void> deleteBranch(
    final String branchName, {
    final bool force = false,
  }) {
    throw const UnsupportedOperationException(
      'deleteBranch must be implemented by the provider',
    );
  }

  /// Gets the status of working directory changes
  Future<WorkingDirectoryStatus> getStatus() {
    throw const UnsupportedOperationException(
      'getStatus must be implemented by the provider',
    );
  }

  /// Stages files for commit
  Future<void> stageFiles(final List<String> filePaths) {
    throw const UnsupportedOperationException(
      'stageFiles must be implemented by the provider',
    );
  }

  /// Unstages files from commit
  Future<void> unstageFiles(final List<String> filePaths) {
    throw const UnsupportedOperationException(
      'unstageFiles must be implemented by the provider',
    );
  }

  /// Tags a specific commit
  Future<void> createTag(
    final String tagName,
    final String commitId, {
    final String? message,
  }) {
    throw const UnsupportedOperationException(
      'createTag must be implemented by the provider',
    );
  }

  /// Lists all tags
  Future<List<String>> listTags() {
    throw const UnsupportedOperationException(
      'listTags must be implemented by the provider',
    );
  }
}

/// {@template commit_info}
/// Information about a version control commit.
/// {@endtemplate}
class CommitInfo {
  /// {@macro commit_info}
  const CommitInfo({
    required this.id,
    required this.message,
    required this.author,
    required this.timestamp,
    this.parentIds = const [],
    this.changedFiles = const [],
  });

  /// Unique identifier for the commit
  final String id;

  /// Commit message
  final String message;

  /// Author information
  final AuthorInfo author;

  /// Timestamp when the commit was created
  final DateTime timestamp;

  /// Parent commit IDs
  final List<String> parentIds;

  /// Files changed in this commit
  final List<String> changedFiles;

  @override
  String toString() =>
      'CommitInfo(id: $id, message: $message, '
      'author: $author, timestamp: $timestamp)';
}

/// {@template author_info}
/// Information about a commit author.
/// {@endtemplate}
class AuthorInfo {
  /// {@macro author_info}
  const AuthorInfo({required this.name, required this.email});

  /// Author's name
  final String name;

  /// Author's email
  final String email;

  @override
  String toString() => '$name <$email>';
}

/// {@template file_diff}
/// Represents changes to a file between two commits.
/// {@endtemplate}
class FileDiff {
  /// {@macro file_diff}
  const FileDiff({
    required this.filePath,
    required this.changeType,
    this.oldContent,
    this.newContent,
    this.additions = 0,
    this.deletions = 0,
  });

  /// Path of the changed file
  final String filePath;

  /// Type of change
  final FileChangeType changeType;

  /// Old file content (for modifications)
  final String? oldContent;

  /// New file content (for modifications)
  final String? newContent;

  /// Number of lines added
  final int additions;

  /// Number of lines deleted
  final int deletions;

  @override
  String toString() =>
      'FileDiff(filePath: $filePath, changeType: '
      '$changeType, +$additions -$deletions)';
}

/// {@template file_change_type}
/// Types of changes that can occur to a file.
/// {@endtemplate}
enum FileChangeType {
  /// File was added
  added,

  /// File was modified
  modified,

  /// File was deleted
  deleted,

  /// File was renamed
  renamed,

  /// File was copied
  copied,
}

/// {@template working_directory_status}
/// Status of the working directory in version control.
/// {@endtemplate}
class WorkingDirectoryStatus {
  /// {@macro working_directory_status}
  const WorkingDirectoryStatus({
    this.modifiedFiles = const [],
    this.addedFiles = const [],
    this.deletedFiles = const [],
    this.untrackedFiles = const [],
    this.stagedFiles = const [],
  });

  /// Files that have been modified
  final List<String> modifiedFiles;

  /// Files that have been added
  final List<String> addedFiles;

  /// Files that have been deleted
  final List<String> deletedFiles;

  /// Files that are not tracked by version control
  final List<String> untrackedFiles;

  /// Files that are staged for commit
  final List<String> stagedFiles;

  /// Whether the working directory is clean (no changes)
  bool get isClean =>
      modifiedFiles.isEmpty &&
      addedFiles.isEmpty &&
      deletedFiles.isEmpty &&
      stagedFiles.isEmpty;

  /// Whether there are staged changes ready for commit
  bool get hasStagedChanges => stagedFiles.isNotEmpty;

  /// Whether there are unstaged changes
  bool get hasUnstagedChanges =>
      modifiedFiles.isNotEmpty ||
      addedFiles.isNotEmpty ||
      deletedFiles.isNotEmpty;

  @override
  String toString() =>
      'WorkingDirectoryStatus(modified: ${modifiedFiles.length}, '
      'added: ${addedFiles.length}, deleted: ${deletedFiles.length},'
      ' untracked: ${untrackedFiles.length}, staged: ${stagedFiles.length})';
}
