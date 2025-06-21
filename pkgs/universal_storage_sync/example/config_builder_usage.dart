// ignore_for_file: avoid_print, avoid_catches_without_on_clauses

import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  print('=== Universal Storage Sync - Config Builder Usage Examples ===\n');

  // Example 1: FileSystem Configuration Builder
  print('1. FileSystem Configuration:');
  final fileSystemConfig = FileSystemConfig(
    basePath: '/path/to/app/data',
    databaseName: 'app_database', // For web platforms
  );

  print('   BasePath: ${fileSystemConfig.basePath}');
  print('   DatabaseName: ${fileSystemConfig.databaseName}\n');

  // Example 2: GitHub API Configuration
  print('2. GitHub API Configuration:');
  final githubConfig = GitHubApiConfig(
    authToken: 'ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    repositoryOwner: const VcRepositoryOwner('your-username'),
    repositoryName: const VcRepositoryName('your-repository'),
  );

  print(
    '   Repository: ${githubConfig.repositoryOwner}/${githubConfig.repositoryName}',
  );
  print('   Branch: ${githubConfig.branchName}');
  print('   Has Token: ${githubConfig.authToken.isNotEmpty}\n');

  // Example 3: Offline Git Configuration (Basic)
  print('3. Offline Git Configuration (Basic):');
  final basicGitConfig = OfflineGitConfig(
    localPath: '/path/to/git/repository',
    branchName: VcBranchName.main,
    authorName: 'John Doe',
    authorEmail: 'john.doe@example.com',
  );

  print('   Local Path: ${basicGitConfig.localPath}');
  print('   Branch: ${basicGitConfig.branchName}');
  print(
    '   Author: ${basicGitConfig.authorName} <${basicGitConfig.authorEmail}>\n',
  );

  // Example 4: Offline Git Configuration (Advanced with Remote)
  print('4. Offline Git Configuration (Advanced):');
  final advancedGitConfig = OfflineGitConfig(
    localPath: '/path/to/advanced/git/repository',
    branchName: VcBranchName.develop,
    authorName: 'Jane Smith',
    authorEmail: 'jane.smith@company.com',
    remoteUrl: const VcUrl('https://github.com/company/project.git'),
    remoteName: 'upstream',
    remoteType: 'github',
    defaultPullStrategy: 'rebase',
    defaultPushStrategy: 'force-with-lease',
    conflictResolution: ConflictResolutionStrategy.lastWriteWins,
  );

  print('   Local Path: ${advancedGitConfig.localPath}');
  print(
    '   Remote: ${advancedGitConfig.remoteName} -> '
    '${advancedGitConfig.remoteUrl}',
  );
  print('   Pull Strategy: ${advancedGitConfig.defaultPullStrategy}');
  print('   Push Strategy: ${advancedGitConfig.defaultPushStrategy}');
  print('   Conflict Resolution: ${advancedGitConfig.conflictResolution}\n');

  // Example 5: Offline Git Configuration with SSH Authentication
  print('5. Offline Git Configuration with SSH Authentication:');
  final sshGitConfig = OfflineGitConfig(
    localPath: '/path/to/ssh/git/repository',
    branchName: VcBranchName.main,
    authorName: 'Dev User',
    authorEmail: 'dev@company.com',
    remoteUrl: const VcUrl('git@github.com:company/secure-project.git'),
    sshKeyPath: '/home/user/.ssh/id_rsa',
  );

  print('   Local Path: ${sshGitConfig.localPath}');
  print('   Remote URL: ${sshGitConfig.remoteUrl}');
  print('   SSH Key: ${sshGitConfig.sshKeyPath}\n');

  // Example 6: Offline Git Configuration with HTTPS Token Authentication
  print('6. Offline Git Configuration with HTTPS Token:');
  final httpsGitConfig = OfflineGitConfig(
    localPath: '/path/to/https/git/repository',
    branchName: VcBranchName.main,
    authorName: 'API User',
    authorEmail: 'api@company.com',
    remoteUrl: const VcUrl('https://github.com/company/api-project.git'),
    httpsToken: 'ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  );

  print('   Remote URL: ${httpsGitConfig.remoteUrl}');
  print('   Has HTTPS Token: ${httpsGitConfig.httpsToken != null}\n');

  // Example 7: Error Handling with Direct Constructors
  print('7. Constructor Validation (Error Handling):');
  try {
    // This will throw because required fields are missing
    GitHubApiConfig(
      authToken: '',
      repositoryOwner: const VcRepositoryOwner(''),
      repositoryName: const VcRepositoryName('test-repo'),
    );
  } catch (e) {
    print('   Expected error: $e');
  }

  try {
    // This will throw because of empty values
    FileSystemConfig(
      basePath: '', // Empty path not allowed
    );
  } catch (e) {
    print('   Expected error: $e');
  }

  print('\n=== All examples completed successfully! ===');
}
