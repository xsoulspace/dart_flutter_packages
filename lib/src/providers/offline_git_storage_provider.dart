import 'dart:io';

import 'package:git/git.dart';
import 'package:path/path.dart' as path;

import '../exceptions/storage_exceptions.dart';
import '../storage_provider.dart';

/// {@template offline_git_storage_provider}
/// A storage provider that uses a local Git repository for storage operations
/// with optional remote synchronization capabilities.
///
/// This provider is offline-first and supports version control features.
/// {@endtemplate}
class OfflineGitStorageProvider extends StorageProvider {
  /// {@macro offline_git_storage_provider}
  OfflineGitStorageProvider();
  GitDir? _gitDir;
  String? _localPath;
  String? _branchName;
  String? _authorName;
  String? _authorEmail;
  bool _isInitialized = false;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    final localPath = config['localPath'] as String?;
    final branchName = config['branchName'] as String?;

    if (localPath == null || localPath.isEmpty) {
      throw const AuthenticationException(
        'localPath is required for OfflineGitStorageProvider',
      );
    }

    if (branchName == null || branchName.isEmpty) {
      throw const AuthenticationException(
        'branchName is required for OfflineGitStorageProvider',
      );
    }

    _localPath = localPath;
    _branchName = branchName;
    _authorName = config['authorName'] as String?;
    _authorEmail = config['authorEmail'] as String?;

    await _initializeRepository();
    _isInitialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _isInitialized && _gitDir != null;

  @override
  Future<String> createFile(
    String filePath,
    String content, {
    String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath!, filePath);
    final file = File(fullPath);

    // Check if file already exists
    if (await file.exists()) {
      throw FileNotFoundException('File already exists at path: $filePath');
    }

    // Ensure parent directory exists
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
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
  Future<String?> getFile(String filePath) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath!, filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
      return null;
    }

    try {
      return await file.readAsString();
    } catch (e) {
      throw NetworkException('Failed to read file at $filePath: $e');
    }
  }

  @override
  Future<String> updateFile(
    String filePath,
    String content, {
    String? commitMessage,
  }) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath!, filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
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
  Future<void> deleteFile(String filePath, {String? commitMessage}) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath!, filePath);
    final file = File(fullPath);

    if (!await file.exists()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }

    // Git remove and commit
    await _gitDir!.runCommand(['rm', filePath]);

    final message = commitMessage ?? 'Delete file: $filePath';
    await _commitChanges(message);
  }

  @override
  Future<List<String>> listFiles(String directoryPath) async {
    _ensureInitialized();

    final fullPath = path.join(_localPath!, directoryPath);
    final directory = Directory(fullPath);

    if (!await directory.exists()) {
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
  Future<void> restore(String filePath, {String? versionId}) async {
    _ensureInitialized();

    try {
      if (versionId != null) {
        // Restore to specific commit
        await _gitDir!.runCommand(['checkout', versionId, '--', filePath]);
      } else {
        // Restore to HEAD (latest commit)
        await _gitDir!.runCommand(['checkout', 'HEAD', '--', filePath]);
      }
    } catch (e) {
      throw GitConflictException('Failed to restore $filePath: $e');
    }
  }

  @override
  bool get supportsSync => true; // Will support sync when implemented

  @override
  Future<void> sync({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  }) async {
    // TODO: Implement in Stage 3
    throw const UnsupportedOperationException(
      'OfflineGitStorageProvider sync is not yet implemented. '
      'This will be available in Stage 3 of development.',
    );
  }

  /// Initializes the Git repository if it doesn't exist.
  Future<void> _initializeRepository() async {
    final directory = Directory(_localPath!);

    // Create directory if it doesn't exist
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // Check if it's already a Git repository
    final gitDirectory = Directory(path.join(_localPath!, '.git'));
    if (await gitDirectory.exists()) {
      // Open existing repository
      _gitDir = await GitDir.fromExisting(_localPath!);
    } else {
      // Initialize new repository
      _gitDir = await GitDir.init(_localPath!);
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
      await _gitDir!.runCommand(['checkout', _branchName!]);
    } catch (e) {
      // Branch doesn't exist, create it
      try {
        await _gitDir!.runCommand(['checkout', '-b', _branchName!]);
      } catch (e) {
        // If we can't create the branch, we might be in an empty repo
        // Create an initial commit first
        await _createInitialCommit();
        await _gitDir!.runCommand(['checkout', '-b', _branchName!]);
      }
    }
  }

  /// Creates an initial commit if the repository is empty.
  Future<void> _createInitialCommit() async {
    try {
      // Create a .gitkeep file to have something to commit
      final gitkeepFile = File(path.join(_localPath!, '.gitkeep'));
      await gitkeepFile.writeAsString('');

      await _gitDir!.runCommand(['add', '.gitkeep']);
      await _commitChanges('Initial commit');
    } catch (e) {
      // Ignore errors - this is just to bootstrap the repository
    }
  }

  /// Commits changes with the given message.
  Future<String> _commitChanges(String message) async {
    try {
      final result = await _gitDir!.runCommand(['commit', '-m', message]);

      // Get the commit hash
      final hashResult = await _gitDir!.runCommand(['rev-parse', 'HEAD']);
      return hashResult.stdout.toString().trim();
    } catch (e) {
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
}
