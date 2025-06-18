/// {@template storage_config}
/// Base class for storage provider configurations.
/// {@endtemplate}
abstract interface class StorageConfig {
  /// {@macro storage_config}
  const StorageConfig();

  /// Converts the configuration to a map for provider initialization.
  Map<String, dynamic> toMap();
}

/// {@template filesystem_config}
/// Configuration for filesystem storage provider.
/// {@endtemplate}
class FileSystemConfig extends StorageConfig {
  /// {@macro filesystem_config}
  const FileSystemConfig({required this.basePath, this.databaseName});

  /// Base path for file operations (non-web platforms).
  final String basePath;

  /// Database name for web platforms using IndexedDB.
  final String? databaseName;

  @override
  Map<String, dynamic> toMap() => {
        'basePath': basePath,
        if (databaseName != null) 'databaseName': databaseName,
      };
}

/// Conflict resolution strategies for remote synchronization.
enum ConflictResolutionStrategy {
  /// Local changes always take precedence over remote changes.
  clientAlwaysRight,

  /// Remote changes always take precedence over local changes.
  serverAlwaysRight,

  /// Throw exception for manual conflict resolution.
  manualResolution,

  /// Use timestamp-based resolution (last write wins).
  lastWriteWins,
}

/// {@template offline_git_config}
/// Configuration for offline Git storage provider with remote sync capabilities.
/// {@endtemplate}
class OfflineGitConfig extends StorageConfig {
  /// {@macro offline_git_config}
  const OfflineGitConfig({
    required this.localPath,
    required this.branchName,
    this.authorName,
    this.authorEmail,
    // Remote configuration
    this.remoteUrl,
    this.remoteName = 'origin',
    this.remoteType,
    this.remoteApiSettings,
    // Sync strategies
    this.defaultPullStrategy = 'merge',
    this.defaultPushStrategy = 'rebase-local',
    this.conflictResolution = ConflictResolutionStrategy.clientAlwaysRight,
    // Authentication
    this.sshKeyPath,
    this.httpsToken,
  });

  /// Path to the local Git repository.
  final String localPath;

  /// Primary local and remote branch name.
  final String branchName;

  /// Author name for Git commits.
  final String? authorName;

  /// Author email for Git commits.
  final String? authorEmail;

  // Remote configuration
  /// URL of the remote Git repository.
  final String? remoteUrl;

  /// Name of the remote (defaults to 'origin').
  final String remoteName;

  /// Type of remote ('github', 'gitlab', 'custom').
  final String? remoteType;

  /// API-specific settings for remote operations.
  final Map<String, dynamic>? remoteApiSettings;

  // Sync strategies
  /// Default pull strategy: 'merge', 'rebase', 'ff-only'.
  final String defaultPullStrategy;

  /// Default push strategy: 'rebase-local', 'force-with-lease', 'fail-on-conflict'.
  final String defaultPushStrategy;

  /// Conflict resolution strategy for merge conflicts.
  final ConflictResolutionStrategy conflictResolution;

  // Authentication
  /// Path to SSH private key for Git authentication.
  final String? sshKeyPath;

  /// HTTPS token for Git authentication.
  final String? httpsToken;

  @override
  Map<String, dynamic> toMap() => {
        'localPath': localPath,
        'branchName': branchName,
        if (authorName != null) 'authorName': authorName,
        if (authorEmail != null) 'authorEmail': authorEmail,
        'remoteName': remoteName,
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        if (remoteType != null) 'remoteType': remoteType,
        if (remoteApiSettings != null) 'remoteApiSettings': remoteApiSettings,
        'defaultPullStrategy': defaultPullStrategy,
        'defaultPushStrategy': defaultPushStrategy,
        'conflictResolution': conflictResolution.name,
        if (sshKeyPath != null) 'sshKeyPath': sshKeyPath,
        if (httpsToken != null) 'httpsToken': httpsToken,
      };
}

/// {@template github_api_config}
/// Configuration for GitHub API storage provider.
/// {@endtemplate}
class GitHubApiConfig extends StorageConfig {
  /// {@macro github_api_config}
  const GitHubApiConfig({
    required this.authToken,
    required this.repositoryOwner,
    required this.repositoryName,
    this.branchName = 'main',
  });

  /// GitHub authentication token.
  final String authToken;

  /// Repository owner (username or organization).
  final String repositoryOwner;

  /// Repository name.
  final String repositoryName;

  /// Branch name to work with.
  final String branchName;

  @override
  Map<String, dynamic> toMap() => {
        'authToken': authToken,
        'repositoryOwner': repositoryOwner,
        'repositoryName': repositoryName,
        'branchName': branchName,
      };
}
