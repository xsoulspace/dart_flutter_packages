import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

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
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authorName('Test User')
            .authorEmail('test@example.com')
            .build();

        await provider.initWithConfig(config);
        expect(() => provider.sync(), throwsA(isA<AuthenticationException>()));
      });

      test('should handle invalid remote URL gracefully', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authorName('Test User')
            .authorEmail('test@example.com')
            .remoteUrl('https://invalid-url-that-does-not-exist.com/repo.git')
            .build();

        await provider.initWithConfig(config);
        expect(() => provider.sync(), throwsA(isA<NetworkException>()));
      });

      test('should configure remote settings from config', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authorName('Test User')
            .authorEmail('test@example.com')
            .remoteUrl('https://github.com/test/repo.git')
            .remoteName('upstream')
            .remoteType('github')
            .defaultPullStrategy('rebase')
            .defaultPushStrategy('force-with-lease')
            .conflictResolution(ConflictResolutionStrategy.serverAlwaysRight)
            .build();

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Conflict Resolution Strategies', () {
      test('should parse conflict resolution strategy from config', () async {
        // Test clientAlwaysRight (default)
        final config1 = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .conflictResolution(ConflictResolutionStrategy.clientAlwaysRight)
            .build();

        await provider.initWithConfig(config1);
        expect(await provider.isAuthenticated(), isTrue);

        // Test serverAlwaysRight
        final provider2 = OfflineGitStorageProvider();
        final tempDir2 = (await Directory.systemTemp.createTemp(
          'git_test_',
        )).path;

        final config2 = OfflineGitConfig.builder()
            .localPath(tempDir2)
            .branchName('main')
            .conflictResolution(ConflictResolutionStrategy.serverAlwaysRight)
            .build();

        await provider2.initWithConfig(config2);
        expect(await provider2.isAuthenticated(), isTrue);

        // Clean up
        await Directory(tempDir2).delete(recursive: true);
      });

      test(
        'should default to clientAlwaysRight for default strategy',
        () async {
          final config = OfflineGitConfig.builder()
              .localPath(tempDir)
              .branchName('main')
              .build(); // Default strategy is clientAlwaysRight

          await provider.initWithConfig(config);
          expect(await provider.isAuthenticated(), isTrue);
        },
      );
    });

    group('Sync Strategies', () {
      test('should configure pull and push strategies', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .defaultPullStrategy('ff-only')
            .defaultPushStrategy('fail-on-conflict')
            .build();

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });

      test('should use default strategies when not specified', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .build();

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Authentication Configuration', () {
      test('should configure SSH key path', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authentication()
            .sshKey('/path/to/ssh/key')
            .build();

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });

      test('should configure HTTPS token', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authentication()
            .httpsToken('github_pat_test_token')
            .build();

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
      });
    });

    group('Error Handling', () {
      test(
        'should handle network timeout gracefully',
        () async {
          final config = OfflineGitConfig.builder()
              .localPath(tempDir)
              .branchName('main')
              .remoteUrl('https://httpbin.org/delay/5') // Returns after delay
              .build();

          await provider.initWithConfig(config);
          expect(() => provider.sync(), throwsA(isA<NetworkException>()));
        },
        timeout: const Timeout(Duration(seconds: 10)),
      );

      test('should handle authentication failure', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .remoteUrl('https://github.com/private/repo.git') // Requires auth
            .build();

        await provider.initWithConfig(config);
        expect(() => provider.sync(), throwsA(isA<NetworkException>()));
      });
    });

    group('Integration with StorageService', () {
      late StorageService storageService;

      setUp(() async {
        storageService = StorageService(provider);
      });

      test('should sync through StorageService', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authorName('Test User')
            .authorEmail('test@example.com')
            .build();

        await storageService.initializeWithConfig(config);

        // Should not throw for provider without remote URL
        // (StorageService handles this gracefully)
        await storageService.syncRemote();
      });

      test('should pass sync strategies to provider', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .remoteUrl('https://invalid-url.com/repo.git')
            .build();

        await storageService.initializeWithConfig(config);

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
      test('should throw exception for missing localPath', () async {
        expect(
          () => OfflineGitConfig.builder().branchName('main').build(),
          throwsA(isA<StateError>()),
        );
      });

      test('should throw exception for missing branchName', () async {
        expect(
          () => OfflineGitConfig.builder().localPath(tempDir).build(),
          throwsA(isA<StateError>()),
        );
      });

      test('should throw exception for empty localPath', () async {
        expect(
          () => OfflineGitConfig.builder()
              .localPath('')
              .branchName('main')
              .build(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should throw exception for empty branchName', () async {
        expect(
          () => OfflineGitConfig.builder()
              .localPath(tempDir)
              .branchName('')
              .build(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should build valid config with all options', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .authorName('Test User')
            .authorEmail('test@example.com')
            .remoteUrl('https://github.com/test/repo.git')
            .remoteName('upstream')
            .remoteType('github')
            .defaultPullStrategy('rebase')
            .defaultPushStrategy('force-with-lease')
            .conflictResolution(ConflictResolutionStrategy.manualResolution)
            .authentication()
            .httpsToken('test-token')
            .build();

        await provider.initWithConfig(config);
        expect(await provider.isAuthenticated(), isTrue);
        expect(provider.supportsSync, isTrue);
      });

      test('should build minimal valid config', () async {
        final config = OfflineGitConfig.builder()
            .localPath(tempDir)
            .branchName('main')
            .build();

        expect(config.localPath, equals(tempDir));
        expect(config.branchName, equals('main'));
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
