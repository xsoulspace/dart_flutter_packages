// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:convert';
import 'dart:developer';

import 'package:github/github.dart';
import 'package:retry/retry.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

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
  var _config = GitHubApiConfig(
    authToken: '',
    repositoryOwner: VcRepositoryOwner(''),
    repositoryName: VcRepositoryName(''),
    branchName: VcBranchName(''),
  );
  GitHub? _github;
  String? get _authToken => _config.authToken;
  VcRepositoryOwner get _repositoryOwner => _config.repositoryOwner;
  VcRepositoryName get _repositoryName => _config.repositoryName;
  RepositorySlug get _repositorySlug =>
      RepositorySlug(_repositoryOwner.value, _repositoryName.value);
  VcBranchName get _branchName => _config.branchName;
  var _isInitialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! GitHubApiConfig) {
      throw ArgumentError(
        'Expected GitHubApiConfig, got ${config.runtimeType}',
      );
    }
    _config = config;

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
      final repo = await _github!.repositories.getRepository(_repositorySlug);

      if (repo.name != _repositoryName.value) {
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
      final repo = await retry(
        () => _github!.repositories.getRepository(_repositorySlug),
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
      final branches = await retry(
        () => _github!.repositories.listBranches(_repositorySlug).toList(),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
      return branches
          .map(
            (final branch) => VcBranch({
              'name': branch.name,
              'commit_sha': branch.commit?.sha ?? '',
              'is_default': branch.name == _branchName.value,
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
    } catch (e, st) {
      log('Error: $e stackTrace: $st');
      return false;
    }
  }

  @override
  Future<FileOperationResult> createFile(
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
        branch: _branchName.value,
      );

      final createResult = await retry(
        () => _github!.repositories.createFile(_repositorySlug, createFile),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      final sha = createResult.commit?.sha ?? '';
      return FileOperationResult.created(path: filePath, revisionId: sha);
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
  Future<FileOperationResult> updateFile(
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
          _repositorySlug,
          filePath,
          message,
          base64.encode(utf8.encode(content)),
          existingFile.sha!,
          branch: _branchName.value,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      final sha = updateResult.commit?.sha ?? '';
      return FileOperationResult.updated(path: filePath, revisionId: sha);
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to update file: $filePath');
    }
  }

  @override
  Future<FileOperationResult> deleteFile(
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
      final delResult = await retry(
        () => _github!.repositories.deleteFile(
          _repositorySlug,
          filePath,
          message,
          existingFile.sha!,
          _branchName.value,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );
      // GitHub delete API doesn't return a commit SHA directly; follow-up could fetch latest
      return FileOperationResult.deleted(path: filePath);
    } catch (e) {
      throw _handleGitHubError(e, 'Failed to delete file: $filePath');
    }
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();

    try {
      final contents = await retry(
        () => _github!.repositories.getContents(
          _repositorySlug,
          directoryPath.isEmpty ? '/' : directoryPath,
          ref: _branchName.value,
        ),
        retryIf: _isRetryableError,
        maxAttempts: 3,
      );

      if (contents.isFile) {
        final f = contents.file!;
        return [
          FileEntry(
            name: f.name ?? '',
            isDirectory: false,
            size: f.size ?? 0,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        ];
      }
      return contents.tree!
          .map(
            (final item) => FileEntry(
              name: item.name ?? '',
              isDirectory: item.type == 'dir',
              modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          )
          .toList();
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
          _repositorySlug,
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
        _repositorySlug,
        filePath,
        ref: _branchName.value,
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
    // TODO(arenukvern): implement cloneRepository
    throw UnimplementedError();
  }

  @override
  Future<void> setRepository(final VcRepositoryName repositoryId) {
    // TODO(arenukvern): implement setRepository
    throw UnimplementedError();
  }
}
