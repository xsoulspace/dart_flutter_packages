import 'dart:convert';

import 'package:github/github.dart';
import 'package:retry/retry.dart';

import '../exceptions/storage_exceptions.dart';
import '../storage_provider.dart';

/// {@template github_api_storage_provider}
/// A storage provider that uses GitHub API directly for all operations.
///
/// This provider does not maintain local Git repositories and operates
/// entirely through GitHub's REST API. It's suited for scenarios where
/// no local offline capability is needed or where Git CLI is unavailable.
/// {@endtemplate}
class GitHubApiStorageProvider extends StorageProvider {
  /// {@macro github_api_storage_provider}
  GitHubApiStorageProvider();

  GitHub? _github;
  String? _authToken;
  String? _repositoryOwner;
  String? _repositoryName;
  String _branchName = 'main';
  bool _isInitialized = false;

  @override
  Future<void> init(Map<String, dynamic> config) async {
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

    // Validate repository access
    await _initializeRepository();
    _isInitialized = true;
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
    String filePath,
    String content, {
    String? commitMessage,
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
  Future<String?> getFile(String filePath) async {
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
    String filePath,
    String content, {
    String? commitMessage,
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
  Future<void> deleteFile(String filePath, {String? commitMessage}) async {
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
  Future<List<String>> listFiles(String directoryPath) async {
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

      final filePaths = <String>[];
      if (contents.isDirectory && contents.tree != null) {
        for (final item in contents.tree!) {
          if (item.path != null) {
            filePaths.add(item.path!);
          }
        }
      }

      return filePaths;
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        throw FileNotFoundException(
          'Directory not found at path: $directoryPath',
        );
      }
      throw _handleGitHubError(e, 'Failed to list files in: $directoryPath');
    }
  }

  @override
  Future<void> restore(String filePath, {String? versionId}) async {
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
  Future<GitHubFile?> _getFileFromGitHub(String filePath) async {
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
  StorageException _handleGitHubError(Object error, String context) {
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
  bool _isRetryableError(Object error) {
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
