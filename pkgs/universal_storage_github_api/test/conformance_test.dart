import 'package:test/test.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  storageProviderConformanceTests(
    'GitHubApiStorageProvider',
    create: () async {
      final provider = GitHubApiStorageProvider();
      await provider.initWithConfig(
        GitHubApiConfig(
          authToken: 'conformance-not-a-real-token',
          repositoryOwner: const VcRepositoryOwner('conformance'),
          repositoryName: const VcRepositoryName('conformance-repo'),
        ),
      );
      return provider;
    },
    supportsSync: true,
  );
}
