import 'package:flutter_test/flutter_test.dart';
import 'package:universal_storage_oauth/universal_storage_oauth.dart';

void main() {
  group('GitHubOAuthConfig', () {
    test('should create valid GitHub configuration with default scopes', () {
      final config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
      );

      expect(config.clientId, 'test_client_id');
      expect(config.clientSecret, 'test_client_secret');
      expect(config.redirectUri, 'test://callback');
      expect(config.customUriScheme, 'test');
      expect(config.scopes, ['repo', 'user:email']); // Default GitHub scopes
    });

    test('should allow custom scopes', () {
      final config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
        scopes: ['read:user', 'public_repo'],
      );

      expect(config.scopes, ['read:user', 'public_repo']);
    });

    test('should have correct platform information', () {
      final config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
      );

      expect(config.platform.displayName, 'GitHub');
      expect(config.platform.apiBaseUrl, 'https://api.github.com');
      expect(config.platform.webUrl, 'https://github.com');
      expect(
        config.platform.authUrl,
        'https://github.com/login/oauth/authorize',
      );
      expect(
        config.platform.tokenUrl,
        'https://github.com/login/oauth/access_token',
      );
    });

    test('should serialize to and from JSON', () {
      final config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
        scopes: ['repo', 'user:email'],
      );

      final json = config.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['platform'], 'github');
      expect(json['client_id'], 'test_client_id');
      expect(json['client_secret'], 'test_client_secret');
      expect(json['redirect_uri'], 'test://callback');
      expect(json['custom_uri_scheme'], 'test');
      expect(json['scopes'], ['repo', 'user:email']);
    });

    test('should handle empty scopes', () {
      final config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
        scopes: [],
      );

      expect(config.scopes, isEmpty);
    });
  });

  group('Platform URLs', () {
    test('GitHub platform should have correct URLs', () {
      final config = GitHubOAuthConfig(
        clientId: 'test_client_id',
        clientSecret: 'test_client_secret',
        redirectUri: 'test://callback',
        customUriScheme: 'test',
      );

      final platform = config.platform;
      expect(platform.displayName, 'GitHub');
      expect(platform.apiBaseUrl, 'https://api.github.com');
      expect(platform.webUrl, 'https://github.com');
      expect(platform.authUrl, 'https://github.com/login/oauth/authorize');
      expect(platform.tokenUrl, 'https://github.com/login/oauth/access_token');
    });
  });

  group('Exception Types', () {
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

    test('ConfigurationException should format message correctly', () {
      const exception = ConfigurationException(
        'Invalid client ID',
        'Client ID cannot be empty',
      );

      expect(exception.message, 'Invalid client ID');
      expect(exception.details, 'Client ID cannot be empty');
      expect(
        exception.toString(),
        'ConfigurationException: Invalid client ID (Client ID cannot be empty)',
      );
    });
  });

  group('OAuth User Model', () {
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

  group('Configuration Validation', () {
    test('should accept valid configuration parameters', () {
      expect(
        () => GitHubOAuthConfig(
          clientId: 'valid_client_id',
          clientSecret: 'valid_client_secret',
          redirectUri: 'myapp://callback',
          customUriScheme: 'myapp',
        ),
        returnsNormally,
      );
    });

    test('should handle various redirect URI formats', () {
      final configs = [
        GitHubOAuthConfig(
          clientId: 'test',
          clientSecret: 'test',
          redirectUri: 'myapp://callback',
          customUriScheme: 'myapp',
        ),
        GitHubOAuthConfig(
          clientId: 'test',
          clientSecret: 'test',
          redirectUri: 'http://localhost:3000/callback',
          customUriScheme: 'http',
        ),
        GitHubOAuthConfig(
          clientId: 'test',
          clientSecret: 'test',
          redirectUri: 'com.example.app://oauth',
          customUriScheme: 'com.example.app',
        ),
      ];

      for (final config in configs) {
        expect(config.redirectUri, isNotEmpty);
        expect(config.customUriScheme, isNotEmpty);
      }
    });
  });
}
