import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:github/github.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:oauth2_client/oauth2_client.dart';

import '../exceptions/oauth_exceptions.dart';
import '../models/models.dart';
import '../providers/oauth_provider.dart';
import '../storage/storage.dart';
import 'github_repository_service.dart';

/// GitHub-specific OAuth provider implementation
class GitHubOAuthProvider implements OAuthProvider {
  GitHubOAuthProvider(this._config);

  final OAuthConfig _config;
  late final GitHubRepositoryService _repositoryService;
  late final CredentialStorage _credentialStorage;

  @override
  GitPlatform get platform => GitPlatform.github;

  @override
  GitHubRepositoryService get repositoryService => _repositoryService;

  @override
  CredentialStorage get credentialStorage => _credentialStorage;

  @override
  Future<void> initialize() async {
    _credentialStorage = SecureCredentialStorage();
    _repositoryService = GitHubRepositoryService();
  }

  @override
  Future<OAuthResult> authenticate() async {
    try {
      final client = OAuth2Client(
        redirection_url: _config.redirectUri.value,
        custom_uri_scheme: _config.customUriScheme.value,
      );

      final oauth2Client = await client.getAccessTokenWithAuthCodeFlow(
        client_id: _config.clientId.value,
        client_secret: _config.clientSecret.value,
        scope: _config.scopes.value,
        auth_url: platform.authUrl,
        token_url: platform.tokenUrl,
      );

      final credentials = StoredCredentials.create(
        accessToken: OAuthAccessToken(oauth2Client.accessToken),
        refreshToken: oauth2Client.refreshToken != null
            ? OAuthRefreshToken(oauth2Client.refreshToken!)
            : null,
        expiresAt: oauth2Client.expirationDate,
        scopes: _config.scopes.value,
      );

      // Store credentials
      await _credentialStorage.storeCredentials(platform, credentials);

      // Fetch user info
      final user = await _fetchUserInfo(credentials.accessToken);

      return OAuthResult.success(credentials: credentials, user: user);
    } catch (e) {
      if (e is OAuthClientException) {
        return OAuthResult.failure(error: OAuthError(e.message));
      }
      return OAuthResult.failure(
        error: OAuthError('Authentication failed: $e'),
      );
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    try {
      final credentials = await _credentialStorage.getCredentials(platform);
      return credentials?.isValid ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    await _credentialStorage.clearCredentials(platform);
  }

  @override
  Future<OAuthUser?> getCurrentUser() async {
    try {
      final credentials = await _credentialStorage.getCredentials(platform);
      if (credentials == null || !credentials.isValid) {
        return null;
      }
      return await _fetchUserInfo(credentials.accessToken);
    } catch (e) {
      return null;
    }
  }

  Future<OAuthUser?> _fetchUserInfo(OAuthAccessToken accessToken) async {
    try {
      final github = GitHub(auth: Authentication.withToken(accessToken.value));
      final user = await github.users.getCurrentUser();

      return OAuthUser.fromJson({
        'id': user.id.toString(),
        'login': user.login ?? '',
        'email': user.email ?? '',
        'name': user.name ?? '',
        'avatar_url': user.avatarUrl ?? '',
        'bio': user.bio ?? '',
        'location': user.location ?? '',
        'company': user.company ?? '',
        'html_url': user.htmlUrl ?? '',
        'public_repos': user.publicReposCount ?? 0,
        'followers': user.followersCount ?? 0,
        'following': user.followingCount ?? 0,
        'created_at': user.createdAt?.toIso8601String() ?? '',
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to fetch user info: $e');
      }
      return null;
    }
  }

  @override
  Future<StoredCredentials?> refreshToken() async {
    try {
      final credentials = await _credentialStorage.getCredentials(platform);
      if (credentials == null || !credentials.hasRefreshToken) {
        return null;
      }

      final oauth2Credentials = oauth2.Credentials(
        credentials.accessToken.value,
        refreshToken: credentials.refreshToken?.value,
        idToken: null,
        tokenEndpoint: Uri.parse(platform.tokenUrl),
        scopes: credentials.scopes,
        expiration: credentials.expiresAt,
      );

      final refreshedCredentials = await oauth2Credentials.refresh(
        identifier: _config.clientId.value,
        secret: _config.clientSecret.value,
      );

      final newCredentials = StoredCredentials.fromOauth2Credentials(
        refreshedCredentials,
      );
      await _credentialStorage.storeCredentials(platform, newCredentials);

      return newCredentials;
    } catch (e) {
      throw OAuthException('Failed to refresh token: $e');
    }
  }
}
