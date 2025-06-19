import 'package:meta/meta.dart';

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
@reopen
class FileSystemConfig extends StorageConfig {
  /// {@macro filesystem_config}
  const FileSystemConfig({required this.basePath, this.databaseName});

  /// Base path for file operations (non-web platforms).
  final String basePath;

  /// Database name for web platforms using IndexedDB.
  final String? databaseName;

  /// Creates a new FileSystemConfig builder
  static FileSystemConfigBuilder builder() => FileSystemConfigBuilder();

  @override
  Map<String, dynamic> toMap() => {
    'basePath': basePath,
    if (databaseName != null) 'databaseName': databaseName,
  };
}

/// {@template filesystem_config_builder}
/// Builder for creating FileSystemConfig instances with validation.
/// {@endtemplate}
class FileSystemConfigBuilder {
  /// {@macro filesystem_config_builder}
  FileSystemConfigBuilder();
  String? _basePath;
  String? _databaseName;

  /// Sets the base path for file operations
  FileSystemConfigBuilder basePath(final String path) {
    if (path.isEmpty) {
      throw ArgumentError('Base path cannot be empty');
    }
    _basePath = path;
    return this;
  }

  /// Sets the database name for web platforms
  FileSystemConfigBuilder databaseName(final String name) {
    if (name.isEmpty) {
      throw ArgumentError('Database name cannot be empty');
    }
    _databaseName = name;
    return this;
  }

  /// Builds the FileSystemConfig with validation
  FileSystemConfig build() {
    if (_basePath == null) {
      throw StateError('Base path is required');
    }
    return FileSystemConfig(basePath: _basePath!, databaseName: _databaseName);
  }
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
@reopen
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

  /// Creates a new OfflineGitConfig builder
  static OfflineGitConfigBuilder builder() => OfflineGitConfigBuilder();

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

/// {@template offline_git_config_builder}
/// Builder for creating OfflineGitConfig instances with validation.
/// {@endtemplate}
class OfflineGitConfigBuilder {
  /// {@macro offline_git_config_builder}
  OfflineGitConfigBuilder();

  String? _localPath;
  String? _branchName;
  String? _authorName;
  String? _authorEmail;
  String? _remoteUrl;
  var _remoteName = 'origin';
  String? _remoteType;
  Map<String, dynamic>? _remoteApiSettings;
  var _defaultPullStrategy = 'merge';
  var _defaultPushStrategy = 'rebase-local';
  ConflictResolutionStrategy _conflictResolution =
      ConflictResolutionStrategy.clientAlwaysRight;
  String? _sshKeyPath;
  String? _httpsToken;

  /// Sets the local Git repository path
  OfflineGitConfigBuilder localPath(final String path) {
    if (path.isEmpty) {
      throw ArgumentError('Local path cannot be empty');
    }
    _localPath = path;
    return this;
  }

  /// Sets the branch name
  OfflineGitConfigBuilder branchName(final String branch) {
    if (branch.isEmpty) {
      throw ArgumentError('Branch name cannot be empty');
    }
    _branchName = branch;
    return this;
  }

  /// Sets the Git author name
  OfflineGitConfigBuilder authorName(final String name) {
    if (name.isEmpty) {
      throw ArgumentError('Author name cannot be empty');
    }
    _authorName = name;
    return this;
  }

  /// Sets the Git author email
  OfflineGitConfigBuilder authorEmail(final String email) {
    if (email.isEmpty) {
      throw ArgumentError('Author email cannot be empty');
    }
    _authorEmail = email;
    return this;
  }

  /// Sets the remote repository URL
  OfflineGitConfigBuilder remoteUrl(final String url) {
    if (url.isEmpty) {
      throw ArgumentError('Remote URL cannot be empty');
    }
    _remoteUrl = url;
    return this;
  }

  /// Sets the remote name (defaults to 'origin')
  OfflineGitConfigBuilder remoteName(final String name) {
    if (name.isEmpty) {
      throw ArgumentError('Remote name cannot be empty');
    }
    _remoteName = name;
    return this;
  }

  /// Sets the remote type ('github', 'gitlab', 'custom')
  OfflineGitConfigBuilder remoteType(final String type) {
    if (type.isEmpty) {
      throw ArgumentError('Remote type cannot be empty');
    }
    _remoteType = type;
    return this;
  }

  /// Sets API-specific settings for remote operations
  OfflineGitConfigBuilder remoteApiSettings(
    final Map<String, dynamic> settings,
  ) {
    _remoteApiSettings = Map.from(settings);
    return this;
  }

  /// Sets the default pull strategy
  OfflineGitConfigBuilder defaultPullStrategy(final String strategy) {
    if (strategy.isEmpty) {
      throw ArgumentError('Pull strategy cannot be empty');
    }
    _defaultPullStrategy = strategy;
    return this;
  }

  /// Sets the default push strategy
  OfflineGitConfigBuilder defaultPushStrategy(final String strategy) {
    if (strategy.isEmpty) {
      throw ArgumentError('Push strategy cannot be empty');
    }
    _defaultPushStrategy = strategy;
    return this;
  }

  /// Sets the conflict resolution strategy
  OfflineGitConfigBuilder conflictResolution(
    final ConflictResolutionStrategy strategy,
  ) {
    _conflictResolution = strategy;
    return this;
  }

  /// Configuration builder for authentication methods
  OfflineGitConfigAuthenticationBuilder authentication() =>
      OfflineGitConfigAuthenticationBuilder(this);

  /// Internal method to set SSH key path
  void _setSshKeyPath(final String path) {
    _sshKeyPath = path;
  }

  /// Internal method to set HTTPS token
  void _setHttpsToken(final String token) {
    _httpsToken = token;
  }

  /// Builds the OfflineGitConfig with validation
  OfflineGitConfig build() {
    if (_localPath == null) {
      throw StateError('Local path is required');
    }
    if (_branchName == null) {
      throw StateError('Branch name is required');
    }
    return OfflineGitConfig(
      localPath: _localPath!,
      branchName: _branchName!,
      authorName: _authorName,
      authorEmail: _authorEmail,
      remoteUrl: _remoteUrl,
      remoteName: _remoteName,
      remoteType: _remoteType,
      remoteApiSettings: _remoteApiSettings,
      defaultPullStrategy: _defaultPullStrategy,
      defaultPushStrategy: _defaultPushStrategy,
      conflictResolution: _conflictResolution,
      sshKeyPath: _sshKeyPath,
      httpsToken: _httpsToken,
    );
  }
}

/// {@template offline_git_config_authentication_builder}
/// Authentication builder for OfflineGitConfig.
/// {@endtemplate}
class OfflineGitConfigAuthenticationBuilder {
  /// {@macro offline_git_config_authentication_builder}
  OfflineGitConfigAuthenticationBuilder(this._parentBuilder);

  final OfflineGitConfigBuilder _parentBuilder;

  /// Sets SSH key authentication
  OfflineGitConfigBuilder sshKey(final String keyPath) {
    if (keyPath.isEmpty) {
      throw ArgumentError('SSH key path cannot be empty');
    }
    _parentBuilder._setSshKeyPath(keyPath);
    return _parentBuilder;
  }

  /// Sets HTTPS token authentication
  OfflineGitConfigBuilder httpsToken(final String token) {
    if (token.isEmpty) {
      throw ArgumentError('HTTPS token cannot be empty');
    }
    _parentBuilder._setHttpsToken(token);
    return _parentBuilder;
  }
}

/// {@template github_api_config}
/// Configuration for GitHub API storage provider.
/// {@endtemplate}
@reopen
class GitHubApiConfig extends StorageConfig {
  /// {@macro github_api_config}
  const GitHubApiConfig({
    this.authToken,
    this.repositoryOwner,
    this.repositoryName,
    this.branchName = 'main',
    this.oauthConfig,
    this.repositoryConfig,
  });

  /// GitHub authentication token (for manual token mode).
  final String? authToken;

  /// Repository owner (username or organization).
  final String? repositoryOwner;

  /// Repository name.
  final String? repositoryName;

  /// Branch name to work with.
  final String branchName;

  /// OAuth configuration for automatic authentication.
  final GitHubOAuthConfig? oauthConfig;

  /// Repository configuration for automatic selection/creation.
  final GitHubRepositoryConfig? repositoryConfig;

  /// Whether this config uses OAuth flow
  bool get usesOAuth => oauthConfig != null;

  /// Whether this config has repository auto-selection
  bool get hasRepositorySelection => repositoryConfig != null;

  /// Creates a new GitHubApiConfig builder
  static GitHubApiConfigBuilder builder() => GitHubApiConfigBuilder();

  @override
  Map<String, dynamic> toMap() => {
    if (authToken != null) 'authToken': authToken,
    if (repositoryOwner != null) 'repositoryOwner': repositoryOwner,
    if (repositoryName != null) 'repositoryName': repositoryName,
    'branchName': branchName,
    if (oauthConfig != null) 'oauthConfig': oauthConfig!.toMap(),
    if (repositoryConfig != null) 'repositoryConfig': repositoryConfig!.toMap(),
  };
}

/// {@template github_oauth_config}
/// OAuth configuration for GitHub authentication.
/// {@endtemplate}
class GitHubOAuthConfig {
  /// {@macro github_oauth_config}
  const GitHubOAuthConfig({
    required this.clientId,
    this.clientSecret,
    this.redirectUri,
    this.scopes = const ['repo'],
    this.deviceFlowEnabled = true,
  });

  /// GitHub App client ID
  final String clientId;

  /// GitHub App client secret (optional for public apps)
  final String? clientSecret;

  /// Redirect URI for OAuth flow
  final String? redirectUri;

  /// Requested OAuth scopes
  final List<String> scopes;

  /// Whether to enable device flow for CLI/desktop apps
  final bool deviceFlowEnabled;

  Map<String, dynamic> toMap() => {
    'clientId': clientId,
    if (clientSecret != null) 'clientSecret': clientSecret,
    if (redirectUri != null) 'redirectUri': redirectUri,
    'scopes': scopes,
    'deviceFlowEnabled': deviceFlowEnabled,
  };
}

/// {@template github_repository_config}
/// Configuration for repository selection and creation.
/// {@endtemplate}
class GitHubRepositoryConfig {
  /// {@macro github_repository_config}
  const GitHubRepositoryConfig({
    this.allowSelection = true,
    this.allowCreation = true,
    this.defaultName,
    this.defaultDescription,
    this.defaultPrivate = true,
    this.templateRepository,
    this.suggestedName,
  });

  /// Whether to allow user to select from existing repositories
  final bool allowSelection;

  /// Whether to allow user to create new repositories
  final bool allowCreation;

  /// Default repository name for creation
  final String? defaultName;

  /// Default repository description for creation
  final String? defaultDescription;

  /// Whether created repositories should be private by default
  final bool defaultPrivate;

  /// Template repository to use for creation (owner/repo format)
  final String? templateRepository;

  /// Suggested repository name based on app context
  final String? suggestedName;

  Map<String, dynamic> toMap() => {
    'allowSelection': allowSelection,
    'allowCreation': allowCreation,
    if (defaultName != null) 'defaultName': defaultName,
    if (defaultDescription != null) 'defaultDescription': defaultDescription,
    'defaultPrivate': defaultPrivate,
    if (templateRepository != null) 'templateRepository': templateRepository,
    if (suggestedName != null) 'suggestedName': suggestedName,
  };
}

/// {@template github_api_config_builder}
/// Builder for creating GitHubApiConfig instances with validation.
/// {@endtemplate}
class GitHubApiConfigBuilder {
  /// {@macro github_api_config_builder}
  GitHubApiConfigBuilder();

  String? _authToken;
  String? _repositoryOwner;
  String? _repositoryName;
  var _branchName = 'main';
  GitHubOAuthConfig? _oauthConfig;
  GitHubRepositoryConfig? _repositoryConfig;

  /// Sets the GitHub authentication token (manual mode)
  GitHubApiConfigBuilder authToken(final String token) {
    if (token.isEmpty) {
      throw ArgumentError('Auth token cannot be empty');
    }
    _authToken = token;
    return this;
  }

  /// Sets the repository owner (username or organization)
  GitHubApiConfigBuilder repositoryOwner(final String owner) {
    if (owner.isEmpty) {
      throw ArgumentError('Repository owner cannot be empty');
    }
    _repositoryOwner = owner;
    return this;
  }

  /// Sets the repository name
  GitHubApiConfigBuilder repositoryName(final String name) {
    if (name.isEmpty) {
      throw ArgumentError('Repository name cannot be empty');
    }
    _repositoryName = name;
    return this;
  }

  /// Sets the branch name (defaults to 'main')
  GitHubApiConfigBuilder branchName(final String branch) {
    if (branch.isEmpty) {
      throw ArgumentError('Branch name cannot be empty');
    }
    _branchName = branch;
    return this;
  }

  /// Configures OAuth authentication
  GitHubApiConfigBuilder oauth({
    required final String clientId,
    final String? clientSecret,
    final String? redirectUri,
    final List<String> scopes = const ['repo'],
    final bool deviceFlowEnabled = true,
  }) {
    _oauthConfig = GitHubOAuthConfig(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes,
      deviceFlowEnabled: deviceFlowEnabled,
    );
    return this;
  }

  /// Configures repository selection/creation
  GitHubApiConfigBuilder repository({
    final bool allowSelection = true,
    final bool allowCreation = true,
    final String? defaultName,
    final String? defaultDescription,
    final bool defaultPrivate = true,
    final String? templateRepository,
    final String? suggestedName,
  }) {
    _repositoryConfig = GitHubRepositoryConfig(
      allowSelection: allowSelection,
      allowCreation: allowCreation,
      defaultName: defaultName,
      defaultDescription: defaultDescription,
      defaultPrivate: defaultPrivate,
      templateRepository: templateRepository,
      suggestedName: suggestedName,
    );
    return this;
  }

  /// Convenience method for OAuth-only configuration (no manual repo selection)
  GitHubApiConfigBuilder autoOAuth({
    required final String clientId,
    final String? clientSecret,
    final String? redirectUri,
    final String? suggestedRepoName,
    final String? repoDescription,
    final bool privateRepo = true,
  }) =>
      oauth(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
      ).repository(
        suggestedName: suggestedRepoName,
        defaultDescription: repoDescription,
        defaultPrivate: privateRepo,
      );

  /// Builds the GitHubApiConfig with validation
  GitHubApiConfig build() {
    // OAuth mode validation
    if (_oauthConfig != null) {
      // OAuth mode - repository selection is handled during auth flow
      return GitHubApiConfig(
        branchName: _branchName,
        oauthConfig: _oauthConfig,
        repositoryConfig: _repositoryConfig,
      );
    }

    // Manual mode validation
    if (_authToken == null) {
      throw StateError(
        'Auth token is required for manual mode, or use oauth() for OAuth mode',
      );
    }
    if (_repositoryOwner == null) {
      throw StateError('Repository owner is required for manual mode');
    }
    if (_repositoryName == null) {
      throw StateError('Repository name is required for manual mode');
    }

    return GitHubApiConfig(
      authToken: _authToken,
      repositoryOwner: _repositoryOwner,
      repositoryName: _repositoryName,
      branchName: _branchName,
    );
  }
}
