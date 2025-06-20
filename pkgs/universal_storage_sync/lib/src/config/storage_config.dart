/// {@template storage_config}
/// Base class for storage provider configurations.
/// {@endtemplate}
sealed class StorageConfig {
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
  FileSystemConfig({required this.basePath, this.databaseName}) {
    if (basePath.isEmpty) {
      throw ArgumentError('Base path cannot be empty');
    }
    if (databaseName != null && databaseName!.isEmpty) {
      throw ArgumentError('Database name cannot be empty');
    }
  }

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

/// {@template offline_git_config}
/// Configuration for offline Git storage provider with remote sync capabilities.
/// {@endtemplate}
class OfflineGitConfig extends StorageConfig {
  /// {@macro offline_git_config}
  OfflineGitConfig({
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
  }) {
    if (localPath.isEmpty) {
      throw ArgumentError('Local path cannot be empty');
    }
    if (branchName.isEmpty) {
      throw ArgumentError('Branch name cannot be empty');
    }
    if (authorName != null && authorName!.isEmpty) {
      throw ArgumentError('Author name cannot be empty');
    }
    if (authorEmail != null && authorEmail!.isEmpty) {
      throw ArgumentError('Author email cannot be empty');
    }
    if (remoteUrl != null && remoteUrl!.isEmpty) {
      throw ArgumentError('Remote URL cannot be empty');
    }
    if (remoteName.isEmpty) {
      throw ArgumentError('Remote name cannot be empty');
    }
    if (remoteType != null && remoteType!.isEmpty) {
      throw ArgumentError('Remote type cannot be empty');
    }
    if (defaultPullStrategy.isEmpty) {
      throw ArgumentError('Pull strategy cannot be empty');
    }
    if (defaultPushStrategy.isEmpty) {
      throw ArgumentError('Push strategy cannot be empty');
    }
    if (sshKeyPath != null && sshKeyPath!.isEmpty) {
      throw ArgumentError('SSH key path cannot be empty');
    }
    if (httpsToken != null && httpsToken!.isEmpty) {
      throw ArgumentError('HTTPS token cannot be empty');
    }
  }

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
///
/// This provider requires a pre-acquired access token and explicit
/// repository information. It does not handle authentication flows
/// or repository selection - these concerns are handled by external
/// components.
/// {@endtemplate}
class GitHubApiConfig extends StorageConfig {
  /// {@macro github_api_config}
  GitHubApiConfig({
    required this.authToken,
    required this.repositoryOwner,
    required this.repositoryName,
    this.branchName = 'main',
  }) {
    if (authToken.isEmpty) {
      throw ArgumentError('Auth token cannot be empty');
    }
    if (repositoryOwner.isEmpty) {
      throw ArgumentError('Repository owner cannot be empty');
    }
    if (repositoryName.isEmpty) {
      throw ArgumentError('Repository name cannot be empty');
    }
    if (branchName.isEmpty) {
      throw ArgumentError('Branch name cannot be empty');
    }
  }

  /// GitHub authentication token (required).
  /// Must be a valid Personal Access Token or OAuth token with appropriate
  /// permissions.
  final String authToken;

  /// Repository owner (username or organization) (required).
  final String repositoryOwner;

  /// Repository name (required).
  final String repositoryName;

  /// Branch name to work with (defaults to 'main').
  final String branchName;

  @override
  Map<String, dynamic> toMap() => {
    'authToken': authToken,
    'repositoryOwner': repositoryOwner,
    'repositoryName': repositoryName,
    'branchName': branchName,
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
