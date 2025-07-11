// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:developer';
import 'dart:io';

import 'package:git/git.dart';
import 'package:path/path.dart' as path;
import 'package:retry/retry.dart';

import '../capabilities/version_control_service.dart';
import '../models/models.dart';
import '../storage_exceptions.dart';
import '../storage_provider.dart';

/// {@template offline_git_storage_provider}
/// A storage provider that uses a local Git repository for storage operations
/// with optional remote synchronization capabilities.
///
/// This provider is offline-first and supports version control features.
/// {@endtemplate}
class OfflineGitStorageProvider extends StorageProvider
    implements VersionControlService {
  /// {@macro offline_git_storage_provider}
  OfflineGitStorageProvider();

  var _config = OfflineGitConfig.empty;
  GitDir? _gitDir;
  String get _localPath => _config.localPath;
  VcBranchName get _branchName => _config.branchName;
  String? get _authorName => _config.authorName;
  String? get _authorEmail => _config.authorEmail;

  // Remote configuration
  VcUrl get _remoteUrl => _config.remoteUrl;
  String get _remoteName => _config.remoteName;

  // Sync strategies
  String get _defaultPullStrategy => _config.defaultPullStrategy;
  String get _defaultPushStrategy => _config.defaultPushStrategy;
  ConflictResolutionStrategy get _conflictResolution =>
      _config.conflictResolution;

  var _isInitialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! OfflineGitConfig) {
      throw ArgumentError(
        'Expected OfflineGitConfig, got ${config.runtimeType}',
      );
    }

    _config = config;

    await _initializeRepository();
    _isInitialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _isInitialized && _gitDir != null;

  @override
  Future<String> createFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath, filePath);
    final file = File(fullPath);

    // Check if file already exists
    if (file.existsSync()) {
      throw FileNotFoundException('File already exists at path: $filePath');
    }

    // Ensure parent directory exists
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    // Write file content
    await file.writeAsString(content);

    // Git add and commit
    await _gitDir!.runCommand(['add', filePath]);

    final message = commitMessage ?? 'Create file: $filePath';
    final commitHash = await _commitChanges(message);

    return commitHash;
  }

  @override
  Future<String?> getFile(final String filePath) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath, filePath);
    final file = File(fullPath);

    if (!file.existsSync()) {
      return null;
    }

    try {
      return await file.readAsString();
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw NetworkException('Failed to read file at $filePath: $e');
    }
  }

  @override
  Future<String> updateFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath, filePath);
    final file = File(fullPath);

    if (!file.existsSync()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    // Write updated content
    await file.writeAsString(content);

    // Git add and commit
    await _gitDir!.runCommand(['add', filePath]);

    final message = commitMessage ?? 'Update file: $filePath';
    final commitHash = await _commitChanges(message);

    return commitHash;
  }

  @override
  Future<void> deleteFile(
    final String filePath, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath, filePath);
    final file = File(fullPath);

    if (!file.existsSync()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    // Git remove and commit
    await _gitDir!.runCommand(['rm', filePath]);

    final message = commitMessage ?? 'Delete file: $filePath';
    await _commitChanges(message);
  }

  @override
  Future<List<String>> listFiles(final String directoryPath) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath, directoryPath);
    final directory = Directory(fullPath);

    if (!directory.existsSync()) {
      throw FileNotFoundException(
        'Directory not found at path: $directoryPath',
      );
    }

    final entities = await directory.list().toList();
    final relativePaths = <String>[];

    for (final entity in entities) {
      final relativePath = path.relative(entity.path, from: _localPath);

      // Skip .git directory and other hidden files/directories
      if (!relativePath.startsWith('.git') &&
          !path.basename(relativePath).startsWith('.')) {
        relativePaths.add(relativePath);
      }
    }

    return relativePaths;
  }

  @override
  Future<void> restore(final String filePath, {final String? versionId}) async {
    _ensureInitialized();

    try {
      if (versionId != null) {
        // Restore to specific commit
        await _gitDir!.runCommand(['checkout', versionId, '--', filePath]);
      } else {
        // Restore to HEAD (latest commit)
        await _gitDir!.runCommand(['checkout', 'HEAD', '--', filePath]);
      }
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw GitConflictException('Failed to restore $filePath: $e');
    }
  }

  @override
  bool get supportsSync => _remoteUrl != null;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    _ensureInitialized();

    if (_remoteUrl == null) {
      throw const AuthenticationException(
        'Remote URL not configured. Cannot sync without remote repository.',
      );
    }

    try {
      // 1. Setup remote if not exists
      await _ensureRemoteSetup();

      // 2. Fetch latest changes
      await _fetchRemoteChanges();

      // 3. Pull with merge strategy
      await _pullWithStrategy(pullMergeStrategy ?? _defaultPullStrategy);

      // 4. Push local changes
      await _pushWithStrategy(pushConflictStrategy ?? _defaultPushStrategy);
    } on StorageException {
      rethrow;
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw NetworkException('Sync operation failed: $e');
    }
  }

  /// Ensures remote repository is properly configured.
  Future<void> _ensureRemoteSetup() async {
    try {
      // Check if remote already exists
      final result = await _gitDir!.runCommand([
        'remote',
        'get-url',
        _remoteName,
      ]);
      final existingUrl = result.stdout.toString().trim();

      if (existingUrl != _remoteUrl!.value) {
        // Update remote URL if different
        await _gitDir!.runCommand([
          'remote',
          'set-url',
          _remoteName,
          _remoteUrl!.value,
        ]);
      }
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      // Remote doesn't exist, add it
      try {
        await _gitDir!.runCommand([
          'remote',
          'add',
          _remoteName,
          _remoteUrl!.value,
        ]);
      } catch (e) {
        throw RemoteNotFoundException('Failed to add remote $_remoteName: $e');
      }
    }

    // Validate remote accessibility
    await _validateRemoteAccess();
  }

  /// Validates that the remote repository is accessible.
  Future<void> _validateRemoteAccess() async {
    try {
      await retry(
        () => _gitDir!.runCommand(['ls-remote', '--heads', _remoteName]),
        maxAttempts: 3,
      );
    } catch (e) {
      if (e.toString().contains('Authentication failed') ||
          e.toString().contains('access denied')) {
        throw AuthenticationFailedException(
          'Authentication failed for remote $_remoteName. Check credentials.',
        );
      } else if (e.toString().contains('not found') ||
          e.toString().contains('does not exist')) {
        throw RemoteNotFoundException(
          'Remote repository not found: $_remoteUrl',
        );
      } else if (e.toString().contains('timeout') ||
          e.toString().contains('timed out')) {
        throw const NetworkTimeoutException(
          'Network timeout while accessing remote repository',
        );
      } else {
        throw NetworkException('Failed to access remote repository: $e');
      }
    }
  }

  /// Fetches latest changes from remote repository.
  Future<void> _fetchRemoteChanges() async {
    try {
      await retry(
        () => _gitDir!.runCommand(['fetch', _remoteName]),
        retryIf: (final e) => !e.toString().contains('Authentication'),
        maxAttempts: 3,
      );
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw NetworkException('Failed to fetch from remote: $e');
    }
  }

  /// Pulls changes from remote with specified strategy.
  Future<void> _pullWithStrategy(final String strategy) async {
    try {
      switch (strategy) {
        case 'merge':
          await _gitDir!.runCommand(['pull', _remoteName, _branchName!.value]);
        case 'rebase':
          await _gitDir!.runCommand([
            'pull',
            '--rebase',
            _remoteName,
            _branchName!.value,
          ]);
        case 'ff-only':
          await _gitDir!.runCommand([
            'pull',
            '--ff-only',
            _remoteName,
            _branchName!.value,
          ]);
        default:
          await _gitDir!.runCommand(['pull', _remoteName, _branchName!.value]);
      }
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      if (e.toString().contains('CONFLICT') ||
          e.toString().contains('conflict')) {
        await _handlePullConflicts();
      } else if (e.toString().contains('non-fast-forward') ||
          e.toString().contains('fast-forward')) {
        throw const SyncConflictException(
          'Cannot fast-forward. Use different pull strategy '
          'or resolve conflicts manually.',
        );
      } else {
        throw GitConflictException('Pull operation failed: $e');
      }
    }
  }

  /// Handles pull conflicts based on resolution strategy.
  Future<void> _handlePullConflicts() async {
    switch (_conflictResolution) {
      case ConflictResolutionStrategy.clientAlwaysRight:
        await _resolveConflictsClientWins();
      case ConflictResolutionStrategy.serverAlwaysRight:
        await _resolveConflictsServerWins();
      case ConflictResolutionStrategy.manualResolution:
        throw const MergeConflictException(
          'Merge conflicts detected. Manual resolution required.',
        );
      case ConflictResolutionStrategy.lastWriteWins:
        await _resolveConflictsLastWriteWins();
    }
  }

  /// Resolves conflicts by preferring local (client) changes.
  Future<void> _resolveConflictsClientWins() async {
    try {
      // Get list of conflicted files
      final result = await _gitDir!.runCommand([
        'diff',
        '--name-only',
        '--diff-filter=U',
      ]);
      final conflictedFiles = result.stdout
          .toString()
          .trim()
          .split('\n')
          .where((final line) => line.isNotEmpty)
          .toList();

      for (final file in conflictedFiles) {
        // Use local version (ours)
        await _gitDir!.runCommand(['checkout', '--ours', file]);
        await _gitDir!.runCommand(['add', file]);
      }

      // Complete the merge
      await _gitDir!.runCommand(['commit', '--no-edit']);
    } catch (e) {
      throw MergeConflictException(
        'Failed to resolve conflicts with client-wins strategy: $e',
      );
    }
  }

  /// Resolves conflicts by preferring remote (server) changes.
  Future<void> _resolveConflictsServerWins() async {
    try {
      // Get list of conflicted files
      final result = await _gitDir!.runCommand([
        'diff',
        '--name-only',
        '--diff-filter=U',
      ]);
      final conflictedFiles = result.stdout
          .toString()
          .trim()
          .split('\n')
          .where((final line) => line.isNotEmpty)
          .toList();

      for (final file in conflictedFiles) {
        // Use remote version (theirs)
        await _gitDir!.runCommand(['checkout', '--theirs', file]);
        await _gitDir!.runCommand(['add', file]);
      }

      // Complete the merge
      await _gitDir!.runCommand(['commit', '--no-edit']);
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw MergeConflictException(
        'Failed to resolve conflicts with server-wins strategy: $e',
      );
    }
  }

  /// Resolves conflicts using timestamp-based resolution.
  Future<void> _resolveConflictsLastWriteWins() async {
    try {
      // For simplicity, this implementation uses client-wins
      // In a real implementation, you would compare file timestamps
      await _resolveConflictsClientWins();
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw MergeConflictException(
        'Failed to resolve conflicts with last-write-wins strategy: $e',
      );
    }
  }

  /// Pushes local changes to remote with specified strategy.
  Future<void> _pushWithStrategy(final String strategy) async {
    try {
      switch (strategy) {
        case 'rebase-local':
          await _pushWithRebaseLocal();
        case 'force-with-lease':
          await _gitDir!.runCommand([
            'push',
            '--force-with-lease',
            _remoteName,
            _branchName!.value,
          ]);
        case 'fail-on-conflict':
          await _gitDir!.runCommand(['push', _remoteName, _branchName!.value]);
        default:
          await _pushWithRebaseLocal();
      }
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      if (e.toString().contains('non-fast-forward') ||
          e.toString().contains('rejected')) {
        if (strategy == 'fail-on-conflict') {
          throw const SyncConflictException(
            'Push rejected due to non-fast-forward. Remote has newer commits.',
          );
        } else {
          throw GitConflictException('Push operation failed: $e');
        }
      } else if (e.toString().contains('Authentication') ||
          e.toString().contains('access denied')) {
        throw AuthenticationFailedException('Push authentication failed: $e');
      } else {
        throw NetworkException('Push operation failed: $e');
      }
    }
  }

  /// Pushes with rebase-local strategy (client is always right).
  Future<void> _pushWithRebaseLocal() async {
    try {
      // Try normal push first
      await _gitDir!.runCommand(['push', _remoteName, _branchName!.value]);
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      if (e.toString().contains('non-fast-forward') ||
          e.toString().contains('rejected')) {
        // Rebase local commits on top of remote
        try {
          await _gitDir!.runCommand([
            'pull',
            '--rebase',
            _remoteName,
            _branchName!.value,
          ]);
          await _gitDir!.runCommand(['push', _remoteName, _branchName!.value]);
        } catch (rebaseError, stackTrace) {
          log('Rebase error: $rebaseError', stackTrace: stackTrace);
          if (rebaseError.toString().contains('CONFLICT')) {
            // Handle rebase conflicts with client-wins strategy
            await _handlePullConflicts();
            await _gitDir!.runCommand(['rebase', '--continue']);
            await _gitDir!.runCommand([
              'push',
              _remoteName,
              _branchName!.value,
            ]);
          } else {
            throw GitConflictException('Rebase operation failed: $rebaseError');
          }
        }
      } else {
        rethrow;
      }
    }
  }

  /// Initializes the Git repository if it doesn't exist.
  Future<void> _initializeRepository() async {
    final directory = Directory(_localPath);

    // Create directory if it doesn't exist
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    // Check if it's already a Git repository
    final gitDirectory = Directory(path.join(_localPath, '.git'));
    if (gitDirectory.existsSync()) {
      // Open existing repository
      _gitDir = await GitDir.fromExisting(_localPath);
    } else {
      // Initialize new repository
      _gitDir = await GitDir.init(_localPath, initialBranch: _branchName.value);
    }

    // Configure Git user if provided
    if (_authorName != null) {
      await _gitDir!.runCommand(['config', 'user.name', _authorName!]);
    }
    if (_authorEmail != null) {
      await _gitDir!.runCommand(['config', 'user.email', _authorEmail!]);
    }

    // Ensure we're on the correct branch
    await _ensureBranch();
  }

  /// Ensures the specified branch exists and is checked out.
  Future<void> _ensureBranch() async {
    try {
      // Try to checkout the branch
      await _gitDir!.runCommand(['checkout', _branchName!.value]);
    } catch (e) {
      // Branch doesn't exist, create it
      try {
        await _gitDir!.runCommand(['checkout', '-b', _branchName!.value]);
      } catch (e) {
        // If we can't create the branch, we might be in an empty repo
        // Create an initial commit first
        await _createInitialCommit();
        await _gitDir!.runCommand(['checkout', '-b', _branchName!.value]);
      }
    }
  }

  /// Creates an initial commit if the repository is empty.
  Future<void> _createInitialCommit() async {
    try {
      // Create a .gitkeep file to have something to commit
      final gitkeepFile = File(path.join(_localPath, '.gitkeep'));
      await gitkeepFile.writeAsString('');

      await _gitDir!.runCommand(['add', '.gitkeep']);
      await _commitChanges('Initial commit');
    } catch (e) {
      // Ignore errors - this is just to bootstrap the repository
    }
  }

  /// Commits changes with the given message.
  Future<String> _commitChanges(final String message) async {
    try {
      await _gitDir!.runCommand(['commit', '-m', message]);

      // Get the commit hash
      final hashResult = await _gitDir!.runCommand(['rev-parse', 'HEAD']);
      return hashResult.stdout.toString().trim();
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      throw GitConflictException('Failed to commit changes: $e');
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized || _gitDir == null) {
      throw const AuthenticationException(
        'Provider not initialized. Call init() first.',
      );
    }
  }

  Future<void> _runGitCommand(final List<String> args) async {
    await _gitDir!.runCommand(args);
  }

  @override
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  ) => throw UnsupportedError('Offline Git does not support cloning');

  @override
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  ) async {
    await _runGitCommand(['init', '-b', details.name]);
    return VcRepository({
      'id': '1',
      'name': details.name,
      'description': details.description,
    });
  }

  @override
  Future<VcRepository> getRepositoryInfo() {
    // TODO(arenukvern): implement getRepositoryInfo
    throw UnimplementedError();
  }

  @override
  Future<List<VcBranch>> listBranches() {
    // TODO(arenukvern): implement listBranches
    throw UnimplementedError();
  }

  @override
  Future<List<VcRepository>> listRepositories() {
    // TODO(arenukvern): implement listRepositories
    throw UnimplementedError();
  }

  @override
  Future<void> setRepository(final VcRepositoryName repositoryId) {
    // TODO(arenukvern): implement setRepository
    throw UnimplementedError();
  }
}
