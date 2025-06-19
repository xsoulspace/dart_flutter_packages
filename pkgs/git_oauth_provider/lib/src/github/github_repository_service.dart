import 'package:github/github.dart' as gh;

import '../exceptions/oauth_exceptions.dart';
import '../models/models.dart';
import '../services/repository_service.dart';
import 'github_oauth_provider.dart';

/// GitHub repository management service
class GitHubRepositoryService implements RepositoryService {
  GitHubRepositoryService(this._oauthProvider);

  final GitHubOAuthProvider _oauthProvider;
  gh.GitHub? _github;

  @override
  Future<List<RepositoryInfo>> getUserRepositories() async {
    final github = await _getGitHubClient();

    try {
      final repos = await github.repositories.listRepositories().toList();
      return repos.map(_convertRepository).toList();
    } catch (e) {
      throw ApiException('Failed to fetch repositories', e.toString());
    }
  }

  @override
  Future<List<RepositoryInfo>> getOrganizationRepositories(
    final String orgName,
  ) async {
    final github = await _getGitHubClient();

    try {
      final repos = await github.repositories
          .listOrganizationRepositories(orgName)
          .toList();
      return repos.map(_convertRepository).toList();
    } catch (e) {
      throw ApiException(
        'Failed to fetch organization repositories',
        e.toString(),
      );
    }
  }

  @override
  Future<RepositoryInfo> createRepository(
    final CreateRepositoryRequest request,
  ) async {
    final github = await _getGitHubClient();

    try {
      final createRepo = gh.CreateRepository(
        request.name,
        description: request.description,
        private: request.isPrivate,
        autoInit: request.autoInit,
        gitignoreTemplate: request.gitignoreTemplate,
        licenseTemplate: request.licenseTemplate,
      );

      final repo = await github.repositories.createRepository(createRepo);
      return _convertRepository(repo);
    } catch (e) {
      if (e.toString().contains('422')) {
        throw RepositoryException.alreadyExists(request.name);
      }
      throw RepositoryException('Failed to create repository', e.toString());
    }
  }

  @override
  Future<RepositoryInfo?> getRepository(
    final String owner,
    final String name,
  ) async {
    final github = await _getGitHubClient();

    try {
      final repo = await github.repositories.getRepository(
        gh.RepositorySlug(owner, name),
      );
      return _convertRepository(repo);
    } catch (e) {
      if (e.toString().contains('404')) {
        return null;
      }
      throw RepositoryException('Failed to get repository', e.toString());
    }
  }

  @override
  Future<List<RepositoryInfo>> searchRepositories(
    final String query, {
    final int? limit,
  }) async {
    final github = await _getGitHubClient();

    try {
      final results = github.search.repositories(query);
      if (limit != null) {
        final limitedResults = await results.take(limit).toList();
        return limitedResults.map(_convertRepository).toList();
      } else {
        final allResults = await results.toList();
        return allResults.map(_convertRepository).toList();
      }
    } catch (e) {
      throw ApiException('Failed to search repositories', e.toString());
    }
  }

  @override
  Future<void> deleteRepository(final String owner, final String name) async {
    final github = await _getGitHubClient();

    try {
      await github.repositories.deleteRepository(
        gh.RepositorySlug(owner, name),
      );
    } catch (e) {
      if (e.toString().contains('404')) {
        throw RepositoryException.notFound('$owner/$name');
      }
      if (e.toString().contains('403')) {
        throw RepositoryException.accessDenied('$owner/$name');
      }
      throw RepositoryException('Failed to delete repository', e.toString());
    }
  }

  @override
  Future<List<String>> getRepositoryBranches(
    final String owner,
    final String name,
  ) async {
    final github = await _getGitHubClient();

    try {
      final branches = await github.repositories
          .listBranches(gh.RepositorySlug(owner, name))
          .toList();
      return branches
          .map((final branch) => branch.name ?? '')
          .where((final name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      if (e.toString().contains('404')) {
        throw RepositoryException.notFound('$owner/$name');
      }
      throw RepositoryException(
        'Failed to get repository branches',
        e.toString(),
      );
    }
  }

  @override
  Future<List<String>> getRepositoryTags(
    final String owner,
    final String name,
  ) async {
    final github = await _getGitHubClient();

    try {
      final tags = await github.repositories
          .listTags(gh.RepositorySlug(owner, name))
          .toList();
      return tags
          .map((final tag) => tag.name)
          .where((final name) => name.isNotEmpty)
          .toList();
    } catch (e) {
      if (e.toString().contains('404')) {
        throw RepositoryException.notFound('$owner/$name');
      }
      throw RepositoryException('Failed to get repository tags', e.toString());
    }
  }

  Future<gh.GitHub> _getGitHubClient() async {
    if (_github != null) return _github!;

    final user = await _oauthProvider.getCurrentUser();
    if (user == null) {
      throw const AuthenticationException('Not authenticated with GitHub');
    }

    // Get credentials via a public method
    final isAuthenticated = await _oauthProvider.isAuthenticated();
    if (!isAuthenticated) {
      throw const AuthenticationException('No GitHub credentials found');
    }

    // Use the HTTP client from the OAuth provider
    final httpClient = await _oauthProvider.getHttpClient();
    if (httpClient == null) {
      throw const AuthenticationException(
        'Failed to get authenticated HTTP client',
      );
    }

    _github = gh.GitHub(client: httpClient);
    return _github!;
  }

  RepositoryInfo _convertRepository(final gh.Repository repo) => RepositoryInfo(
    id: repo.id.toString(),
    name: repo.name,
    fullName: repo.fullName,
    owner: RepositoryOwner(
      id: repo.owner?.id.toString() ?? '',
      login: repo.owner?.login ?? '',
      type: _getOwnerType(repo.owner),
      avatarUrl: repo.owner?.avatarUrl,
      htmlUrl: repo.owner?.htmlUrl,
    ),
    description: repo.description,
    isPrivate: repo.isPrivate,
    defaultBranch: repo.defaultBranch,
    cloneUrl: repo.cloneUrl,
    sshUrl: repo.sshUrl,
    htmlUrl: repo.htmlUrl,
    createdAt: repo.createdAt,
    updatedAt: repo.updatedAt,
    permissions: _convertPermissions(repo.permissions),
    language: repo.language,
    starCount: repo.stargazersCount,
    forkCount: repo.forksCount,
    size: repo.size,
  );

  RepositoryOwnerType _getOwnerType(final gh.UserInformation? owner) {
    // Since we can't access the type field directly, we can infer it
    // from other properties or default to user
    return RepositoryOwnerType.user;
  }

  RepositoryPermissions? _convertPermissions(
    final gh.RepositoryPermissions? permissions,
  ) {
    if (permissions == null) return null;

    return RepositoryPermissions(
      admin: permissions.admin,
      push: permissions.push,
      pull: permissions.pull,
    );
  }
}
