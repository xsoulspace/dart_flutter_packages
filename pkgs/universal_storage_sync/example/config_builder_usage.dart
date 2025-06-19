import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() async {
  print('=== Universal Storage Sync - Config Builder Usage Examples ===\n');

  // Example 1: FileSystem Config Builder
  print('1. FileSystem Configuration Builder:');
  final fileSystemConfig = FileSystemConfig.builder()
      .basePath('/path/to/app/data')
      .databaseName('app_database') // For web platforms
      .build();

  print('   BasePath: ${fileSystemConfig.basePath}');
  print('   DatabaseName: ${fileSystemConfig.databaseName}\n');

  // Example 2: GitHub API Config Builder
  print('2. GitHub API Configuration Builder:');
  final githubConfig = GitHubApiConfig.builder()
      .authToken('ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
      .repositoryOwner('your-username')
      .repositoryName('your-repository')
      .branchName('main')
      .build();

  print(
    '   Repository: ${githubConfig.repositoryOwner}/${githubConfig.repositoryName}',
  );
  print('   Branch: ${githubConfig.branchName}');
  print('   Has Token: ${githubConfig.authToken.isNotEmpty}\n');

  // Example 3: Offline Git Config Builder (Basic)
  print('3. Offline Git Configuration Builder (Basic):');
  final basicGitConfig = OfflineGitConfig.builder()
      .localPath('/path/to/git/repository')
      .branchName('main')
      .authorName('John Doe')
      .authorEmail('john.doe@example.com')
      .build();

  print('   Local Path: ${basicGitConfig.localPath}');
  print('   Branch: ${basicGitConfig.branchName}');
  print(
    '   Author: ${basicGitConfig.authorName} <${basicGitConfig.authorEmail}>\n',
  );

  // Example 4: Offline Git Config Builder (Advanced with Remote)
  print('4. Offline Git Configuration Builder (Advanced):');
  final advancedGitConfig = OfflineGitConfig.builder()
      .localPath('/path/to/advanced/git/repository')
      .branchName('develop')
      .authorName('Jane Smith')
      .authorEmail('jane.smith@company.com')
      .remoteUrl('https://github.com/company/project.git')
      .remoteName('upstream')
      .remoteType('github')
      .defaultPullStrategy('rebase')
      .defaultPushStrategy('force-with-lease')
      .conflictResolution(ConflictResolutionStrategy.lastWriteWins)
      .build();

  print('   Local Path: ${advancedGitConfig.localPath}');
  print(
    '   Remote: ${advancedGitConfig.remoteName} -> ${advancedGitConfig.remoteUrl}',
  );
  print('   Pull Strategy: ${advancedGitConfig.defaultPullStrategy}');
  print('   Push Strategy: ${advancedGitConfig.defaultPushStrategy}');
  print('   Conflict Resolution: ${advancedGitConfig.conflictResolution}\n');

  // Example 5: Offline Git Config with SSH Authentication
  print('5. Offline Git Configuration with SSH Authentication:');
  final sshGitConfig = OfflineGitConfig.builder()
      .localPath('/path/to/ssh/git/repository')
      .branchName('main')
      .authorName('Dev User')
      .authorEmail('dev@company.com')
      .remoteUrl('git@github.com:company/secure-project.git')
      .authentication()
      .sshKey('/home/user/.ssh/id_rsa')
      .build();

  print('   Local Path: ${sshGitConfig.localPath}');
  print('   Remote URL: ${sshGitConfig.remoteUrl}');
  print('   SSH Key: ${sshGitConfig.sshKeyPath}\n');

  // Example 6: Offline Git Config with HTTPS Token Authentication
  print('6. Offline Git Configuration with HTTPS Token:');
  final httpsGitConfig = OfflineGitConfig.builder()
      .localPath('/path/to/https/git/repository')
      .branchName('main')
      .authorName('API User')
      .authorEmail('api@company.com')
      .remoteUrl('https://github.com/company/api-project.git')
      .authentication()
      .httpsToken('ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')
      .build();

  print('   Local Path: ${httpsGitConfig.localPath}');
  print('   Remote URL: ${httpsGitConfig.remoteUrl}');
  print('   Has HTTPS Token: ${httpsGitConfig.httpsToken != null}\n');

  // Example 7: Error Handling with Builders
  print('7. Builder Validation (Error Handling):');
  try {
    // This will throw because required fields are missing
    GitHubApiConfig.builder()
        .repositoryName('test-repo')
        // Missing authToken and repositoryOwner
        .build();
  } catch (e) {
    print('   Expected error: $e');
  }

  try {
    // This will throw because of empty values
    FileSystemConfig.builder()
        .basePath('') // Empty path not allowed
        .build();
  } catch (e) {
    print('   Expected error: $e');
  }

  print('\n=== All examples completed successfully! ===');
}
