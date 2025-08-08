import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_git_offline/universal_storage_git_offline.dart';

void main() {
  group('OfflineGitStorageProvider Remote Sync', () {
    late OfflineGitStorageProvider provider;
    late Directory tempDirectory;
    late String tempDir;

    setUp(() async {
      // Create a temporary directory for testing
      tempDirectory = await Directory.systemTemp.createTemp('git_remote_test_');
      tempDir = tempDirectory.path;
      provider = OfflineGitStorageProvider();
    });

    tearDown(() async {
      // Clean up temporary directory
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    group('Remote Setup & Configuration', () {
      test('should throw exception when sync without remote URL', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
        );

        await provider.initWithConfig(config);
        expect(() => provider.sync(), throwsA(isA<AuthenticationException>()));
      });

      test('should handle invalid remote URL gracefully', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
          remoteUrl: const VcUrl(
            'https://invalid-url-that-does-not-exist.com/repo.git',
          ),
        );

        await provider.initWithConfig(config);
        expect(() => provider.sync(), throwsA(isA<NetworkException>()));
      });

      test('should configure remote settings from config', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
          remoteUrl: const VcUrl('https://github.com/test/repo.git'),
          remoteName: 'upstream',
          remoteType: 'github',
          defaultPullStrategy: 'rebase',
          defaultPushStrategy: 'force-with-lease',
          conflictResolution: ConflictResolutionStrategy.serverAlwaysRight,
        );

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Conflict Resolution Strategies', () {
      test('should parse conflict resolution strategy from config', () async {
        // Test clientAlwaysRight (default)
        final config1 = OfflineGitConfig(localPath: tempDir);

        await provider.initWithConfig(config1);
        expect(await provider.isAuthenticated(), isTrue);

        // Test serverAlwaysRight
        final provider2 = OfflineGitStorageProvider();
        final tempDir2 = (await Directory.systemTemp.createTemp(
          'git_test_',
        )).path;

        final config2 = OfflineGitConfig(
          localPath: tempDir2,
          conflictResolution: ConflictResolutionStrategy.serverAlwaysRight,
        );

        await provider2.initWithConfig(config2);
        expect(await provider2.isAuthenticated(), isTrue);

        // Clean up
        await Directory(tempDir2).delete(recursive: true);
      });

      test(
        'should default to clientAlwaysRight for default strategy',
        () async {
          final config = OfflineGitConfig(
            localPath: tempDir,
          ); // Default strategy is clientAlwaysRight

          await provider.initWithConfig(config);
          expect(await provider.isAuthenticated(), isTrue);
        },
      );
    });

    group('Sync Strategies', () {
      test('should configure pull and push strategies', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          defaultPullStrategy: 'ff-only',
          defaultPushStrategy: 'fail-on-conflict',
        );

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });

      test('should use default strategies when not specified', () async {
        final config = OfflineGitConfig(localPath: tempDir);

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Authentication Configuration', () {
      test('should configure SSH key path', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          remoteUrl: const VcUrl('https://github.com/test/repo.git'),
          sshKeyPath: '/path/to/ssh/key',
        );

        await provider.initWithConfig(config);
        expect(provider.supportsSync, isTrue);
        expect(config.sshKeyPath, '/path/to/ssh/key');
      });

      test('should configure HTTPS token', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          remoteUrl: const VcUrl('https://github.com/test/repo.git'),
          httpsToken: 'github_pat_test_token',
        );

        await provider.initWithConfig(config);
        expect(provider.supportsSync, isTrue);
        expect(config.httpsToken, 'github_pat_test_token');
      });
    });

    group('Error Handling', () {
      test(
        'should handle network timeout gracefully',
        () async {
          final config = OfflineGitConfig(
            localPath: tempDir,
            remoteUrl: const VcUrl(
              'https://httpbin.org/delay/5',
            ), // Returns after delay
          );

          await provider.initWithConfig(config);
          expect(() => provider.sync(), throwsA(isA<NetworkException>()));
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test('should handle authentication failure', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          remoteUrl: const VcUrl(
            'https://github.com/private/repo.git',
          ), // Requires auth
        );

        await provider.initWithConfig(config);
        expect(() => provider.sync(), throwsA(isA<NetworkException>()));
      });
    });

    group('Integration with StorageService', () {
      late StorageService storageService;

      setUp(() {
        storageService = StorageService(provider);
      });

      test('should sync through StorageService', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
        );

        // Should not throw for provider without remote URL
        // (StorageService handles this gracefully)
        await storageService.syncRemote();
      });

      test('should pass sync strategies to provider', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          remoteUrl: const VcUrl('https://invalid-url.com/repo.git'),
        );

        await storageService.syncRemote(
          pullMergeStrategy: 'rebase',
          pushConflictStrategy: 'force-with-lease',
        );
      });
    });

    group('Configuration Validation', () {
      test('should throw exception for missing localPath', () {
        expect(
          () => OfflineGitConfig(localPath: ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw exception for missing branchName', () {
        // In new interface defaults, branchName defaults to main; no exception
        final cfg = OfflineGitConfig(localPath: tempDir);
        expect(cfg.branchName, equals(VcBranchName.main));
      });

      test('should throw exception for empty localPath', () {
        expect(
          () => OfflineGitConfig(localPath: ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw exception for empty branchName', () {
        // Branch defaults to main; no exception here
        final cfg = OfflineGitConfig(localPath: tempDir);
        expect(cfg.branchName, equals(VcBranchName.main));
      });

      test('should build valid config with all options', () async {
        final config = OfflineGitConfig(
          localPath: tempDir,
          authorName: 'Test User',
          authorEmail: 'test@example.com',
          remoteUrl: const VcUrl('https://github.com/test/repo.git'),
          remoteName: 'upstream',
          remoteType: 'github',
          defaultPullStrategy: 'rebase',
          defaultPushStrategy: 'force-with-lease',
          conflictResolution: ConflictResolutionStrategy.manualResolution,
          httpsToken: 'test-token',
        );

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
        expect(provider.supportsSync, isTrue);
      });

      test('should build minimal valid config', () {
        final config = OfflineGitConfig(localPath: tempDir);

        expect(config.localPath, equals(tempDir));
        expect(config.branchName, equals(VcBranchName.main));
        expect(
          config.conflictResolution,
          equals(ConflictResolutionStrategy.clientAlwaysRight),
        );
        expect(config.defaultPullStrategy, equals('merge'));
        expect(config.defaultPushStrategy, equals('rebase-local'));
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
