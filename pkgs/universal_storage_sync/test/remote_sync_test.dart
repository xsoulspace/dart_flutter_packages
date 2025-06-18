import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  group('OfflineGitStorageProvider Remote Sync', () {
    late OfflineGitStorageProvider provider;
    late String tempDir;

    setUp(() async {
      // Create a temporary directory for testing
      final tempDirectory = await Directory.systemTemp.createTemp(
        'git_remote_test_',
      );
      tempDir = tempDirectory.path;
      provider = OfflineGitStorageProvider();
    });

    tearDown(() async {
      // Clean up temporary directory
      final directory = Directory(tempDir);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    group('Remote Setup & Configuration', () {
      test('should throw exception when sync without remote URL', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'authorName': 'Test User',
          'authorEmail': 'test@example.com',
        });

        expect(
          () => provider.sync(),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('should handle invalid remote URL gracefully', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'authorName': 'Test User',
          'authorEmail': 'test@example.com',
          'remoteUrl': 'https://invalid-url-that-does-not-exist.com/repo.git',
        });

        expect(
          () => provider.sync(),
          throwsA(isA<NetworkException>()),
        );
      });

      test('should configure remote settings from config', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'authorName': 'Test User',
          'authorEmail': 'test@example.com',
          'remoteUrl': 'https://github.com/test/repo.git',
          'remoteName': 'upstream',
          'remoteType': 'github',
          'defaultPullStrategy': 'rebase',
          'defaultPushStrategy': 'force-with-lease',
          'conflictResolution': 'serverAlwaysRight',
        });

        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Conflict Resolution Strategies', () {
      test('should parse conflict resolution strategy from config', () async {
        // Test clientAlwaysRight (default)
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'conflictResolution': 'clientAlwaysRight',
        });
        expect(await provider.isAuthenticated(), isTrue);

        // Test serverAlwaysRight
        final provider2 = OfflineGitStorageProvider();
        final tempDir2 =
            (await Directory.systemTemp.createTemp('git_test_')).path;
        await provider2.init({
          'localPath': tempDir2,
          'branchName': 'main',
          'conflictResolution': 'serverAlwaysRight',
        });
        expect(await provider2.isAuthenticated(), isTrue);

        // Clean up
        await Directory(tempDir2).delete(recursive: true);
      });

      test('should default to clientAlwaysRight for invalid strategy',
          () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'conflictResolution': 'invalidStrategy',
        });
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Sync Strategies', () {
      test('should configure pull and push strategies', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'defaultPullStrategy': 'ff-only',
          'defaultPushStrategy': 'fail-on-conflict',
        });
        expect(await provider.isAuthenticated(), isTrue);
      });

      test('should use default strategies when not specified', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
        });
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Authentication Configuration', () {
      test('should configure SSH key path', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'sshKeyPath': '/path/to/ssh/key',
        });
        expect(await provider.isAuthenticated(), isTrue);
      });

      test('should configure HTTPS token', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'httpsToken': 'github_pat_test_token',
        });
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Error Handling', () {
      test('should handle network timeout gracefully', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'remoteUrl': 'https://httpstat.us/408', // Returns timeout
        });

        expect(
          () => provider.sync(),
          throwsA(isA<NetworkException>()),
        );
      });

      test('should handle authentication failure', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          'remoteUrl': 'https://github.com/private/repo.git', // Requires auth
        });

        expect(
          () => provider.sync(),
          throwsA(isA<NetworkException>()),
        );
      });
    });

    group('Integration with StorageService', () {
      late StorageService storageService;

      setUp(() async {
        storageService = StorageService(provider);
      });

      test('should sync through StorageService', () async {
        await storageService.initialize({
          'localPath': tempDir,
          'branchName': 'main',
          'authorName': 'Test User',
          'authorEmail': 'test@example.com',
        });

        // Should not throw for provider without remote URL
        // (StorageService handles this gracefully)
        await storageService.syncRemote();
      });

      test('should pass sync strategies to provider', () async {
        await storageService.initialize({
          'localPath': tempDir,
          'branchName': 'main',
          'remoteUrl': 'https://invalid-url.com/repo.git',
        });

        expect(
          () => storageService.syncRemote(
            pullMergeStrategy: 'rebase',
            pushConflictStrategy: 'force-with-lease',
          ),
          throwsA(isA<NetworkException>()),
        );
      });
    });

    group('Configuration Validation', () {
      test('should validate required configuration parameters', () async {
        // Missing localPath
        expect(
          () => provider.init({
            'branchName': 'main',
          }),
          throwsA(isA<AuthenticationException>()),
        );

        // Missing branchName
        expect(
          () => provider.init({
            'localPath': tempDir,
          }),
          throwsA(isA<AuthenticationException>()),
        );

        // Empty localPath
        expect(
          () => provider.init({
            'localPath': '',
            'branchName': 'main',
          }),
          throwsA(isA<AuthenticationException>()),
        );

        // Empty branchName
        expect(
          () => provider.init({
            'localPath': tempDir,
            'branchName': '',
          }),
          throwsA(isA<AuthenticationException>()),
        );
      });

      test('should handle optional configuration parameters', () async {
        await provider.init({
          'localPath': tempDir,
          'branchName': 'main',
          // All optional parameters
          'authorName': null,
          'authorEmail': null,
          'remoteUrl': null,
          'remoteName': null,
          'remoteType': null,
          'remoteApiSettings': null,
          'sshKeyPath': null,
          'httpsToken': null,
        });

        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('OfflineGitConfig Integration', () {
      test('should work with OfflineGitConfig', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          branchName: 'main',
          authorName: 'Test User',
          authorEmail: 'test@example.com',
          remoteUrl: 'https://github.com/test/repo.git',
          remoteName: 'upstream',
          remoteType: 'github',
          defaultPullStrategy: 'rebase',
          defaultPushStrategy: 'force-with-lease',
          conflictResolution: ConflictResolutionStrategy.serverAlwaysRight,
          sshKeyPath: '/path/to/key',
          httpsToken: 'token123',
        );

        await provider.init(config.toMap());
        expect(await provider.isAuthenticated(), isTrue);
      });

      test('should handle minimal OfflineGitConfig', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          branchName: 'main',
        );

        await provider.init(config.toMap());
        expect(await provider.isAuthenticated(), isTrue);
      });
    });
  });

  group('ConflictResolutionStrategy', () {
    test('should have all expected values', () {
      expect(ConflictResolutionStrategy.values, hasLength(4));
      expect(
        ConflictResolutionStrategy.values,
        contains(ConflictResolutionStrategy.clientAlwaysRight),
      );
      expect(
        ConflictResolutionStrategy.values,
        contains(ConflictResolutionStrategy.serverAlwaysRight),
      );
      expect(
        ConflictResolutionStrategy.values,
        contains(ConflictResolutionStrategy.manualResolution),
      );
      expect(
        ConflictResolutionStrategy.values,
        contains(ConflictResolutionStrategy.lastWriteWins),
      );
    });

    test('should have correct names', () {
      expect(
        ConflictResolutionStrategy.clientAlwaysRight.name,
        equals('clientAlwaysRight'),
      );
      expect(
        ConflictResolutionStrategy.serverAlwaysRight.name,
        equals('serverAlwaysRight'),
      );
      expect(
        ConflictResolutionStrategy.manualResolution.name,
        equals('manualResolution'),
      );
      expect(
        ConflictResolutionStrategy.lastWriteWins.name,
        equals('lastWriteWins'),
      );
    });
  });
}
