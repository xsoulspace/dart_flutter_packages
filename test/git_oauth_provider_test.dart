import 'package:flutter_test/flutter_test.dart';
import 'package:git_oauth_provider/git_oauth_provider.dart';

void main() {
  group('Git OAuth Provider', () {
    late OAuthConfig config;

    setUp(() {
      config = OAuthConfig.github(
        clientId: OAuthClientId('test_client_id'),
        clientSecret: OAuthClientSecret('test_client_secret'),
        redirectUri: OAuthRedirectUri('com.example.test://oauth'),
        customUriScheme: OAuthCustomUriScheme('com.example.test'),
      );
    });

    test('OAuthConfig should be created correctly', () {
      expect(config.platform, GitPlatform.github);
      expect(config.clientId.value, 'test_client_id');
      expect(config.clientSecret.value, 'test_client_secret');
      expect(config.redirectUri.value, 'com.example.test://oauth');
      expect(config.customUriScheme.value, 'com.example.test');
      expect(config.scopes.value, ['repo', 'user:email']);
    });

    test('GitHubOAuthProvider should initialize correctly', () async {
      final provider = GitHubOAuthProvider(config);
      await provider.initialize();

      expect(provider.platform, GitPlatform.github);
      expect(provider.repositoryService, isA<GitHubRepositoryService>());
      expect(provider.credentialStorage, isA<CredentialStorage>());
    });
  });

  group('Models', () {
    test('OAuthUser should handle JSON correctly', () {
      final userJson = {
        'id': '12345',
        'login': 'testuser',
        'email': 'test@example.com',
        'name': 'Test User',
        'avatar_url': 'https://avatar.example.com/test.jpg',
        'bio': 'Test bio',
        'location': 'Test Location',
        'company': 'Test Company',
        'html_url': 'https://github.com/testuser',
        'public_repos': 10,
        'followers': 5,
        'following': 3,
        'created_at': '2020-01-01T00:00:00Z',
      };

      final user = OAuthUser.fromJson(userJson);

      expect(user.id, '12345');
      expect(user.login, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.avatarUrl, 'https://avatar.example.com/test.jpg');
      expect(user.bio, 'Test bio');
      expect(user.location, 'Test Location');
      expect(user.company, 'Test Company');
      expect(user.htmlUrl, 'https://github.com/testuser');
      expect(user.publicRepos, 10);
      expect(user.followers, 5);
      expect(user.following, 3);
      expect(user.createdAt?.year, 2020);
    });

    test('StoredCredentials should handle expiration correctly', () {
      final futureDate = DateTime.now().add(Duration(hours: 1));
      final credentials = StoredCredentials.create(
        accessToken: OAuthAccessToken('test_token'),
        expiresAt: futureDate,
      );

      expect(credentials.isExpired, false);
      expect(credentials.isValid, true);
    });

    test('StoredCredentials should detect expired tokens', () {
      final pastDate = DateTime.now().subtract(Duration(hours: 1));
      final credentials = StoredCredentials.create(
        accessToken: OAuthAccessToken('test_token'),
        expiresAt: pastDate,
      );

      expect(credentials.isExpired, true);
      expect(credentials.isValid, false);
    });

    test('StoredCredentials should handle no expiration', () {
      final credentials = StoredCredentials.create(
        accessToken: OAuthAccessToken('test_token'),
      );

      expect(credentials.isExpired, false);
      expect(credentials.isValid, true);
    });

    test('StoredCredentials should handle refresh tokens', () {
      final credentials = StoredCredentials.create(
        accessToken: OAuthAccessToken('test_token'),
        refreshToken: OAuthRefreshToken('refresh_token'),
        expiresAt: DateTime.now().add(Duration(hours: 1)),
        scopes: ['repo', 'user:email'],
      );

      expect(credentials.hasRefreshToken, true);
      expect(credentials.hasExpiration, true);
      expect(credentials.hasScopes, true);
      expect(credentials.scopeCount, 2);
      expect(credentials.containsScope('repo'), true);
      expect(credentials.containsScope('invalid'), false);
    });
  });
}
