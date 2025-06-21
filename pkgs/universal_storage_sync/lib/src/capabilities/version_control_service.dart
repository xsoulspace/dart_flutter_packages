import '../models/models.dart';

/// Generic service interface for version-control repository operations.
///
/// Implementations should adapt a concrete SDK (e.g. GitHub, GitLab, Bitbucket)
/// to this provider-agnostic contract so that upper-level orchestration code
/// (such as [RepositoryManager]) can work with any backend.
///
/// Uses provider-agnostic models:
/// * [VcRepository] – repository information
/// * [VcBranch] – branch information
/// * [VcCreateRepositoryRequest] – repository creation parameters
abstract interface class VersionControlService {
  /// List repositories available to the current authenticated user.
  Future<List<VcRepository>> listRepositories();

  /// Create a new repository with the provided [details].
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  );

  /// Get metadata about the currently-configured repository (if any).
  Future<VcRepository> getRepositoryInfo();

  /// List branches that exist in the currently-configured repository.
  Future<List<VcBranch>> listBranches();

  /// Set the current repository context by ID or full name.
  Future<void> setRepository(final VcRepositoryName repositoryId);

  /// Clone a repository to a local path.
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  );
}
