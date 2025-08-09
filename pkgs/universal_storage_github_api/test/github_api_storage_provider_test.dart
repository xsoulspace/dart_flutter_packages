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

    test('should throw ArgumentError when wrong config type is provided', () {
      final config = FileSystemConfig(basePath: '/test');
      expect(
        () => provider.initWithConfig(config),
        throwsA(isA<ArgumentError>()),
      );
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
          repositoryOwner: const VcRepositoryOwner(''),
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
          repositoryName: const VcRepositoryName(''),
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
  });
}


