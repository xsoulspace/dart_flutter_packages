import '../models/models.dart';

/// Request model for creating repositories
class CreateRepositoryRequest {
  const CreateRepositoryRequest({
    required this.name,
    this.description,
    this.isPrivate = false,
    this.organizationName,
    this.autoInit = false,
    this.gitignoreTemplate,
    this.licenseTemplate,
  });

  final String name;
  final String? description;
  final bool isPrivate;
  final String? organizationName;
  final bool autoInit;
  final String? gitignoreTemplate;
  final String? licenseTemplate;

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
