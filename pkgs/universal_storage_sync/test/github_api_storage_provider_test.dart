import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

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
          repositoryOwner: 'test',
          repositoryName: 'test-repo',
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
          repositoryName: 'test-repo',
          repositoryOwner: '',
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
          repositoryOwner: 'test',
          repositoryName: '',
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
        repositoryOwner: 'test-owner',
        repositoryName: 'test-repo',
      );

      expect(config.authToken, equals('test-token'));
      expect(config.repositoryOwner, equals('test-owner'));
      expect(config.repositoryName, equals('test-repo'));
    });
  });
}
