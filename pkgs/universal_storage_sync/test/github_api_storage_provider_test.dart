import 'package:test/test.dart';
import 'package:universal_storage_sync/src/config/storage_config.dart';
import 'package:universal_storage_sync/src/providers/github_api_storage_provider.dart';

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
      const config = FileSystemConfig(basePath: '/test');
      expect(
        () => provider.initWithConfig(config),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ConfigurationException when '
        'authToken is missing in manual mode', () {
      final config = GitHubApiConfig.builder()
          .repositoryOwner('test')
          .repositoryName('test-repo')
          .build;

      expect(config, throwsA(isA<StateError>()));
    });

    test('should throw ConfigurationException when '
        'repositoryOwner is missing in manual mode', () {
      expect(
        () => GitHubApiConfig.builder()
            .authToken('test-token')
            .repositoryName('test-repo')
            .build(),
        throwsA(isA<StateError>()),
      );
    });

    test('should throw ConfigurationException when '
        'repositoryName is missing in manual mode', () {
      expect(
        () => GitHubApiConfig.builder()
            .authToken('test-token')
            .repositoryOwner('test')
            .build(),
        throwsA(isA<StateError>()),
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
      final config = GitHubApiConfig.builder()
          .authToken('test-token')
          .repositoryOwner('test-owner')
          .repositoryName('test-repo')
          .build();

      expect(config.authToken, equals('test-token'));
      expect(config.repositoryOwner, equals('test-owner'));
      expect(config.repositoryName, equals('test-repo'));
    });
  });
}
