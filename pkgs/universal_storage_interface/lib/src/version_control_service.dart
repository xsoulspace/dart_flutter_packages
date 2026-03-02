import 'models/version_control_models.dart';

abstract interface class VersionControlService {
  VersionControlCapabilities get declaredVersionControlCapabilities;

  Future<VersionControlCapabilities> resolveVersionControlCapabilities();

  Future<List<VcRepository>> listRepositories();
  Future<VcRepository> createRepository(
    final VcCreateRepositoryRequest details,
  );
  Future<VcRepository> getRepositoryInfo();
  Future<List<VcBranch>> listBranches();
  Future<void> setRepository(final VcRepositoryName repositoryId);
  Future<void> cloneRepository(
    final VcRepository repository,
    final String localPath,
  );
}
