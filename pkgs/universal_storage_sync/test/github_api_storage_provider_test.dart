import 'package:test/test.dart';
import 'package:universal_storage_sync/src/exceptions/storage_exceptions.dart';
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

    test('should throw ConfigurationException when required config is missing',
        () async {
      expect(
        () => provider.init({}),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('should throw ConfigurationException when authToken is missing',
        () async {
      expect(
        () => provider.init({
          'repositoryOwner': 'test',
          'repositoryName': 'test-repo',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('should throw ConfigurationException when repositoryOwner is missing',
        () async {
      expect(
        () => provider.init({
          'authToken': 'test-token',
          'repositoryName': 'test-repo',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('should throw ConfigurationException when repositoryName is missing',
        () async {
      expect(
        () => provider.init({
          'authToken': 'test-token',
          'repositoryOwner': 'test',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('should not support sync operations', () {
      expect(provider.supportsSync, isFalse);
    });

    test('should return false for isAuthenticated when not initialized',
        () async {
      final result = await provider.isAuthenticated();
      expect(result, isFalse);
    });
  });
}
