// ignore_for_file: avoid_print, avoid_catches_without_on_clauses

import 'package:universal_storage_sync/universal_storage_sync.dart';

/// Example demonstrating GitHub API Storage Provider usage.
///
/// This provider operates entirely through GitHub's REST API without
/// maintaining local Git repositories. It's ideal for scenarios where:
/// - No local offline capability is needed
/// - Git CLI is unavailable
/// - You want direct API-based file operations
Future<void> main() async {
  print('=== GitHub API Storage Provider Example ===\n');

  // Initialize the GitHub API storage provider
  final provider = GitHubApiStorageProvider();

  try {
    // Configure the provider with GitHub API settings
    final config = GitHubApiConfig(
      authToken: 'your_github_personal_access_token_here',
      repositoryOwner: const VcRepositoryOwner('your-username'),
      repositoryName: const VcRepositoryName('your-repository-name'),
    );

    await provider.initWithConfig(config);

    print('✅ GitHub API provider initialized successfully');

    // Check authentication status
    final isAuthenticated = await provider.isAuthenticated();
    print('🔐 Authentication status: ${isAuthenticated ? 'Valid' : 'Invalid'}');

    if (!isAuthenticated) {
      print(
        '❌ Authentication failed. Please check your token and permissions.',
      );
      return;
    }

    // Example 1: Create a new file
    print('\n📝 Creating a new file...');
    try {
      final result = await provider.createFile(
        'example.txt',
        'Hello from GitHub API Storage Provider!',
        commitMessage: 'Add example file via API',
      );
      print('✅ File created successfully. Commit SHA: ${result.revisionId}');
    } on FileAlreadyExistsException catch (e) {
      print('⚠️  File already exists: ${e.message}');
    }

    // Example 2: Read file content
    print('\n📖 Reading file content...');
    final content = await provider.getFile('example.txt');
    if (content != null) {
      print('✅ File content: $content');
    } else {
      print('❌ File not found');
    }

    // Example 3: Update file content
    print('\n✏️  Updating file content...');
    try {
      final updateResult = await provider.updateFile(
        'example.txt',
        'Updated content from GitHub API Storage Provider!',
        commitMessage: 'Update example file via API',
      );
      print(
        '✅ File updated successfully. Commit SHA: ${updateResult.revisionId}',
      );
    } on FileNotFoundException catch (e) {
      print('❌ File not found for update: ${e.message}');
    }

    // Example 4: List files in repository root
    print('\n📂 Listing files in repository root...');
    try {
      final entries = await provider.listDirectory('');
      print('✅ Files found: ${entries.length}');
      for (final file in entries.take(5)) {
        print('  - ${file.name}${file.isDirectory ? '/' : ''}');
      }
      if (entries.length > 5) {
        print('  ... and ${entries.length - 5} more files');
      }
    } catch (e) {
      print('❌ Error listing files: $e');
    }

    // Example 5: Create a file in a subdirectory
    print('\n📁 Creating file in subdirectory...');
    try {
      await provider.createFile(
        'docs/api-guide.md',
        '# API Guide\n\nThis file was created using '
            'the GitHub API Storage Provider.',
        commitMessage: 'Add API guide documentation',
      );
      print('✅ File created in subdirectory successfully');
    } on FileAlreadyExistsException catch (e) {
      print('⚠️  File already exists: ${e.message}');
    }

    // Example 6: Restore file from a specific commit (requires commit SHA)
    print('\n🔄 Restore functionality...');
    print('ℹ️  To restore a file, you need a specific commit SHA.');
    print(
      "   Example: await provider.restore('example.txt', "
      "versionId: 'commit-sha-here');",
    );

    // Example 7: Delete a file
    print('\n🗑️  Deleting a file...');
    try {
      await provider.deleteFile(
        'example.txt',
        commitMessage: 'Remove example file via API',
      );
      print('✅ File deleted successfully');
    } on FileNotFoundException catch (e) {
      print('❌ File not found for deletion: ${e.message}');
    }

    print('\n✅ GitHub API Storage Provider example completed successfully!');
  } on ConfigurationException catch (e) {
    print('❌ Configuration error: ${e.message}');
    print(
      '💡 Make sure to provide valid authToken, '
      'repositoryOwner, and repositoryName',
    );
  } on AuthenticationFailedException catch (e) {
    print('❌ Authentication failed: ${e.message}');
    print('💡 Check your GitHub token permissions and repository access');
  } on RemoteNotFoundException catch (e) {
    print('❌ Repository not found: ${e.message}');
    print('💡 Verify the repository owner and name are correct');
  } on GitHubRateLimitException catch (e) {
    print('❌ Rate limit exceeded: ${e.message}');
    print(
      '💡 Wait before making more requests or use a token with higher limits',
    );
  } on GitHubApiException catch (e) {
    print('❌ GitHub API error: ${e.message}');
  } on NetworkException catch (e) {
    print('❌ Network error: ${e.message}');
    print('💡 Check your internet connection');
  } catch (e) {
    print('❌ Unexpected error: $e');
  }
}

/// Example of using GitHub API Storage Provider with StorageService
Future<void> storageServiceExample() async {
  print('\n=== GitHub API with StorageService Example ===\n');

  final service = StorageService(GitHubApiStorageProvider());

  try {
    final config = GitHubApiConfig(
      authToken: 'your_github_personal_access_token_here',
      repositoryOwner: const VcRepositoryOwner('your-username'),
      repositoryName: const VcRepositoryName('your-repository-name'),
    );

    await service.initializeWithConfig(config);

    // Use StorageService methods
    await service.saveFile('service-example.txt', 'Hello from StorageService!');
    final content = await service.readFile('service-example.txt');
    print('Content via StorageService: $content');

    // Note: GitHub API provider doesn't support sync operations
    // service.syncRemote() will print a message about not supporting sync
  } catch (e) {
    print('Error: $e');
  }
}

/// Configuration tips for GitHub API Storage Provider
void configurationTips() {
  print('\n=== Configuration Tips ===\n');

  print('🔑 GitHub Personal Access Token:');
  print(
    '   1. Go to GitHub Settings > Developer settings > Personal access tokens',
  );
  print('   2. Generate a new token with appropriate permissions:');
  print('      - repo (for private repositories)');
  print('      - public_repo (for public repositories)');
  print('   3. Copy the token and use it as authToken');

  print('\n📁 Repository Configuration:');
  print('   - repositoryOwner: Your GitHub username or organization name');
  print('   - repositoryName: The name of your repository');
  print('   - branchName: Target branch (optional, defaults to "main")');

  print('\n⚡ Performance Considerations:');
  print('   - Each operation makes HTTP requests to GitHub API');
  print('   - Rate limits apply (5000 requests/hour for authenticated users)');
  print(
    '   - No local caching - consider OfflineGitStorageProvider '
    'for offline support',
  );

  print('\n🔒 Security Best Practices:');
  print('   - Never commit tokens to version control');
  print('   - Use environment variables or secure configuration');
  print('   - Regularly rotate access tokens');
  print('   - Use minimal required permissions');
}
