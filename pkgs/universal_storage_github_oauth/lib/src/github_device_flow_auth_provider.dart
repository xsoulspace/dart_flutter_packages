import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:universal_storage_oauth/universal_storage_oauth.dart';

/// Configuration for [GithubDeviceFlowAuthProvider].
@immutable
final class GithubDeviceFlowConfig {
  const GithubDeviceFlowConfig({
    required this.clientId,
    this.scopes = const ['repo'],
    this.deviceCodeUrl = defaultDeviceCodeUrl,
    this.tokenUrl = defaultTokenUrl,
    this.apiBaseUrl = defaultApiBaseUrl,
  });

  /// GitHub App / OAuth App client ID. No client secret is needed for the
  /// device flow; "Enable Device Flow" must be checked in the app settings.
  final String clientId;

  /// OAuth scopes to request (GitHub Apps derive permissions from the app
  /// configuration instead — pass an empty list for fine-grained apps).
  final List<String> scopes;

  /// Device-code request endpoint. Override for web proxies.
  final String deviceCodeUrl;
  /// Token polling endpoint. Override for web proxies.
  final String tokenUrl;
  /// REST API base URL. Override for web proxies or GHES.
  final String apiBaseUrl;

  static const defaultDeviceCodeUrl =
      'https://github.com/login/device/code';
  static const defaultTokenUrl = 'https://github.com/login/oauth/access_token';
  static const defaultApiBaseUrl = 'https://api.github.com';
}

/// {@template github_device_flow_auth_provider}
/// GitHub OAuth provider using the OAuth Device Flow exclusively.
///
/// The device flow works uniformly across Android, iOS, macOS, Linux and
/// Windows: the app opens `https://github.com/login/device`, shows a
/// one-time code, and polls for the token. No deep links, loopback
/// servers, or client secret are involved.
///
/// On web, `github.com/login/*` does not send CORS headers — host
/// [config]'s URLs behind a small proxy and override [GithubDeviceFlowConfig.tokenUrl]
/// / [deviceCodeUrl] accordingly.
/// {@endtemplate}
class GithubDeviceFlowAuthProvider implements OAuthProvider {
  /// {@macro github_device_flow_auth_provider}
  GithubDeviceFlowAuthProvider({
    required this.config,
    required OAuthFlowDelegate delegate,
    CredentialStorage? storage,
    http.Client? httpClient,
  }) : _delegate = delegate,
       _storage = storage ?? SecureCredentialStorage(),
       _httpClient = httpClient ?? http.Client();

  /// Provider configuration.
  final GithubDeviceFlowConfig flowConfig;

  final OAuthFlowDelegate _delegate;
  final CredentialStorage _storage;
  final http.Client _httpClient;

  @override
  GitPlatform get platform => GitPlatform.github;

  @override
  OAuthConfig get config => OAuthConfig.github(
    clientId: OAuthClientId(this.flowConfig.clientId),
    clientSecret: OAuthClientSecret.empty,
    redirectUri: OAuthRedirectUri.empty,
    customUriScheme: OAuthCustomUriScheme.empty,
    scopes: OAuthScopes(flowConfig.scopes),
  );

  @override
  Future<OAuthResult> authenticate() async {
    try {
      final credentials = await _runDeviceFlow();
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
        scopes: credentials.scopes ?? <String>[],
      );
      return OAuthResult.success(credentials: credentials, user: user);
    } on OAuthFlowCancelledException {
      throw const AuthenticationException('Authentication was cancelled by user');
    } on OAuthFlowException catch (e) {
      await _delegate.onAuthorizationError(error: 'flow_error', description: e.message);
      throw AuthenticationException('OAuth flow failed: ${e.message}');
    } on Exception catch (e) {
      await _delegate.onAuthorizationError(error: 'unknown_error', description: '$e');
      throw AuthenticationException('GitHub authentication failed', '$e');
    }
  }

  Future<StoredCredentials> _runDeviceFlow() async {
    // Step 1: request device + user codes.
    final deviceResponse = await _requestDeviceCodes();

    // Step 2: delegate UI (show code, open browser, wait for user).
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

    // Step 3: poll for the access token.
    return _pollForToken(
      deviceCode: deviceResponse['device_code'] as String,
      interval: deviceResponse['interval'] as int? ?? 5,
    );
  }

  Future<Map<String, dynamic>> _requestDeviceCodes() async {
    final response = await _httpClient.post(
      Uri.parse(flowConfig.deviceCodeUrl),
      headers: {'Accept': 'application/json'},
      body: {'client_id': flowConfig.clientId, 'scope': flowConfig.scopes.join(' ')},
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

  Future<StoredCredentials> _pollForToken({
    required final String deviceCode,
    required final int interval,
  }) async {
    var currentInterval = interval;
    // Generous cap: device codes expire in ~15 minutes.
    final deadline = DateTime.now().add(const Duration(minutes: 16));

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: currentInterval));

      final response = await _httpClient.post(
        Uri.parse(flowConfig.tokenUrl),
        headers: {'Accept': 'application/json'},
        body: {
          'client_id': flowConfig.clientId,
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
          scopes: flowConfig.scopes,
        );
      }

      switch (data['error'] as String?) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          // RFC 8628: add 5 seconds to the polling interval.
          currentInterval += 5;
          continue;
        case 'expired_token':
          throw const AuthenticationException('Device code expired');
        case 'access_denied':
          throw const AuthenticationException('Access denied by user');
        case null:
          throw AuthenticationException(
            'Device authorization failed: unexpected response',
          );
        default:
          throw AuthenticationException(
            'Device authorization failed: '
            '${data['error_description'] ?? data['error']}',
          );
      }
    }

    throw const AuthenticationException('Device authorization timed out');
  }

  @override
  Future<bool> isAuthenticated() async {
    final credentials = await _storage.getCredentials(platform);
    return credentials != null &&
        credentials.accessToken.isNotEmpty &&
        !credentials.isExpired;
  }

  @override
  Future<void> signOut() => _storage.clearCredentials(platform);

  @override
  Future<OAuthUser?> getCurrentUser() async {
    final credentials = await getStoredCredentials();
    if (credentials == null || credentials.accessToken.isEmpty) return null;

    try {
      final response = await _httpClient.get(
        Uri.parse('${flowConfig.apiBaseUrl}/user'),
        headers: {
          'Authorization': 'Bearer ${credentials.accessToken.value}',
          'Accept': 'application/vnd.github+json',
        },
      );
      if (response.statusCode == 200) {
        return OAuthUser.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } else if (response.statusCode == 401) {
        throw const ApiException.unauthorized();
      }
      throw ApiException('Failed to get user information', 'HTTP ${response.statusCode}');
    } on Exception catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get user information', '$e');
    }
  }

  /// Returns the stored credentials, or `null` when signed out.
  Future<StoredCredentials?> getStoredCredentials() =>
      _storage.getCredentials(platform);
}
