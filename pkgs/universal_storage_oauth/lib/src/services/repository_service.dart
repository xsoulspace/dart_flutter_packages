import '../models/models.dart';

/// Request model for creating repositories
class CreateRepositoryRequest {
  /// Creates a new repository request.
  ///
  /// Parameters:
  /// - [name]: The name of the repository.
  /// - [description]: The description of the repository.
  /// - [isPrivate]: Whether the repository is private.
  /// - [organizationName]: The name of the organization.
  const CreateRepositoryRequest({
    required this.name,
    this.description,
    this.isPrivate = false,
    this.organizationName,
    this.autoInit = false,
    this.gitignoreTemplate,
    this.licenseTemplate,
  });

  /// The name of the repository.
  final String name;

  /// The description of the repository.
  final String? description;

  /// Whether the repository is private.
  final bool isPrivate;

  /// The name of the organization.
  final String? organizationName;

  /// Whether to initialize the repository with a README.
  final bool autoInit;

  /// The Gitignore template to use.
  final String? gitignoreTemplate;

  /// The license template to use.
  final String? licenseTemplate;

  /// Converts the repository request to JSON format.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'isPrivate': isPrivate,
    'organizationName': organizationName,
    'autoInit': autoInit,
    'gitignoreTemplate': gitignoreTemplate,
    'licenseTemplate': licenseTemplate,
  };

  @override
  String toString() =>
      'CreateRepositoryRequest(name: $name, private: $isPrivate)';
}

/// Service for managing repositories
abstract class RepositoryService {
  /// Get list of user's repositories
  Future<List<RepositoryInfo>> getUserRepositories();

  /// Get list of organization repositories
  Future<List<RepositoryInfo>> getOrganizationRepositories(
    final String orgName,
  );

  /// Create a new repository
  Future<RepositoryInfo> createRepository(
    final CreateRepositoryRequest request,
  );

  /// Get repository by name
  Future<RepositoryInfo?> getRepository(final String owner, final String name);

  /// Search repositories
  Future<List<RepositoryInfo>> searchRepositories(
    final String query, {
    final int? limit,
  });

  /// Delete a repository (if permissions allow)
  Future<void> deleteRepository(final String owner, final String name);

  /// Get repository branches
  Future<List<String>> getRepositoryBranches(
    final String owner,
    final String name,
  );

  /// Get repository tags
  Future<List<String>> getRepositoryTags(final String owner, final String name);
}
