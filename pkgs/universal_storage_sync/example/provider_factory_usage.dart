// ignore_for_file: avoid_print

import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() async {
  print('=== Universal Storage Sync - Storage Factory Usage Examples ===\n');

  try {
    // Example 1: Auto-detect provider from config type
    print('1. Auto-detect Provider from Configuration:');

    final fileConfig = FileSystemConfig(basePath: '/tmp/demo');

    final service1 = await StorageFactory.create(fileConfig);
    print('   Created FileSystem service automatically');

    final gitHubConfig = GitHubApiConfig(
      authToken: 'demo_token',
      repositoryOwner: 'demo-user',
      repositoryName: 'demo-repo',
    );

    final service2 = await StorageFactory.create(gitHubConfig);
    print('   Created GitHub API service automatically\n');

    // Example 2: Specific factory methods
    print('2. Specific Factory Methods:');

    final fsConfig = FileSystemConfig(basePath: '/path/to/data');
    final fsService = await StorageFactory.createFileSystem(fsConfig);
    print('   Created FileSystem service with specific method');

    final ghConfig = GitHubApiConfig(
      authToken: 'ghp_demo_token_123',
      repositoryOwner: 'myorg',
      repositoryName: 'myproject',
    );
    final ghService = await StorageFactory.createGitHubApi(ghConfig);
    print('   Created GitHub service with specific method');

    final gitConfig = OfflineGitConfig(
      localPath: '/path/to/repo',
      branchName: 'main',
      authorName: 'Demo User',
      authorEmail: 'demo@example.com',
    );
    final gitService = await StorageFactory.createOfflineGit(gitConfig);
    print('   Created Offline Git service with specific method\n');

    // Example 3: Using provider selector to choose optimal config
    print('3. Using Provider Selector:');

    const requirements = ProviderRequirements(
      needsVersionControl: true,
      needsOffline: true,
      hasGitCli: true,
    );

    final recommendation = ProviderSelector.recommend(requirements);
    print('   Recommended: ${recommendation.providerType}');
    print('   Score: ${recommendation.score}/100');
    print('   Reason: ${recommendation.reason}');

    // Create service using recommended config template
    final recommendedService = await StorageFactory.create(
      recommendation.configTemplate,
    );
    print('   Service created using recommendation\n');

    // Example 4: Use case-based selection
    print('4. Use Case-based Provider Selection:');

    final simpleReq = ProviderSelector.fromUseCase('simple local storage');
    final simpleRec = ProviderSelector.recommend(simpleReq);
    print(
      '   For "simple local storage": ${simpleRec.providerType} (score: ${simpleRec.score})',
    );

    final collabReq = ProviderSelector.fromUseCase(
      'team collaboration project',
    );
    final collabRec = ProviderSelector.recommend(collabReq);
    print(
      '   For "team collaboration": ${collabRec.providerType} (score: ${collabRec.score})',
    );

    final versionReq = ProviderSelector.fromUseCase(
      'version control and backup',
    );
    final versionRec = ProviderSelector.recommend(versionReq);
    print(
      '   For "version control": ${versionRec.providerType} (score: ${versionRec.score})\n',
    );

    // Example 5: Compare all provider options
    print('5. All Provider Recommendations:');
    const webReq = ProviderRequirements(
      isWeb: true,
      needsRemoteSync: true,
      needsVersionControl: true,
    );

    final allRecommendations = ProviderSelector.getAllRecommendations(webReq);
    for (var i = 0; i < allRecommendations.length; i++) {
      final rec = allRecommendations[i];
      print(
        '   ${i + 1}. ${rec.providerType} (${rec.score}/100): ${rec.reason}',
      );
    }
    print('');

    // Example 6: Path normalization utility
    print('6. Path Normalization Examples:');
    const testPath = r'folder\subfolder//file.txt';
    print('   Original path: $testPath');
    print(
      '   FileSystem: ${PathNormalizer.normalize(testPath, ProviderType.filesystem)}',
    );
    print(
      '   GitHub: ${PathNormalizer.normalize(testPath, ProviderType.github)}',
    );
    print('   Git: ${PathNormalizer.normalize(testPath, ProviderType.git)}');

    final segments = ['docs', 'api', 'readme.md'];
    print(
      '   Joined for GitHub: ${PathNormalizer.join(segments, ProviderType.github)}',
    );
    print(
      '   Path validation (GitHub): ${PathNormalizer.isSafePath('docs/api/readme.md', ProviderType.github)}\n',
    );

    // Example 7: Basic operations with factory-created service
    print('7. Basic Operations with Factory-Created Service:');
    // Note: This would require actual provider implementation
    // Here we just show the API usage pattern

    print('   // Example service operations:');
    print('   // await service.saveFile("test.txt", "Hello, World!");');
    print('   // final content = await service.readFile("test.txt");');
    print('   // await service.syncRemote();');
    print('   Service ready for operations\n');
  } catch (e) {
    print('Error: $e');
  }

  print('=== Factory usage examples completed! ===');
}
