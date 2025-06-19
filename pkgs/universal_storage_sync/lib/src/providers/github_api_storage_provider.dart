import 'dart:convert';

import 'package:github/github.dart';
import 'package:retry/retry.dart';

import '../config/storage_config.dart';
import '../exceptions/storage_exceptions.dart';
import '../storage_provider.dart';

/// {@template github_api_storage_provider}
/// A storage provider that uses GitHub API directly for all operations.
///
/// This provider does not maintain local Git repositories and operates
/// entirely through GitHub's REST API. It's suited for scenarios where:
/// - No local offline capability is needed
/// - Git CLI is unavailable
/// - You want direct API-based file operations
/// - OAuth authentication is preferred over manual tokens
/// {@endtemplate}
class GitHubApiStorageProvider extends StorageProvider {
  /// {@macro github_api_storage_provider}
  GitHubApiStorageProvider();

  GitHub? _github;
  String? _authToken;
  String? _repositoryOwner;
  String? _repositoryName;
  var _branchName = 'main';
  var _isInitialized = false;

  // OAuth support
  GitHubOAuthConfig? _oauthConfig;
  GitHubRepositoryConfig? _repositoryConfig;

  @override
  Future<void> init(final Map<String, dynamic> config) async {
    // Try to parse as GitHubApiConfig first
    if (config.containsKey('oauthConfig')) {
      await _initializeWithOAuth(config);
    } else {
      await _initializeWithToken(config);
    }
  }

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is GitHubApiConfig) {
      if (config.usesOAuth) {
        await _initializeWithOAuthConfig(config);
      } else {
        await _initializeWithTokenConfig(config);
      }
    } else {
      throw ArgumentError(
        'Expected GitHubApiConfig, got ${config.runtimeType}',
      );
    }
  }

  /// Initialize with OAuth configuration
  Future<void> _initializeWithOAuthConfig(final GitHubApiConfig config) async {
    _oauthConfig = config.oauthConfig;
    _repositoryConfig = config.repositoryConfig;
    _branchName = config.branchName;

    // Start OAuth flow
    final authResult = await _performOAuthFlow();
    _authToken = authResult.accessToken;

    // Handle repository selection/creation
    if (_repositoryConfig != null) {
      final repoResult = await _handleRepositorySelection();
      _repositoryOwner = repoResult.owner;
      _repositoryName = repoResult.name;
    } else if (config.repositoryOwner != null &&
        config.repositoryName != null) {
      _repositoryOwner = config.repositoryOwner;
      _repositoryName = config.repositoryName;
    } else {
      throw const ConfigurationException(
        'Repository must be specified or repository selection must be enabled',
      );
    }

    // Initialize GitHub client
    _github = GitHub(auth: Authentication.withToken(_authToken));
    await _initializeRepository();
    _isInitialized = true;
  }

  /// Initialize with token configuration (legacy)
  Future<void> _initializeWithTokenConfig(final GitHubApiConfig config) async {
    _authToken = config.authToken;
    _repositoryOwner = config.repositoryOwner;
    _repositoryName = config.repositoryName;
    _branchName = config.branchName;

    if (_authToken == null ||
        _repositoryOwner == null ||
        _repositoryName == null) {
      throw const ConfigurationException(
        'authToken, repositoryOwner, and repositoryName are required for manual mode',
      );
    }

    // Initialize GitHub client
    _github = GitHub(auth: Authentication.withToken(_authToken));
    await _initializeRepository();
    _isInitialized = true;
  }

  /// Initialize with OAuth from map (legacy)
  Future<void> _initializeWithOAuth(final Map<String, dynamic> config) async {
    final oauthConfigMap = config['oauthConfig'] as Map<String, dynamic>;
    _oauthConfig = GitHubOAuthConfig(
      clientId: oauthConfigMap['clientId'] as String,
      clientSecret: oauthConfigMap['clientSecret'] as String?,
      redirectUri: oauthConfigMap['redirectUri'] as String?,
      scopes:
          (oauthConfigMap['scopes'] as List<dynamic>?)?.cast<String>() ??
          ['repo'],
      deviceFlowEnabled: oauthConfigMap['deviceFlowEnabled'] as bool? ?? true,
    );

    if (config.containsKey('repositoryConfig')) {
      final repoConfigMap = config['repositoryConfig'] as Map<String, dynamic>;
      _repositoryConfig = GitHubRepositoryConfig(
        allowSelection: repoConfigMap['allowSelection'] as bool? ?? true,
        allowCreation: repoConfigMap['allowCreation'] as bool? ?? true,
        defaultName: repoConfigMap['defaultName'] as String?,
        defaultDescription: repoConfigMap['defaultDescription'] as String?,
        defaultPrivate: repoConfigMap['defaultPrivate'] as bool? ?? true,
        templateRepository: repoConfigMap['templateRepository'] as String?,
        suggestedName: repoConfigMap['suggestedName'] as String?,
      );
    }

    _branchName = config['branchName'] as String? ?? 'main';

    // Start OAuth flow
    final authResult = await _performOAuthFlow();
    _authToken = authResult.accessToken;

    // Handle repository selection/creation
    if (_repositoryConfig != null) {
      final repoResult = await _handleRepositorySelection();
      _repositoryOwner = repoResult.owner;
      _repositoryName = repoResult.name;
    } else {
      _repositoryOwner = config['repositoryOwner'] as String?;
      _repositoryName = config['repositoryName'] as String?;

      if (_repositoryOwner == null || _repositoryName == null) {
        throw const ConfigurationException(
          'Repository must be specified or repository selection must be enabled',
        );
      }
    }

    // Initialize GitHub client
    _github = GitHub(auth: Authentication.withToken(_authToken));
    await _initializeRepository();
    _isInitialized = true;
  }

  /// Initialize with token from map (legacy)
  Future<void> _initializeWithToken(final Map<String, dynamic> config) async {
    _authToken = config['authToken'] as String?;
    _repositoryOwner = config['repositoryOwner'] as String?;
    _repositoryName = config['repositoryName'] as String?;
    _branchName = config['branchName'] as String? ?? 'main';

    if (_authToken == null ||
        _repositoryOwner == null ||
        _repositoryName == null) {
      throw const ConfigurationException(
        'authToken, repositoryOwner, and repositoryName are required',
      );
    }

    // Initialize GitHub client
    _github = GitHub(auth: Authentication.withToken(_authToken));
    await _initializeRepository();
    _isInitialized = true;
  }

  /// Performs OAuth flow and returns access token
  Future<GitHubOAuthResult> _performOAuthFlow() async {
    if (_oauthConfig == null) {
      throw const ConfigurationException('OAuth configuration is required');
    }

    // For web applications with redirect URI
    if (_oauthConfig!.redirectUri != null) {
      return _performWebOAuthFlow();
    }

    // For desktop/CLI applications using device flow
    if (_oauthConfig!.deviceFlowEnabled) {
      return _performDeviceOAuthFlow();
    }

    throw const ConfigurationException(
      'Either redirectUri or deviceFlowEnabled must be configured for OAuth',
    );
  }

  /// Performs web-based OAuth flow
  Future<GitHubOAuthResult> _performWebOAuthFlow() async {
    // Implementation would integrate with platform-specific OAuth handling
    // This is a placeholder for the actual OAuth implementation
    throw const UnsupportedOperationException(
      'Web OAuth flow requires platform-specific implementation. '
      'Please implement GitHubOAuthHandler for your platform.',
    );
  }

  /// Performs device-based OAuth flow for CLI/desktop apps
  Future<GitHubOAuthResult> _performDeviceOAuthFlow() async {
    // Implementation would handle GitHub device flow
    // This is a placeholder for the actual OAuth implementation
    throw const UnsupportedOperationException(
      'Device OAuth flow requires platform-specific implementation. '
      'Please implement GitHubDeviceFlowHandler for your platform.',
    );
  }

  /// Handles repository selection or creation
  Future<GitHubRepositoryResult> _handleRepositorySelection() async {
    if (_repositoryConfig == null || _github == null) {
      throw const ConfigurationException(
        'Repository configuration is required',
      );
    }

    final currentUser = await _github!.users.getCurrentUser();
    final username = currentUser.login!;

    // If repository selection is allowed, show user their repositories
    if (_repositoryConfig!.allowSelection) {
      final repositories = await _github!.repositories
          .listRepositories()
          .toList();

      // For CLI/desktop apps, this would show a selection interface
      // For web apps, this would provide data for UI selection
      // This is a placeholder for actual repository selection UI

      // For now, use suggested name or first repository
      if (_repositoryConfig!.suggestedName != null) {
        final suggested = repositories.firstWhere(
          (final repo) => repo.name == _repositoryConfig!.suggestedName,
          orElse: () => repositories.first,
        );
        return GitHubRepositoryResult(
          owner: suggested.owner!.login,
          name: suggested.name,
          isNew: false,
        );
      }
    }

    // If repository creation is allowed and needed
    if (_repositoryConfig!.allowCreation) {
      final repoName =
          _repositoryConfig!.suggestedName ??
          _repositoryConfig!.defaultName ??
          'universal-storage-${DateTime.now().millisecondsSinceEpoch}';

      final newRepo = await _github!.repositories.createRepository(
        CreateRepository(
          repoName,
          description:
              _repositoryConfig!.defaultDescription ??
              'Created by Universal Storage Sync',
          private: _repositoryConfig!.defaultPrivate,
        ),
      );

      return GitHubRepositoryResult(
        owner: username,
        name: newRepo.name,
        isNew: true,
      );
    }

    throw const ConfigurationException(
      'No repository selection or creation options are enabled',
    );
  }

  @override
  Future<bool> isAuthenticated() async {
    if (!_isInitialized || _github == null) return false;

    try {
      await _github!.users.getCurrentUser();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<String> createFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    try {
      // Check if file already exists
      final existingFile = await _getFileFromGitHub(filePath);
      if (existingFile != null) {
        throw FileAlreadyExistsException(
          'File already exists at path: $filePath',
        );
      }

      // Create the file using the correct API
      final message = commitMessage ?? 'Create file: $filePath';
      final createFile = CreateFile(
        message: message,
        content: base64.encode(utf8.encode(content)),
        path: filePath,
        branch: _branchName,
      );
      final createResult = await retry(
        () => _github!.repositories.createFile(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          createFile,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      return createResult.commit?.sha ?? '';
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to create file: $filePath');
    }
  }

  @override
  Future<String?> getFile(final String filePath) async {
    _ensureInitialized();

    try {
      final file = await _getFileFromGitHub(filePath);
      if (file == null) return null;

      // Use the text property which automatically decodes base64 content
      return file.text;
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null;
      }
      throw _handleGitHubError(e, 'Failed to read file: $filePath');
    }
  }

  @override
  Future<String> updateFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    try {
      // Get existing file to obtain SHA
      final existingFile = await _getFileFromGitHub(filePath);
      if (existingFile == null) {
        throw FileNotFoundException('File not found at path: $filePath');
      }

      // Update the file using the correct API
      final message = commitMessage ?? 'Update file: $filePath';
      final updateResult = await retry(
        () => _github!.repositories.updateFile(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          filePath,
          message,
          base64.encode(utf8.encode(content)),
          existingFile.sha!,
          branch: _branchName,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      return updateResult.commit?.sha ?? '';
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to update file: $filePath');
    }
  }

  @override
  Future<void> deleteFile(
    final String filePath, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    try {
      // Get existing file to obtain SHA
      final existingFile = await _getFileFromGitHub(filePath);
      if (existingFile == null) {
        throw FileNotFoundException('File not found at path: $filePath');
      }

      // Delete the file using the correct API
      final message = commitMessage ?? 'Delete file: $filePath';
      await retry(
        () => _github!.repositories.deleteFile(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          filePath,
          message,
          existingFile.sha!,
          _branchName,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to delete file: $filePath');
    }
  }

  @override
  Future<List<String>> listFiles(final String directoryPath) async {
    _ensureInitialized();

    try {
      final contents = await retry(
        () => _github!.repositories.getContents(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          directoryPath.isEmpty ? '/' : directoryPath,
          ref: _branchName,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      if (contents.isFile) {
        return [contents.file!.name!];
      } else {
        return contents.tree!.map((final item) => item.name!).toList();
      }
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return [];
      }
      throw _handleGitHubError(
        e,
        'Failed to list files in: ${directoryPath.isEmpty ? '/' : directoryPath}',
      );
    }
  }

  @override
  Future<void> restore(final String filePath, {final String? versionId}) async {
    _ensureInitialized();

    if (versionId == null) {
      throw const UnsupportedOperationException(
        'GitHub API provider requires versionId (commit SHA) for restore operations',
      );
    }

    try {
      // Get file content from specific commit
      final contents = await retry(
        () => _github!.repositories.getContents(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          filePath,
          ref: versionId,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      if (!contents.isFile || contents.file == null) {
        throw FileNotFoundException('File not found at path: $filePath');
      }

      final fileContent = contents.file!;
      if (fileContent.content == null) {
        throw const GitHubApiException('File content is not available');
      }

      // Use the text property which automatically decodes base64 content
      final content = fileContent.text;

      await updateFile(
        filePath,
        content,
        commitMessage: 'Restore file $filePath to version $versionId',
      );
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to restore file: $filePath');
    }
  }

  @override
  bool get supportsSync => false; // GitHub API provider doesn't need sync

  /// Initializes the repository and validates access.
  Future<void> _initializeRepository() async {
    try {
      // Check if repository exists and is accessible
      await retry(
        () => _github!.repositories.getRepository(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        throw RemoteNotFoundException(
          'Repository $_repositoryOwner/$_repositoryName not found or not accessible',
        );
      } else if (e.toString().contains('401') || e.toString().contains('403')) {
        throw AuthenticationFailedException(
          'Authentication failed for repository $_repositoryOwner/$_repositoryName. Check token permissions.',
        );
      } else {
        throw _handleGitHubError(e, 'Failed to access repository');
      }
    }

    // Validate branch exists
    await _validateBranch();
  }

  /// Validates that the specified branch exists.
  Future<void> _validateBranch() async {
    try {
      await retry(
        () => _github!.repositories.getBranch(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          _branchName,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        throw RemoteNotFoundException(
          'Branch $_branchName not found in repository $_repositoryOwner/$_repositoryName',
        );
      } else {
        throw _handleGitHubError(e, 'Failed to validate branch');
      }
    }
  }

  /// Gets file content from GitHub API.
  Future<GitHubFile?> _getFileFromGitHub(final String filePath) async {
    try {
      final contents = await retry(
        () => _github!.repositories.getContents(
          RepositorySlug(_repositoryOwner!, _repositoryName!),
          filePath,
          ref: _branchName,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      return contents.isFile ? contents.file : null;
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null;
      }
      rethrow;
    }
  }

  /// Handles GitHub API errors and converts them to appropriate storage exceptions.
  StorageException _handleGitHubError(
    final Object error,
    final String context,
  ) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('rate limit') || errorStr.contains('403')) {
      return GitHubRateLimitException(
        '$context: GitHub API rate limit exceeded',
      );
    } else if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
      return AuthenticationFailedException('$context: Authentication failed');
    } else if (errorStr.contains('404') || errorStr.contains('not found')) {
      return RemoteNotFoundException('$context: Resource not found');
    } else if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return const NetworkTimeoutException('GitHub API request timed out');
    } else {
      return GitHubApiException('$context: $error');
    }
  }

  /// Determines if an error is retryable.
  bool _isRetryableError(final Object error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
        errorStr.contains('network') ||
        errorStr.contains('connection') ||
        (errorStr.contains('500') ||
            errorStr.contains('502') ||
            errorStr.contains('503'));
  }

  void _ensureInitialized() {
    if (!_isInitialized || _github == null) {
      throw const AuthenticationException(
        'Provider not initialized. Call init() first.',
      );
    }
  }
}

/// Result of GitHub OAuth authentication
class GitHubOAuthResult {
  const GitHubOAuthResult({
    required this.accessToken,
    this.refreshToken,
    this.scope,
    this.tokenType = 'bearer',
  });

  final String accessToken;
  final String? refreshToken;
  final String? scope;
  final String tokenType;
}

/// Result of GitHub repository selection/creation
class GitHubRepositoryResult {
  const GitHubRepositoryResult({
    required this.owner,
    required this.name,
    required this.isNew,
  });

  final String owner;
  final String name;
  final bool isNew;
}
