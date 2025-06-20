import 'package:git/git.dart';
import 'package:github/github.dart';

import '../exceptions/storage_exceptions.dart';
import '../models/models.dart';
import 'version_control_service.dart';

/// GitHub implementation of [VersionControlService].
///
/// Provides repository operations using the GitHub API with provider-agnostic
/// models for seamless integration with other version control systems.
class GitHubVersionControlService implements VersionControlService {
  GitHubVersionControlService({required this.github, this.currentRepository});

  final GitHub github;
  VcRepositoryId? currentRepository;

  @override
  Future<List<VcRepository>> listRepositories() async {
    try {
      final repos = await github.repositories.listRepositories().toList();
      return repos.map(_mapRepository).toList();
    } catch (e) {
      throw GitHubApiException('Failed to list repositories: $e');
    }
  }

  @override
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  ) async {
    try {
      final createRequest = CreateRepository(
        details.name,
        description: details.description.isEmpty ? null : details.description,
        private: details.isPrivate,
        autoInit: details.initializeWithReadme,
        licenseTemplate: details.license.isEmpty ? null : details.license,
        gitignoreTemplate: details.gitignoreTemplate.isEmpty
            ? null
            : details.gitignoreTemplate,
      );

      final repo = await github.repositories.createRepository(createRequest);
      return _mapRepository(repo);
    } catch (e) {
      throw RepositoryCreationException('Failed to create repository: $e');
    }
  }

  @override
  Future<VcRepository> getRepositoryInfo() async {
    if (currentRepository == null || currentRepository!.isEmpty) {
      throw const ConfigurationException('No repository configured');
    }

    try {
      final repo = await github.repositories.getRepository(
        RepositorySlug.full(currentRepository!.value),
      );
      return _mapRepository(repo);
    } catch (e) {
      throw GitHubApiException('Failed to get repository info: $e');
    }
  }

  @override
  Future<List<VcBranch>> listBranches() async {
    if (currentRepository == null || currentRepository!.isEmpty) {
      throw const ConfigurationException('No repository configured');
    }

    try {
      final slug = RepositorySlug.full(currentRepository!.value);
      final branches = await github.repositories.listBranches(slug).toList();
      return branches.map(_mapBranch).toList();
    } catch (e) {
      throw GitHubApiException('Failed to list branches: $e');
    }
  }

  @override
  Future<void> setRepository(final VcRepositoryId repositoryId) async {
    if (repositoryId.isEmpty) {
      throw const ConfigurationException('Repository ID cannot be empty');
    }

    try {
      // Validate repository exists
      final slug = RepositorySlug.full(repositoryId.value);
      await github.repositories.getRepository(slug);
      currentRepository = repositoryId;
    } catch (e) {
      throw GitHubApiException('Failed to set repository: $e');
    }
  }

  @override
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  ) async {
    try {
      await runGit(['clone', repository.cloneUrl, localPath]);
    } catch (e) {
      throw GitConflictException('Failed to clone repository: $e');
    }
  }

  /// Maps GitHub Repository to provider-agnostic VcRepository.
  VcRepository _mapRepository(final Repository repo) => VcRepository({
    'id': repo.id.toString(),
    'name': repo.name,
    'description': repo.description ?? '',
    'clone_url': repo.cloneUrl,
    'default_branch': repo.defaultBranch ?? 'main',
    'is_private': repo.isPrivate,
    'owner': repo.owner?.login ?? '',
    'full_name': repo.fullName,
    'web_url': repo.htmlUrl,
  });

  /// Maps GitHub Branch to provider-agnostic VcBranch.
  VcBranch _mapBranch(final Branch branch) => VcBranch({
    'name': branch.name,
    'commit_sha': branch.commit?.sha ?? '',
    'is_default': false, // GitHub API doesn't provide this in branch list
    'is_protected': false, // Need separate API call for protection status
  });
}
