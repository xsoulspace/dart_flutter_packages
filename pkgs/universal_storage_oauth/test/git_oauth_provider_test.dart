import 'package:flutter_test/flutter_test.dart';
import 'package:universal_storage_oauth/universal_storage_oauth.dart';

void main() {
  group('GitPlatform', () {
    test('should have correct URLs for GitHub', () {
      const platform = GitPlatform.github;

      expect(platform.displayName, 'GitHub');
      expect(platform.apiBaseUrl, 'https://api.github.com');
      expect(platform.webUrl, 'https://github.com');
      expect(platform.authUrl, 'https://github.com/login/oauth/authorize');
      expect(platform.tokenUrl, 'https://github.com/login/oauth/access_token');
    });

    test('should have correct URLs for GitLab', () {
      const platform = GitPlatform.gitlab;

      expect(platform.displayName, 'GitLab');
      expect(platform.apiBaseUrl, 'https://gitlab.com/api/v4');
      expect(platform.webUrl, 'https://gitlab.com');
      expect(platform.authUrl, 'https://gitlab.com/oauth/authorize');
      expect(platform.tokenUrl, 'https://gitlab.com/oauth/token');
    });
  });

  group('OAuthConfig GitHub', () {
    test('should create valid configuration', () {
      final config = OAuthConfig.github(
        clientId: const OAuthClientId('test_client_id'),
        clientSecret: const OAuthClientSecret('test_client_secret'),
        redirectUri: const OAuthRedirectUri('test://callback'),
        customUriScheme: const OAuthCustomUriScheme('test'),
      );

      expect(config.platform, GitPlatform.github);
      expect(config.clientId.value, 'test_client_id');
      expect(config.clientSecret.value, 'test_client_secret');
      expect(config.redirectUri.value, 'test://callback');
      expect(config.customUriScheme.value, 'test');
      expect(config.scopes.value, ['repo', 'user:email']);
    });

    test('should allow custom scopes', () {
      final config = OAuthConfig.github(
        clientId: const OAuthClientId('test_client_id'),
        clientSecret: const OAuthClientSecret('test_client_secret'),
        redirectUri: const OAuthRedirectUri('test://callback'),
        customUriScheme: const OAuthCustomUriScheme('test'),
        scopes: const OAuthScopes(['read:user', 'public_repo']),
      );

      expect(config.scopes.value, ['read:user', 'public_repo']);
    });

    test('should create GitLab configuration', () {
      final config = OAuthConfig.gitlab(
        clientId: const OAuthClientId('test_client_id'),
        clientSecret: const OAuthClientSecret('test_client_secret'),
        redirectUri: const OAuthRedirectUri('test://callback'),
        customUriScheme: const OAuthCustomUriScheme('test'),
      );

      expect(config.platform, GitPlatform.gitlab);
      expect(config.clientId.value, 'test_client_id');
      expect(config.clientSecret.value, 'test_client_secret');
      expect(config.redirectUri.value, 'test://callback');
      expect(config.customUriScheme.value, 'test');
      expect(config.scopes.value, [
        'read_user',
        'read_repository',
        'write_repository',
      ]);
    });
  });

  group('OAuthUser', () {
    test('should create user from JSON', () {
      final json = {
        'id': '12345',
        'login': 'testuser',
        'email': 'test@example.com',
        'name': 'Test User',
        'avatar_url': 'https://example.com/avatar.png',
      };

      final user = OAuthUser.fromJson(json);

      expect(user.id, '12345');
      expect(user.login, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.avatarUrl, 'https://example.com/avatar.png');
    });

    test('should handle missing optional fields', () {
      final json = {'id': '12345', 'login': 'testuser'};

      final user = OAuthUser.fromJson(json);

      expect(user.id, '12345');
      expect(user.login, 'testuser');
      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('should convert to JSON', () {
      const user = OAuthUser({
        'id': '12345',
        'login': 'testuser',
        'email': 'test@example.com',
        'name': 'Test User',
      });

      final json = user.toJson();

      expect(json['id'], '12345');
      expect(json['login'], 'testuser');
      expect(json['email'], 'test@example.com');
      expect(json['name'], 'Test User');
    });

    test('should handle extended user data', () {
      final json = {
        'id': '12345',
        'login': 'testuser',
        'email': 'test@example.com',
        'name': 'Test User',
        'avatar_url': 'https://example.com/avatar.png',
        'bio': 'Software Developer',
        'location': 'San Francisco',
        'company': 'Tech Corp',
        'html_url': 'https://github.com/testuser',
        'public_repos': 42,
        'followers': 123,
        'following': 56,
        'created_at': '2020-01-01T00:00:00Z',
      };

      final user = OAuthUser.fromJson(json);

      expect(user.bio, 'Software Developer');
      expect(user.location, 'San Francisco');
      expect(user.company, 'Tech Corp');
      expect(user.htmlUrl, 'https://github.com/testuser');
      expect(user.publicRepos, 42);
      expect(user.followers, 123);
      expect(user.following, 56);
      expect(user.createdAt, DateTime.parse('2020-01-01T00:00:00Z'));
    });
  });

  group('StoredCredentials', () {
    test('should detect expired credentials', () {
      final expiredCredentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('token'),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(expiredCredentials.isExpired, isTrue);
      expect(expiredCredentials.isValid, isFalse);
    });

    test('should detect valid credentials', () {
      final validCredentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('token'),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(validCredentials.isExpired, isFalse);
      expect(validCredentials.isValid, isTrue);
    });

    test('should handle null expiration', () {
      final credentialsWithoutExpiration = StoredCredentials.create(
        accessToken: const OAuthAccessToken('token'),
      );

      expect(credentialsWithoutExpiration.isExpired, isFalse);
      expect(credentialsWithoutExpiration.hasExpiration, isFalse);
      expect(credentialsWithoutExpiration.isValid, isTrue);
    });

    test('should handle refresh tokens', () {
      final credentialsWithRefresh = StoredCredentials.create(
        accessToken: const OAuthAccessToken('access_token'),
        refreshToken: const OAuthRefreshToken('refresh_token'),
      );

      expect(credentialsWithRefresh.hasRefreshToken, isTrue);
      expect(credentialsWithRefresh.refreshToken?.value, 'refresh_token');

      final credentialsWithoutRefresh = StoredCredentials.create(
        accessToken: const OAuthAccessToken('access_token'),
      );

      expect(credentialsWithoutRefresh.hasRefreshToken, isFalse);
      expect(credentialsWithoutRefresh.refreshToken, isNull);
    });

    test('should handle scopes', () {
      final credentialsWithScopes = StoredCredentials.create(
        accessToken: const OAuthAccessToken('token'),
        scopes: ['repo', 'user:email', 'read:org'],
      );

      expect(credentialsWithScopes.hasScopes, isTrue);
      expect(credentialsWithScopes.scopeCount, 3);
      expect(credentialsWithScopes.containsScope('repo'), isTrue);
      expect(credentialsWithScopes.containsScope('admin'), isFalse);

      final credentialsWithoutScopes = StoredCredentials.create(
        accessToken: const OAuthAccessToken('token'),
      );

      expect(credentialsWithoutScopes.hasScopes, isFalse);
      expect(credentialsWithoutScopes.scopeCount, 0);
      expect(credentialsWithoutScopes.containsScope('repo'), isFalse);
    });

    test('should serialize to and from JSON', () {
      final credentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('access_token'),
        refreshToken: const OAuthRefreshToken('refresh_token'),
        expiresAt: DateTime.parse('2024-12-31T23:59:59Z'),
        scopes: ['repo', 'user:email'],
      );

      final json = credentials.toJson();
      final restored = StoredCredentials.fromJson(json);

      expect(restored.accessToken.value, credentials.accessToken.value);
      expect(restored.refreshToken?.value, credentials.refreshToken?.value);
      expect(restored.expiresAt, credentials.expiresAt);
      expect(restored.scopes, credentials.scopes);
    });

    test('should provide safe token representation', () {
      final credentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('ghp_very_long_secret_token_12345'),
      );

      expect(credentials.accessToken.safeRepresentation, 'ghp_very...');

      final emptyCredentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken(''),
      );

      expect(emptyCredentials.accessToken.safeRepresentation, 'empty');
    });
  });

  group('CreateRepositoryRequest', () {
    test('should create basic request', () {
      const request = CreateRepositoryRequest(name: 'test-repo');

      expect(request.name, 'test-repo');
      expect(request.isPrivate, isFalse);
      expect(request.autoInit, isFalse);
      expect(request.description, isNull);
    });

    test('should create full request', () {
      const request = CreateRepositoryRequest(
        name: 'test-repo',
        description: 'A test repository',
        isPrivate: true,
        autoInit: true,
        organizationName: 'test-org',
      );

      expect(request.name, 'test-repo');
      expect(request.description, 'A test repository');
      expect(request.isPrivate, isTrue);
      expect(request.autoInit, isTrue);
      expect(request.organizationName, 'test-org');
    });
  });

  group('RepositoryInfo', () {
    test('should create repository info from data', () {
      final repoInfo = RepositoryInfo.create(
        id: '123456',
        name: 'test-repo',
        fullName: 'owner/test-repo',
        owner: RepositoryOwner.create(
          id: '789',
          login: 'owner',
          type: RepositoryOwnerType.user,
          avatarUrl: 'https://example.com/avatar.png',
          htmlUrl: 'https://github.com/owner',
        ),
        description: 'Test repository',
        defaultBranch: 'main',
        cloneUrl: 'https://github.com/owner/test-repo.git',
        sshUrl: 'git@github.com:owner/test-repo.git',
        htmlUrl: 'https://github.com/owner/test-repo',
        language: 'Dart',
        starCount: 42,
        forkCount: 7,
        size: 1024,
      );

      expect(repoInfo.id, '123456');
      expect(repoInfo.name, 'test-repo');
      expect(repoInfo.fullName, 'owner/test-repo');
      expect(repoInfo.owner.login, 'owner');
      expect(repoInfo.owner.type, RepositoryOwnerType.user);
      expect(repoInfo.description, 'Test repository');
      expect(repoInfo.isPrivate, isFalse);
      expect(repoInfo.defaultBranch, 'main');
      expect(repoInfo.language, 'Dart');
      expect(repoInfo.starCount, 42);
      expect(repoInfo.forkCount, 7);
      expect(repoInfo.size, 1024);
    });

    test('should handle organization owner type', () {
      final repoInfo = RepositoryInfo.create(
        id: '123456',
        name: 'test-repo',
        fullName: 'org/test-repo',
        owner: RepositoryOwner.create(
          id: '789',
          login: 'org',
          type: RepositoryOwnerType.organization,
          avatarUrl: 'https://example.com/org-avatar.png',
          htmlUrl: 'https://github.com/org',
        ),
        isPrivate: true,
        defaultBranch: 'develop',
      );

      expect(repoInfo.owner.type, RepositoryOwnerType.organization);
      expect(repoInfo.owner.login, 'org');
      expect(repoInfo.isPrivate, isTrue);
      expect(repoInfo.defaultBranch, 'develop');
    });
  });

  group('Exceptions', () {
    test('AuthenticationException should format message correctly', () {
      const exception = AuthenticationException(
        'Login failed',
        'Invalid credentials',
      );

      expect(exception.message, 'Login failed');
      expect(exception.details, 'Invalid credentials');
      expect(
        exception.toString(),
        'AuthenticationException: Login failed (Invalid credentials)',
      );
    });

    test('ApiException should have convenience constructors', () {
      const networkException = ApiException.network('Connection timeout');
      const unauthorizedException = ApiException.unauthorized();
      const rateLimitedException = ApiException.rateLimited(
        'Too many requests',
      );

      expect(networkException.message, 'Network error occurred');
      expect(networkException.details, 'Connection timeout');

      expect(unauthorizedException.message, 'Unauthorized access');
      expect(unauthorizedException.details, isNull);

      expect(rateLimitedException.message, 'Rate limit exceeded');
      expect(rateLimitedException.details, 'Too many requests');
    });

    test('RepositoryException should have convenience constructors', () {
      const notFound = RepositoryException.notFound('owner/repo');
      const accessDenied = RepositoryException.accessDenied('owner/repo');
      const alreadyExists = RepositoryException.alreadyExists('owner/repo');

      expect(notFound.message, 'Repository not found');
      expect(notFound.details, 'owner/repo');

      expect(accessDenied.message, 'Access denied to repository');
      expect(accessDenied.details, 'owner/repo');

      expect(alreadyExists.message, 'Repository already exists');
      expect(alreadyExists.details, 'owner/repo');
    });
  });

  group('OAuthAccessToken', () {
    test('should provide utility methods', () {
      const token = OAuthAccessToken('test_token');
      const emptyToken = OAuthAccessToken('');

      expect(token.isEmpty, isFalse);
      expect(token.isNotEmpty, isTrue);
      expect(emptyToken.isEmpty, isTrue);
      expect(emptyToken.isNotEmpty, isFalse);
    });

    test('should provide safe fallback', () {
      const primaryToken = OAuthAccessToken('');
      const fallbackToken = OAuthAccessToken('fallback');

      final result = primaryToken.whenEmptyUse(fallbackToken);
      expect(result.value, 'fallback');

      const validToken = OAuthAccessToken('valid');
      final resultValid = validToken.whenEmptyUse(fallbackToken);
      expect(resultValid.value, 'valid');
    });
  });

  group('OAuthRefreshToken', () {
    test('should provide utility methods', () {
      const token = OAuthRefreshToken('refresh_token');
      const emptyToken = OAuthRefreshToken('');

      expect(token.isEmpty, isFalse);
      expect(token.isNotEmpty, isTrue);
      expect(emptyToken.isEmpty, isTrue);
      expect(emptyToken.isNotEmpty, isFalse);
    });

    test('should provide safe fallback', () {
      const primaryToken = OAuthRefreshToken('');
      const fallbackToken = OAuthRefreshToken('fallback');

      final result = primaryToken.whenEmptyUse(fallbackToken);
      expect(result.value, 'fallback');
    });
  });

  group('MockCredentialStorage', () {
    late MockCredentialStorage storage;

    setUp(() {
      storage = MockCredentialStorage();
    });

    test('should store and retrieve credentials', () async {
      final credentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('test_token'),
        refreshToken: const OAuthRefreshToken('refresh_token'),
        scopes: ['repo', 'user:email'],
      );

      await storage.storeCredentials(GitPlatform.github, credentials);

      final retrieved = await storage.getCredentials(GitPlatform.github);
      expect(retrieved, isNotNull);
      expect(retrieved!.accessToken.value, 'test_token');
      expect(retrieved.refreshToken?.value, 'refresh_token');
      expect(retrieved.scopes, ['repo', 'user:email']);
    });

    test('should return null for non-existent credentials', () async {
      final result = await storage.getCredentials(GitPlatform.github);
      expect(result, isNull);
    });

    test('should clear credentials', () async {
      final credentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('test_token'),
      );

      await storage.storeCredentials(GitPlatform.github, credentials);
      expect(await storage.hasCredentials(GitPlatform.github), isTrue);

      await storage.clearCredentials(GitPlatform.github);
      expect(await storage.hasCredentials(GitPlatform.github), isFalse);
    });

    test('should clear all credentials', () async {
      final credentials = StoredCredentials.create(
        accessToken: const OAuthAccessToken('test_token'),
      );

      await storage.storeCredentials(GitPlatform.github, credentials);
      await storage.storeCredentials(GitPlatform.gitlab, credentials);

      await storage.clearAllCredentials();

      expect(await storage.hasCredentials(GitPlatform.github), isFalse);
      expect(await storage.hasCredentials(GitPlatform.gitlab), isFalse);
    });
  });
}

/// Mock implementation of CredentialStorage for testing
class MockCredentialStorage implements CredentialStorage {
  final Map<GitPlatform, StoredCredentials> _storage = {};

  @override
  Future<void> storeCredentials(
    final GitPlatform platform,
    final StoredCredentials credentials,
  ) async {
    _storage[platform] = credentials;
  }

  @override
  Future<StoredCredentials?> getCredentials(final GitPlatform platform) async =>
      _storage[platform];

  @override
  Future<void> clearCredentials(final GitPlatform platform) async {
    _storage.remove(platform);
  }

  @override
  Future<void> clearAllCredentials() async {
    _storage.clear();
  }

  @override
  Future<bool> hasCredentials(final GitPlatform platform) async =>
      _storage.containsKey(platform);
}
