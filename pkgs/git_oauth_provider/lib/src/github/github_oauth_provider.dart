import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:oauth2_client/github_oauth2_client.dart';

import '../exceptions/oauth_exceptions.dart';
import '../models/models.dart';
import '../providers/oauth_provider.dart';
import '../storage/credential_storage.dart';
import '../storage/secure_credential_storage.dart';

/// GitHub OAuth implementation using oauth2_client
class GitHubOAuthProvider implements OAuthProvider {
  GitHubOAuthProvider(this._config, [final CredentialStorage? storage])
    : _storage = storage ?? SecureCredentialStorage();

  final GitHubOAuthConfig _config;
  final CredentialStorage _storage;
  oauth2.Client? _client;

  @override
  GitPlatform get platform => GitPlatform.github;

  @override
  OAuthConfig get config => _config;

  @override
  Future<OAuthResult> authenticate() async {
    try {
      final ghClient = GitHubOAuth2Client(
        redirectUri: _config.redirectUri,
        customUriScheme: _config.customUriScheme,
      );

      final tokenResponse = await ghClient.getTokenWithAuthCodeFlow(
        clientId: _config.clientId,
        clientSecret: _config.clientSecret,
        scopes: _config.scopes,
      );

      if (tokenResponse.accessToken == null) {
        throw const AuthenticationException(
          'Authentication failed: No access token received.',
        );
      }

      final credentials = StoredCredentials(
        accessToken: tokenResponse.accessToken!,
        refreshToken: tokenResponse.refreshToken,
        expiresAt: tokenResponse.expirationDate,
        scopes: _config.scopes,
      );

      await _storage.storeCredentials(platform, credentials);

      final user = await getCurrentUser();

      return OAuthResult(credentials: credentials, user: user);
    } on Exception catch (e) {
      throw AuthenticationException(
        'GitHub authentication failed',
        e.toString(),
      );
    }
  }

  @override
  Future<OAuthResult> refreshToken(final String refreshToken) async {
    // GitHub tokens don't expire by default, but this could be implemented
    // if the token has an expiration and refresh capability
    throw const AuthenticationException(
      'GitHub tokens do not support refresh by default',
    );
  }

  @override
  Future<bool> isAuthenticated() async {
    final credentials = await _storage.getCredentials(platform);
    return credentials != null &&
        credentials.accessToken.isNotEmpty &&
        !credentials.isExpired;
  }

  @override
  Future<void> signOut() async {
    await _storage.clearCredentials(platform);
    _client?.close();
    _client = null;
  }

  @override
  Future<OAuthUser?> getCurrentUser() async {
    final client = await _getAuthenticatedClient();
    if (client == null) return null;

    try {
      final response = await client.get(
        Uri.parse('${platform.apiBaseUrl}/user'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return OAuthUser(
          id: data['id'].toString(),
          login: data['login'] as String,
          email: data['email'] as String?,
          name: data['name'] as String?,
          avatarUrl: data['avatar_url'] as String?,
          bio: data['bio'] as String?,
          location: data['location'] as String?,
          company: data['company'] as String?,
          htmlUrl: data['html_url'] as String?,
          publicRepos: data['public_repos'] as int?,
          followers: data['followers'] as int?,
          following: data['following'] as int?,
          createdAt: data['created_at'] != null
              ? DateTime.parse(data['created_at'] as String)
              : null,
        );
      } else if (response.statusCode == 401) {
        throw const ApiException.unauthorized();
      } else {
        throw ApiException(
          'Failed to get user information',
          'HTTP ${response.statusCode}',
        );
      }
    } on Exception catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get user information', e.toString());
    }
    return null;
  }

  Future<oauth2.Client?> _getAuthenticatedClient() async {
    if (_client != null) return _client;

    final credentials = await _storage.getCredentials(platform);
    if (credentials == null) return null;

    final oauth2Credentials = oauth2.Credentials(
      credentials.accessToken,
      refreshToken: credentials.refreshToken,
      expiration: credentials.expiresAt,
      scopes: credentials.scopes,
    );

    _client = oauth2.Client(
      oauth2Credentials,
      identifier: _config.clientId,
      secret: _config.clientSecret,
      onCredentialsRefreshed: (final newCreds) async {
        await _storage.storeCredentials(
          platform,
          StoredCredentials.fromOauth2Credentials(newCreds),
        );
      },
    );

    return _client;
  }

  /// Get an HTTP client for making authenticated API requests
  Future<http.Client?> getHttpClient() async => _getAuthenticatedClient();

  /// Test the current authentication by trying to fetch user info
  Future<bool> testAuthentication() async {
    try {
      final user = await getCurrentUser();
      return user != null;
    } catch (e) {
      return false;
    }
  }
}
