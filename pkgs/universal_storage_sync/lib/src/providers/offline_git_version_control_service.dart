import 'dart:io';

import 'package:git/git.dart';
import 'package:path/path.dart' as p;

import '../exceptions/storage_exceptions.dart';
import '../models/models.dart';
import 'version_control_service.dart';

/// Offline Git implementation of [VersionControlService].
///
/// Provides repository operations using local Git commands without requiring
/// remote API access. Ideal for local-only operations or when working offline.
class OfflineGitVersionControlService implements VersionControlService {
  OfflineGitVersionControlService({
    required this.workingDirectory,
    this.currentRepository,
  });

  /// Base directory for Git operations
  final String workingDirectory;

  /// Currently configured repository path
  VcRepositoryId? currentRepository;

  @override
  Future<List<VcRepository>> listRepositories() async {
    try {
      final workingDir = Directory(workingDirectory);
      if (!workingDir.existsSync()) {
        return [];
      }

      final repos = <VcRepository>[];
      await for (final entity in workingDir.list()) {
        if (entity is Directory && await GitDir.isGitDir(entity.path)) {
          final repo = await _getRepositoryFromPath(entity.path);
          repos.add(repo);
        }
      }

      return repos;
    } catch (e) {
      throw FileNotFoundException('Failed to list repositories: $e');
    }
  }

  @override
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  ) async {
    try {
      final repoPath = p.join(workingDirectory, details.name);
      final repoDir = Directory(repoPath);

      if (repoDir.existsSync()) {
        throw FileAlreadyExistsException(
          'Repository ${details.name} already exists',
        );
      }

      // Create directory and initialize Git repo
      repoDir.createSync(recursive: true);
      final gitDir = await GitDir.init(repoPath);

      // Create initial README if requested
      if (details.initializeWithReadme) {
        final readmeFile = File(p.join(repoPath, 'README.md'));
        await readmeFile.writeAsString(
          '# ${details.name}\n\n${details.description}',
        );

        // Add and commit README
        await _runGitCommand(['add', 'README.md'], repoPath);
        await _runGitCommand([
          'commit',
          '-m',
          'Initial commit: Add README',
        ], repoPath);
      }

      return _getRepositoryFromPath(repoPath);
    } catch (e) {
      if (e is FileAlreadyExistsException) rethrow;
      throw GitConflictException('Failed to create repository: $e');
    }
  }

  @override
  Future<VcRepository> getRepositoryInfo() async {
    if (currentRepository == null || currentRepository!.isEmpty) {
      throw const ConfigurationException('No repository configured');
    }

    try {
      final repoPath = p.join(workingDirectory, currentRepository!.value);
      return await _getRepositoryFromPath(repoPath);
    } catch (e) {
      throw FileNotFoundException('Failed to get repository info: $e');
    }
  }

  @override
  Future<List<VcBranch>> listBranches() async {
    if (currentRepository == null || currentRepository!.isEmpty) {
      throw const ConfigurationException('No repository configured');
    }

    try {
      final repoPath = p.join(workingDirectory, currentRepository!.value);

      // Get local branches
      final branchResult = await _runGitCommand([
        'branch',
        '--format=%(refname:short)',
      ], repoPath);

      final branchNames = branchResult
          .split('\n')
          .where((final line) => line.trim().isNotEmpty)
          .toList();

      final branches = <VcBranch>[];
      for (final branchName in branchNames) {
        // Get latest commit for branch
        final commitSha = await _runGitCommand([
          'rev-parse',
          branchName.trim(),
        ], repoPath);

        // Check if it's the current branch
        final currentBranch = await _runGitCommand([
          'branch',
          '--show-current',
        ], repoPath);

        final isDefault = currentBranch.trim() == branchName.trim();

        branches.add(
          VcBranch({
            'name': branchName.trim(),
            'commit_sha': commitSha.trim(),
            'is_default': isDefault,
            'is_protected': false, // Local repos don't have protection
          }),
        );
      }

      return branches;
    } catch (e) {
      throw GitConflictException('Failed to list branches: $e');
    }
  }

  @override
  Future<void> setRepository(final VcRepositoryId repositoryId) async {
    if (repositoryId.isEmpty) {
      throw const ConfigurationException('Repository ID cannot be empty');
    }

    try {
      final repoPath = p.join(workingDirectory, repositoryId.value);
      if (!await GitDir.isGitDir(repoPath)) {
        throw FileNotFoundException(
          'Repository not found: ${repositoryId.value}',
        );
      }

      currentRepository = repositoryId;
    } catch (e) {
      if (e is FileNotFoundException) rethrow;
      throw GitConflictException('Failed to set repository: $e');
    }
  }

  @override
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  ) async {
    try {
      await _runGitCommand([
        'clone',
        repository.cloneUrl,
        localPath,
      ], workingDirectory);
    } catch (e) {
      throw GitConflictException('Failed to clone repository: $e');
    }
  }

  /// Runs a Git command and returns the stdout.
  Future<String> _runGitCommand(
    final List<String> args,
    final String workingDir,
  ) async {
    final result = await Process.run('git', args, workingDirectory: workingDir);
    if (result.exitCode != 0) {
      throw GitConflictException('Git command failed: ${result.stderr}');
    }
    return result.stdout.toString();
  }

  /// Creates a VcRepository from a local Git repository path.
  Future<VcRepository> _getRepositoryFromPath(final String repoPath) async {
    final repoName = p.basename(repoPath);

    // Try to get remote URL
    String cloneUrl = '';
    String webUrl = '';
    try {
      final remoteUrl = await _runGitCommand([
        'remote',
        'get-url',
        'origin',
      ], repoPath);
      cloneUrl = remoteUrl.trim();
      webUrl = cloneUrl.replaceAll('.git', ''); // Simple conversion
    } catch (e) {
      // No remote configured, use local path
      cloneUrl = repoPath;
      webUrl = repoPath;
    }

    // Get current branch as default
    String defaultBranch = 'main';
    try {
      final branchName = await _runGitCommand([
        'branch',
        '--show-current',
      ], repoPath);
      defaultBranch = branchName.trim();
      if (defaultBranch.isEmpty) defaultBranch = 'main';
    } catch (e) {
      // Ignore, use default
    }

    return VcRepository({
      'id': repoName,
      'name': repoName,
      'description': '', // Local repos don't have descriptions
      'clone_url': cloneUrl,
      'default_branch': defaultBranch,
      'is_private': true, // Local repos are considered private
      'owner': '', // No owner concept for local repos
      'full_name': repoName,
      'web_url': webUrl,
    });
  }
}
