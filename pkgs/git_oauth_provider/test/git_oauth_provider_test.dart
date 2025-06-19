import 'package:flutter_test/flutter_test.dart';
import 'package:git_oauth_provider/git_oauth_provider.dart';

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

  group('GitHubOAuthConfig', () {
    test('should create valid configuration', () {
      const config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
      );

      expect(config.platform, GitPlatform.github);
      expect(config.clientId, 'test_client_id');
      expect(config.clientSecret, 'test_client_secret');
      expect(config.redirectUri, 'test://callback');
      expect(config.customUriScheme, 'test');
      expect(config.scopes, ['repo', 'user:email']);
    });

    test('should allow custom scopes', () {
      const config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
        scopes: ['read:user', 'public_repo'],
      );

      expect(config.scopes, ['read:user', 'public_repo']);
    });
  });

  group('OAuthUser', () {
    test('should create user from JSON', () {
      final json = {
        'id': '12345',
        'login': 'testuser',
        'email': 'test@example.com',
        'name': 'Test User',
        'avatarUrl': 'https://example.com/avatar.png',
      };

      final user = OAuthUser.fromJson(json);

      expect(user.id, '12345');
      expect(user.login, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.avatarUrl, 'https://example.com/avatar.png');
    });

    test('should handle missing optional fields', () {
      final json = {
        'id': '12345',
        'login': 'testuser',
      };

      final user = OAuthUser.fromJson(json);

      expect(user.id, '12345');
      expect(user.login, 'testuser');
      expect(user.email, isNull);
      expect(user.name, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('should convert to JSON', () {
      const user = OAuthUser(
        id: '12345',
        login: 'testuser',
        email: 'test@example.com',
        name: 'Test User',
      );

      final json = user.toJson();

      expect(json['id'], '12345');
      expect(json['login'], 'testuser');
      expect(json['email'], 'test@example.com');
      expect(json['name'], 'Test User');
    });
  });

  group('StoredCredentials', () {
    test('should detect expired credentials', () {
      final expiredCredentials = StoredCredentials(
        accessToken: 'token',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(expiredCredentials.isExpired, isTrue);
    });

    test('should detect valid credentials', () {
      final validCredentials = StoredCredentials(
        accessToken: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(validCredentials.isExpired, isFalse);
    });

    test('should handle null expiration', () {
      const credentialsWithoutExpiration = StoredCredentials(
        accessToken: 'token',
      );

      expect(credentialsWithoutExpiration.isExpired, isFalse);
    });

    test('should serialize to and from JSON', () {
      final credentials = StoredCredentials(
        accessToken: 'access_token',
        refreshToken: 'refresh_token',
        expiresAt: DateTime.parse('2024-12-31T23:59:59Z'),
        scopes: ['repo', 'user:email'],
      );

      final json = credentials.toJson();
      final restored = StoredCredentials.fromJson(json);

      expect(restored.accessToken, credentials.accessToken);
      expect(restored.refreshToken, credentials.refreshToken);
      expect(restored.expiresAt, credentials.expiresAt);
      expect(restored.scopes, credentials.scopes);
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

  group('Exceptions', () {
    test('AuthenticationException should format message correctly', () {
      const exception =
          AuthenticationException('Login failed', 'Invalid credentials');

      expect(exception.message, 'Login failed');
      expect(exception.details, 'Invalid credentials');
      expect(exception.toString(),
          'AuthenticationException: Login failed (Invalid credentials)');
    });

    test('ApiException should have convenience constructors', () {
      const networkException = ApiException.network('Connection timeout');
      const unauthorizedException = ApiException.unauthorized();
      const rateLimitedException =
          ApiException.rateLimited('Too many requests');

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
}
