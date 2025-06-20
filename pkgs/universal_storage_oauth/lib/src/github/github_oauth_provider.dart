import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:oauth2_client/github_oauth2_client.dart';

import '../exceptions/oauth_exceptions.dart';
import '../models/models.dart';
import '../providers/oauth_flow_delegate.dart';
import '../providers/oauth_provider.dart';
import '../storage/secure_credential_storage.dart';

/// GitHub OAuth implementation using delegate pattern for platform-agnostic authentication
class GitHubOAuthProvider implements OAuthProvider {
  GitHubOAuthProvider(
    this._config,
    this._delegate, [
    final CredentialStorage? storage,
  ]) : _storage = storage ?? SecureCredentialStorage();

  final GitHubOAuthConfig _config;
  final OAuthFlowDelegate _delegate;
  final CredentialStorage _storage;
  oauth2.Client? _client;

  @override
  GitPlatform get platform => GitPlatform.github;

  @override
  OAuthConfig get config => _config.config;

  @override
  Future<OAuthResult> authenticate() async {
    try {
      // Choose authentication flow based on configuration
      final credentials = _config.redirectUri.isNotEmpty
          ? await _performWebOAuthFlow()
          : await _performDeviceOAuthFlow();

      await _storage.storeCredentials(platform, credentials);

      final user = await getCurrentUser();
      if (user == null) {
        await _delegate.onAuthorizationError(
          error: 'user_info_failed',
          description: 'Failed to get user information after authentication',
        );
        throw const AuthenticationException(
          'Failed to get user information after authentication.',
        );
      }

      await _delegate.onAuthorizationSuccess(
        maskedToken: '${credentials.accessToken.value.substring(0, 8)}***',
        scopes: credentials.scopes ?? [],
      );

      return OAuthResult.success(credentials: credentials, user: user);
    } on OAuthFlowCancelledException {
      throw const AuthenticationException(
        'Authentication was cancelled by user',
      );
    } on OAuthFlowException catch (e) {
      await _delegate.onAuthorizationError(
        error: 'flow_error',
        description: e.message,
      );
      throw AuthenticationException('OAuth flow failed: ${e.message}');
    } on Exception catch (e) {
      await _delegate.onAuthorizationError(
        error: 'unknown_error',
        description: e.toString(),
      );
      throw AuthenticationException(
        'GitHub authentication failed',
        e.toString(),
      );
    }
  }

  /// Performs web-based OAuth flow using the oauth2_client package
  Future<StoredCredentials> _performWebOAuthFlow() async {
    final client = GitHubOAuth2Client(
      redirectUri: _config.redirectUri,
      customUriScheme: Uri.parse(_config.redirectUri).scheme,
    );

    final tokenResp = await client.getTokenWithAuthCodeFlow(
      clientId: _config.clientId,
      clientSecret: _config.clientSecret,
      scopes: _config.scopes,
    );

    if (tokenResp.error != null || tokenResp.accessToken == null) {
      throw AuthenticationException(
        'Token exchange failed: ${tokenResp.error ?? 'unknown error'}',
      );
    }

    return StoredCredentials.create(
      accessToken: OAuthAccessToken(tokenResp.accessToken!),
      refreshToken: tokenResp.refreshToken != null
          ? OAuthRefreshToken(tokenResp.refreshToken!)
          : null,
      expiresAt: tokenResp.expiresIn != null
          ? DateTime.now().add(Duration(seconds: tokenResp.expiresIn!))
          : null,
      scopes: tokenResp.scope,
    );
  }

  /// Performs device flow for CLI/desktop applications
  Future<StoredCredentials> _performDeviceOAuthFlow() async {
    // Step 1: Request device and user codes
    final deviceResponse = await _requestDeviceCodes();

    // Step 2: Delegate device flow UI handling
    await _delegate.handleDeviceFlow(
      deviceCode: deviceResponse['device_code'] as String,
      userCode: deviceResponse['user_code'] as String,
      verificationUrl: Uri.parse(deviceResponse['verification_uri'] as String),
      verificationUrlComplete:
          deviceResponse['verification_uri_complete'] != null
          ? Uri.parse(deviceResponse['verification_uri_complete'] as String)
          : null,
      expiresIn: deviceResponse['expires_in'] as int,
      interval: deviceResponse['interval'] as int? ?? 5,
    );

    // Step 3: Poll for access token
    return _pollForDeviceToken(
      deviceCode: deviceResponse['device_code'] as String,
      interval: deviceResponse['interval'] as int? ?? 5,
    );
  }

  /// Requests device and user codes from GitHub
  Future<Map<String, dynamic>> _requestDeviceCodes() async {
    final response = await http.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {'client_id': _config.clientId, 'scope': _config.scopes.join(' ')},
    );

    if (response.statusCode != 200) {
      throw AuthenticationException(
        'Device code request failed: HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['error'] != null) {
      throw AuthenticationException(
        'Device code request failed: '
        '${data['error_description'] ?? data['error']}',
      );
    }

    return data;
  }

  /// Polls GitHub for access token after device authorization
  Future<StoredCredentials> _pollForDeviceToken({
    required final String deviceCode,
    required final int interval,
  }) async {
    const maxAttempts = 60; // 5 minutes at 5-second intervals
    var attempts = 0;

    while (attempts < maxAttempts) {
      await Future<void>.delayed(Duration(seconds: interval));
      attempts++;

      final response = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {'Accept': 'application/json'},
        body: {
          'client_id': _config.clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      if (response.statusCode != 200) {
        throw AuthenticationException(
          'Device token polling failed: HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['access_token'] != null) {
        return StoredCredentials.create(
          accessToken: OAuthAccessToken(data['access_token'] as String),
          refreshToken: data['refresh_token'] != null
              ? OAuthRefreshToken(data['refresh_token'] as String)
              : null,
          scopes: _config.scopes,
        );
      }

      final error = data['error'] as String?;
      if (error == 'authorization_pending') {
        continue; // Keep polling
      } else if (error == 'slow_down') {
        // Increase interval as requested by GitHub
        await Future<void>.delayed(Duration(seconds: interval));
        continue;
      } else if (error == 'expired_token') {
        throw const AuthenticationException('Device code expired');
      } else if (error == 'access_denied') {
        throw const AuthenticationException('Access denied by user');
      } else {
        throw AuthenticationException(
          'Device authorization failed: ${data['error_description'] ?? error}',
        );
      }
    }

    throw const AuthenticationException('Device authorization timed out');
  }

  @override
  Future<OAuthResult> refreshToken(final String refreshToken) {
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
        return OAuthUser.fromJson(data);
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
  }

  Future<oauth2.Client?> _getAuthenticatedClient() async {
    if (_client != null) return _client;

    final credentials = await _storage.getCredentials(platform);
    if (credentials == null) return null;

    final oauth2Credentials = oauth2.Credentials(
      credentials.accessToken.value,
      refreshToken: credentials.refreshToken?.value,
      expiration: credentials.expiresAt,
      scopes: credentials.scopes,
    );

    return _client = oauth2.Client(
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
  }

  /// Get an HTTP client for making authenticated API requests
  Future<http.Client?> getHttpClient() => _getAuthenticatedClient();

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
