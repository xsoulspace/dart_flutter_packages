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
  Future<List<RepositoryInfo>> getOrganizationRepositories(String orgName);

  /// Create a new repository
  Future<RepositoryInfo> createRepository(CreateRepositoryRequest request);

  /// Get repository by name
  Future<RepositoryInfo?> getRepository(String owner, String name);

  /// Search repositories
  Future<List<RepositoryInfo>> searchRepositories(String query, {int? limit});

  /// Delete a repository (if permissions allow)
  Future<void> deleteRepository(String owner, String name);

  /// Get repository branches
  Future<List<String>> getRepositoryBranches(String owner, String name);

  /// Get repository tags
  Future<List<String>> getRepositoryTags(String owner, String name);
}
