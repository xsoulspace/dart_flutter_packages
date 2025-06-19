// ignore_for_file: avoid_print

import 'dart:io';

import 'package:universal_storage_sync/universal_storage_sync.dart';

/// Example demonstrating remote Git synchronization capabilities
/// of the OfflineGitStorageProvider (Stage 3 features).
Future<void> main() async {
  print('=== Universal Storage Sync - Remote Git Sync Example ===\n');

  // Create a temporary directory for this example
  final tempDir = await Directory.systemTemp.createTemp('remote_sync_example_');
  final localPath = tempDir.path;

  try {
    await demonstrateRemoteSync(localPath);
  } finally {
    // Clean up
    await tempDir.delete(recursive: true);
    print('Cleaned up temporary directory: $localPath');
  }
}

Future<void> demonstrateRemoteSync(final String localPath) async {
  print('1. Creating OfflineGitStorageProvider with remote configuration...');

  // Configure with remote repository
  final config = OfflineGitConfig(
    localPath: localPath,
    branchName: 'main',
    authorName: 'Example User',
    authorEmail: 'user@example.com',
    // Remote configuration (commented out for example - would need real repo)
    // remoteUrl: 'https://github.com/username/repo.git',
    // remoteName: 'origin',
    // remoteType: 'github',
    // Authentication (commented out for example)
    // httpsToken: 'github_pat_your_token_here',
    // sshKeyPath: '/path/to/your/ssh/key',
    // Sync strategies
    defaultPullStrategy: 'rebase',
  );

  final provider = OfflineGitStorageProvider();
  await provider.initWithConfig(config);

  print('✓ Provider initialized successfully');
  print('  - Local path: $localPath');
  print('  - Branch: main');
  print('  - Conflict resolution: clientAlwaysRight');
  print('  - Pull strategy: rebase');
  print('  - Push strategy: rebase-local');

  // Check sync support
  print('\n2. Checking sync support...');
  print('  - Supports sync: ${provider.supportsSync}');
  if (!provider.supportsSync) {
    print('  - Note: No remote URL configured, so sync is not supported');
  }

  print('\n3. Creating some local files...');

  // Create some files
  await provider.createFile(
    'README.md',
    '# Remote Sync Example\n\nThis is a test repository for demonstrating remote sync.',
    commitMessage: 'Add README',
  );

  await provider.createFile(
    'config.json',
    '{\n  "version": "1.0.0",\n  "features": ["local", "remote"]\n}',
    commitMessage: 'Add configuration file',
  );

  await provider.createFile(
    'docs/getting-started.md',
    '# Getting Started\n\n1. Clone the repository\n2. Configure your settings\n3. Start syncing!',
    commitMessage: 'Add getting started guide',
  );

  print('✓ Created 3 files with Git commits');

  // List files
  print('\n4. Listing files in repository...');
  final files = await provider.listFiles('.');
  for (final file in files) {
    print('  - $file');
  }

  print('\n5. Demonstrating sync behavior...');

  // Try to sync (will fail gracefully since no remote is configured)
  try {
    await provider.sync();
    print('✓ Sync completed successfully');
  } catch (e) {
    if (e is AuthenticationException) {
      print('ℹ Sync not performed: No remote URL configured');
      print('  This is expected behavior for local-only repositories');
    } else {
      print('✗ Sync failed: $e');
    }
  }

  print('\n6. Using StorageService for graceful sync handling...');

  final storageService = StorageService(provider);
  await storageService.initializeWithConfig(config);

  // StorageService handles non-sync providers gracefully
  await storageService.syncRemote();
  print('✓ StorageService.syncRemote() completed gracefully');
  print("  (No operation performed since provider doesn't support sync)");

  print('\n7. Demonstrating conflict resolution configuration...');

  // Show different conflict resolution strategies
  const strategies = ConflictResolutionStrategy.values;
  print('Available conflict resolution strategies:');
  for (final strategy in strategies) {
    print('  - ${strategy.name}');
  }

  print('\n8. Example with remote URL (configuration only)...');

  // Example configuration with remote URL (for demonstration)
  final remoteConfig = OfflineGitConfig(
    localPath: localPath,
    branchName: 'main',
    authorName: 'Example User',
    authorEmail: 'user@example.com',
    // This would enable sync support
    remoteUrl: 'https://github.com/example/repo.git',
    defaultPushStrategy: 'force-with-lease',
    conflictResolution: ConflictResolutionStrategy.serverAlwaysRight,
    httpsToken: 'your_github_token_here',
  );

  print('Configuration with remote URL:');
  print('  - Remote URL: ${remoteConfig.remoteUrl}');
  print('  - Remote name: ${remoteConfig.remoteName}');
  print('  - Pull strategy: ${remoteConfig.defaultPullStrategy}');
  print('  - Push strategy: ${remoteConfig.defaultPushStrategy}');
  print('  - Conflict resolution: ${remoteConfig.conflictResolution.name}');
  print('  - Authentication: HTTPS token configured');

  // Create a new provider with remote config to show sync support
  final remoteProvider = OfflineGitStorageProvider();
  await remoteProvider.initWithConfig(remoteConfig);
  print('  - Supports sync: ${remoteProvider.supportsSync}');

  print('\n=== Remote Sync Example Complete ===');
  print('\nKey takeaways:');
  print(
    '• OfflineGitStorageProvider supports both local-only and remote sync modes',
  );
  print(
    '• Sync support is automatically detected based on remote URL configuration',
  );
  print('• StorageService gracefully handles providers without sync support');
  print('• Multiple conflict resolution strategies are available');
  print('• Authentication supports both SSH keys and HTTPS tokens');
  print('• "Client is always right" philosophy with configurable strategies');
}
