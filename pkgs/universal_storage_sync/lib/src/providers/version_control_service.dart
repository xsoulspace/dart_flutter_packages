/// Generic service interface for version-control repository operations.
///
/// Implementations should adapt a concrete SDK (e.g. GitHub, GitLab, Bitbucket)
/// to this provider-agnostic contract so that upper-level orchestration code
/// (such as [RepositoryManager]) can work with any backend.
///
/// The generic parameters allow strong typing without forcing callers to depend
/// on a specific SDK:
/// * [R] – concrete repository model
/// * [B] – concrete branch model
/// * [C] – concrete request model used when creating a repository
abstract interface class VersionControlService<R, B, C> {
  /// List repositories available to the current authenticated user.
  Future<List<R>> listRepositories();

  /// Create a new repository with the provided [details].
  Future<R> createRepository(final C details);

  /// Get metadata about the currently-configured repository (if any).
  Future<R> getRepositoryInfo();

  /// List branches that exist in the currently-configured repository.
  Future<List<B>> listBranches();
}
