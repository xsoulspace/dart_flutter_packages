import 'dart:convert';

import 'package:github/github.dart';
import 'package:retry/retry.dart';

import '../config/storage_config.dart';
import '../exceptions/storage_exceptions.dart';
import '../models/version_control_models.dart';
import '../storage_provider.dart';
import 'version_control_service.dart';

/// {@template github_api_storage_provider}
/// A storage provider that uses GitHub API directly for file operations.
///
/// This provider operates entirely through GitHub's REST API and requires
/// a pre-acquired access token. It does not handle authentication flows
/// or repository selection - these concerns are handled by external components.
///
/// Key characteristics:
/// - Requires valid GitHub access token with appropriate permissions
/// - Operates on a single, pre-configured repository
/// - No local offline capability
/// - Direct API-based file operations only
/// - Exposes low-level repository management primitives
/// {@endtemplate}
class GitHubApiStorageProvider extends StorageProvider
    implements VersionControlService {
  /// {@macro github_api_storage_provider}
  GitHubApiStorageProvider();

  GitHub? _github;
  String? _authToken;
  String? _repositoryOwner;
  String? _repositoryName;
  var _branchName = 'main';
  var _isInitialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! GitHubApiConfig) {
      throw ArgumentError(
        'Expected GitHubApiConfig, got ${config.runtimeType}',
      );
    }

    _authToken = config.authToken;
    _repositoryOwner = config.repositoryOwner;
    _repositoryName = config.repositoryName;
    _branchName = config.branchName;

    // Initialize GitHub client with the provided token
    _github = GitHub(auth: Authentication.withToken(_authToken));

    // Verify repository access
    await _initializeRepository();
    _isInitialized = true;
  }

  /// Initializes and verifies repository access
  Future<void> _initializeRepository() async {
    try {
      // Verify repository access by getting repository information
      final slug = RepositorySlug(_repositoryOwner!, _repositoryName!);
      final repo = await _github!.repositories.getRepository(slug);

      if (repo.name != _repositoryName) {
        throw ConfigurationException(
          'Repository verification failed: '
          'expected $_repositoryName, got ${repo.name}',
        );
      }
    } catch (e) {
      throw ConfigurationException(
        'Failed to access repository $_repositoryOwner/$_repositoryName: $e',
      );
    }
  }

  /// Ensures the provider is properly initialized
  void _ensureInitialized() {
    if (!_isInitialized || _github == null) {
      throw const ConfigurationException(
        'Provider not initialized. Call initWithConfig() first.',
      );
    }
  }

  // ========== Low-Level Repository Primitives ==========

  /// Lists all repositories accessible to the authenticated user
  @override
  Future<List<VcRepository>> listRepositories() async {
    _ensureInitialized();

    try {
      final repos = await retry(
        () => _github!.repositories.listRepositories().toList(),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
      return repos
          .map(
            (final repo) => VcRepository({
              'id': repo.id.toString(),
              'name': repo.name,
              'description': repo.description,
              'clone_url': repo.cloneUrl,
              'default_branch': repo.defaultBranch,
              'is_private': repo.isPrivate,
              'owner': repo.owner?.login ?? '',
              'full_name': repo.fullName,
              'web_url': repo.htmlUrl,
            }),
          )
          .toList();
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to list repositories');
    }
  }

  /// Creates a new repository
  @override
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  ) async {
    _ensureInitialized();

    try {
      final repo = await retry(
        () => _github!.repositories.createRepository(
          CreateRepository(
            details.name,
            description: details.description,
            private: details.isPrivate,
            autoInit: details.initializeWithReadme,
            licenseTemplate: details.license,
          ),
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
      return VcRepository({
        'id': repo.id.toString(),
        'name': repo.name,
        'description': repo.description,
        'clone_url': repo.cloneUrl,
        'default_branch': repo.defaultBranch,
        'is_private': repo.isPrivate,
        'owner': repo.owner?.login ?? '',
        'full_name': repo.fullName,
        'web_url': repo.htmlUrl,
      });
    } catch (e) {
      throw _handleGitHubError(
        e,
        'Failed to create repository: ${details.name}',
      );
    }
  }

  /// Gets information about the current repository
  @override
  Future<VcRepository> getRepositoryInfo() async {
    _ensureInitialized();

    try {
      final slug = RepositorySlug(_repositoryOwner!, _repositoryName!);
      final repo = await retry(
        () => _github!.repositories.getRepository(slug),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
      return VcRepository({
        'id': repo.id.toString(),
        'name': repo.name,
        'description': repo.description,
        'clone_url': repo.cloneUrl,
        'default_branch': repo.defaultBranch,
        'is_private': repo.isPrivate,
        'owner': repo.owner?.login ?? '',
        'full_name': repo.fullName,
        'web_url': repo.htmlUrl,
      });
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to get repository info');
    }
  }

  /// Lists branches in the current repository
  @override
  Future<List<VcBranch>> listBranches() async {
    _ensureInitialized();

    try {
      final slug = RepositorySlug(_repositoryOwner!, _repositoryName!);
      final branches = await retry(
        () => _github!.repositories.listBranches(slug).toList(),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
      return branches
          .map(
            (final branch) => VcBranch({
              'name': branch.name,
              'commit_sha': branch.commit?.sha ?? '',
              'is_default': branch.name == _branchName,
            }),
          )
          .toList();
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to list branches');
    }
  }

  /// Gets the current authenticated user
  Future<User> getCurrentUser() async {
    _ensureInitialized();

    try {
      return await retry(
        () => _github!.users.getCurrentUser(),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to get current user');
    }
  }

  // ========== Storage Provider Implementation ==========

  @override
  Future<bool> isAuthenticated() async {
    if (!_isInitialized || _github == null) return false;

    try {
      await getCurrentUser();
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

      // Create the file
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

      // Update the file
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

      // Delete the file
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
        'Failed to list files in: '
        '${directoryPath.isEmpty ? '/' : directoryPath}',
      );
    }
  }

  @override
  Future<void> restore(final String filePath, {final String? versionId}) async {
    _ensureInitialized();

    if (versionId == null) {
      throw const UnsupportedOperationException(
        'GitHub API provider requires '
        'versionId (commit SHA) for restore operations',
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

      // Update current file with content from the specified version
      await updateFile(
        filePath,
        contents.file?.text ?? '',
        commitMessage: 'Restore $filePath to version $versionId',
      );
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to restore file: $filePath');
    }
  }

  // ========== Helper Methods ==========

  /// Gets a file from GitHub API
  Future<GitHubFile?> _getFileFromGitHub(final String filePath) async {
    try {
      final contents = await _github!.repositories.getContents(
        RepositorySlug(_repositoryOwner!, _repositoryName!),
        filePath,
        ref: _branchName,
      );
      return contents.isFile ? contents.file : null;
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null;
      }
      rethrow;
    }
  }

  /// Determines if an error is retryable
  bool _isRetryableError(final Exception e) {
    final errorString = e.toString().toLowerCase();
    return errorString.contains('timeout') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504');
  }

  /// Handles GitHub API errors and converts them to appropriate exceptions
  Exception _handleGitHubError(final Object error, final String context) {
    final errorString = error.toString();

    if (errorString.contains('401') || errorString.contains('Unauthorized')) {
      return const AuthenticationException(
        'Authentication failed: Invalid or expired token',
      );
    }

    if (errorString.contains('403') || errorString.contains('Forbidden')) {
      return const AuthenticationException(
        'Access denied: Insufficient permissions',
      );
    }

    if (errorString.contains('404') || errorString.contains('Not Found')) {
      return const FileNotFoundException('Resource not found');
    }

    if (errorString.contains('422') ||
        errorString.contains('Unprocessable Entity')) {
      return const ConfigurationException('Invalid request data');
    }

    return GitHubApiException('$context: $errorString');
  }

  @override
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  ) {
    // TODO: implement cloneRepository
    throw UnimplementedError();
  }

  @override
  Future<void> setRepository(final VcRepositoryId repositoryId) {
    // TODO: implement setRepository
    throw UnimplementedError();
  }
}
