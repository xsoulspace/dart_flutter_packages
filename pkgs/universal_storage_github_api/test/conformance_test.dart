import 'package:test/test.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'fake_github_api.dart';

void main() {
  final fakeApi = FakeGitHubApi();

  setUpAll(() async {
    await fakeApi.ready;
  });

  tearDownAll(() async {
    await fakeApi.close();
  });

  storageProviderConformanceTests(
    'GitHubApiStorageProvider (in-process fake API)',
    create: () async {
      final provider = fakeApi.createProvider();
      await provider.initWithConfig(
        GitHubApiConfig(
          authToken: 'fake-token',
          repositoryOwner: const VcRepositoryOwner('conformance'),
          repositoryName: const VcRepositoryName('conformance-repo'),
        ),
      );
      return provider;
    },
    // NOTE: GitHubApiStorageProvider intentionally declares supportsSync=false;
    // its remote operations live on VersionControlService, not StorageProvider.sync.
    supportsSync: false,
  );
}
