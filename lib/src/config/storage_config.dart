/// {@template storage_config}
/// Base class for storage provider configurations.
/// {@endtemplate}
abstract class StorageConfig {
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

/// {@template offline_git_config}
/// Configuration for offline Git storage provider.
/// {@endtemplate}
class OfflineGitConfig extends StorageConfig {
  /// {@macro offline_git_config}
  const OfflineGitConfig({
    required this.localPath,
    required this.branchName,
    this.authorName,
    this.authorEmail,
    this.remoteName = 'origin',
    this.remoteUrl,
    this.remoteType,
    this.remoteApiSettings,
  });

  /// Path to the local Git repository.
  final String localPath;

  /// Primary local and remote branch name.
  final String branchName;

  /// Author name for Git commits.
  final String? authorName;

  /// Author email for Git commits.
  final String? authorEmail;

  /// Name of the remote (defaults to 'origin').
  final String remoteName;

  /// URL of the remote Git repository.
  final String? remoteUrl;

  /// Type of remote ('github', 'custom_git', etc.).
  final String? remoteType;

  /// API-specific settings for remote operations.
  final Map<String, dynamic>? remoteApiSettings;

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
