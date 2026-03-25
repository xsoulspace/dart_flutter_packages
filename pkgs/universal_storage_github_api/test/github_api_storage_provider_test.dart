import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_github_api/universal_storage_github_api.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  group('GitHubApiStorageProvider', () {
    late GitHubApiStorageProvider provider;

    setUp(() {
      provider = GitHubApiStorageProvider();
    });

    test('should be instantiated', () {
      expect(provider, isA<GitHubApiStorageProvider>());
    });

    test('implements RemoteEngine role with declared capabilities', () {
      expect(provider, isA<RemoteEngine>());
      expect(provider.declaredCapabilities.supportsRevisionMetadata, isTrue);
      expect(provider.declaredCapabilities.supportsDiff, isFalse);
    });

    test('declares clone-to-local capability as unsupported', () async {
      expect(
        provider.declaredVersionControlCapabilities.supportsCloneToLocal,
        isFalse,
      );
      final resolved = await provider.resolveVersionControlCapabilities();
      expect(resolved.supportsCloneToLocal, isFalse);
    });

    test('should throw ArgumentError when wrong config type is provided', () {
      final tempDirectory = Directory.systemTemp.createTempSync(
        'github_api_wrong_config_test_',
      );
      final config = FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: tempDirectory.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
        ),
      );
      expect(
        () => provider.initWithConfig(config),
        throwsA(isA<ArgumentError>()),
      );
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('should throw ArgumentError when '
        'authToken'
        ' is missing in manual mode', () {
      expect(
        () => GitHubApiConfig(
          repositoryOwner: const VcRepositoryOwner('test'),
          repositoryName: const VcRepositoryName('test-repo'),
          authToken: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ArgumentError when '
        'repositoryOwner'
        ' is missing in manual mode', () {
      expect(
        () => GitHubApiConfig(
          authToken: 'test-token',
          repositoryName: const VcRepositoryName('test-repo'),
          repositoryOwner: VcRepositoryOwner.empty,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ArgumentError when '
        'repositoryName'
        ' is missing in manual mode', () {
      expect(
        () => GitHubApiConfig(
          authToken: 'test-token',
          repositoryOwner: const VcRepositoryOwner('test'),
          repositoryName: VcRepositoryName.empty,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should not support sync operations', () {
      expect(provider.supportsSync, isFalse);
    });

    test(
      'should return false for isAuthenticated when not initialized',
      () async {
        final result = await provider.isAuthenticated();
        expect(result, isFalse);
      },
    );

    test('should build valid manual config', () {
      final config = GitHubApiConfig(
        authToken: 'test-token',
        repositoryOwner: const VcRepositoryOwner('test-owner'),
        repositoryName: const VcRepositoryName('test-repo'),
      );

      expect(config.authToken, equals('test-token'));
      expect(config.repositoryOwner.value, equals('test-owner'));
      expect(config.repositoryName.value, equals('test-repo'));
    });

    test('cloneRepository should require initialized provider '
        'and not throw UnimplementedError', () {
      expect(
        () => provider.cloneRepository(
          const VcRepository(id: '1', name: 'repo'),
          '/tmp/repo',
        ),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('setRepository should require initialized provider '
        'and not throw UnimplementedError', () {
      expect(
        () => provider.setRepository(const VcRepositoryName('another-repo')),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('dispose should complete without throwing', () async {
      await provider.dispose();
      expect(await provider.isAuthenticated(), isFalse);
    });
  });
}
