import 'package:from_json_to_json/from_json_to_json.dart';

import 'git_platform.dart';

/// Extension type that represents a client ID for OAuth applications.
///
/// Type-safe wrapper around OAuth client identifiers to prevent mixing
/// with other string types at compile time.
extension type const OAuthClientId(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthClientId.fromJson(final dynamic value) =>
      OAuthClientId(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  OAuthClientId whenEmptyUse(final OAuthClientId other) =>
      isEmpty ? other : this;

  static const empty = OAuthClientId('');
}

/// Extension type that represents a client secret for OAuth applications.
///
/// Type-safe wrapper around OAuth client secrets to prevent mixing
/// with other string types at compile time.
extension type const OAuthClientSecret(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthClientSecret.fromJson(final dynamic value) =>
      OAuthClientSecret(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  OAuthClientSecret whenEmptyUse(final OAuthClientSecret other) =>
      isEmpty ? other : this;

  static const empty = OAuthClientSecret('');
}

/// Extension type that represents a redirect URI for OAuth flows.
///
/// Type-safe wrapper around OAuth redirect URIs to prevent mixing
/// with other string types at compile time.
extension type const OAuthRedirectUri(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthRedirectUri.fromJson(final dynamic value) =>
      OAuthRedirectUri(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  OAuthRedirectUri whenEmptyUse(final OAuthRedirectUri other) =>
      isEmpty ? other : this;

  static const empty = OAuthRedirectUri('');
}

/// Extension type that represents a custom URI scheme for OAuth flows.
///
/// Type-safe wrapper around custom URI schemes to prevent mixing
/// with other string types at compile time.
extension type const OAuthCustomUriScheme(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthCustomUriScheme.fromJson(final dynamic value) =>
      OAuthCustomUriScheme(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  OAuthCustomUriScheme whenEmptyUse(final OAuthCustomUriScheme other) =>
      isEmpty ? other : this;

  static const empty = OAuthCustomUriScheme('');
}

/// Extension type that represents OAuth scopes list.
///
/// Type-safe wrapper around OAuth scopes with convenient methods
/// for managing scope collections.
extension type const OAuthScopes(List<String> value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthScopes.fromJson(final dynamic jsonData) {
    final list = jsonDecodeList(jsonData);
    return OAuthScopes(jsonDecodeListAs<String>(list));
  }

  /// Create scopes from individual scope strings
  factory OAuthScopes.from(final List<String> scopes) => OAuthScopes(scopes);

  List<String> toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  int get length => value.length;

  /// Check if a specific scope is included
  bool contains(final String scope) => value.contains(scope);

  /// Add a scope if not already present
  OAuthScopes addScope(final String scope) =>
      contains(scope) ? this : OAuthScopes([...value, scope]);

  /// Remove a scope if present
  OAuthScopes removeScope(final String scope) =>
      OAuthScopes(value.where((final s) => s != scope).toList());

  /// Join scopes into a space-separated string (common OAuth format)
  String get asSpaceSeparatedString => value.join(' ');

  static const empty = OAuthScopes([]);

  // Common scope sets
  static const githubDefault = OAuthScopes(['repo', 'user:email']);
  static const gitlabDefault = OAuthScopes([
    'read_user',
    'read_repository',
    'write_repository',
  ]);
  static const bitbucketDefault = OAuthScopes(['repositories', 'account']);
}

/// Extension type that represents base OAuth configuration.
///
/// Contains all necessary configuration data for OAuth authentication flows
/// across different Git platforms. Provides type-safe access to configuration
/// data with graceful handling of missing fields.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const OAuthConfig(Map<String, dynamic> value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthConfig.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return OAuthConfig(map);
  }

  /// Create GitHub OAuth configuration
  factory OAuthConfig.github({
    required final OAuthClientId clientId,
    required final OAuthClientSecret clientSecret,
    required final OAuthRedirectUri redirectUri,
    required final OAuthCustomUriScheme customUriScheme,
    final OAuthScopes? scopes,
  }) => OAuthConfig({
    'platform': GitPlatform.github.name,
    'client_id': clientId.value,
    'client_secret': clientSecret.value,
    'redirect_uri': redirectUri.value,
    'custom_uri_scheme': customUriScheme.value,
    'scopes': (scopes ?? OAuthScopes.githubDefault).value,
  });

  /// Create GitLab OAuth configuration
  factory OAuthConfig.gitlab({
    required final OAuthClientId clientId,
    required final OAuthClientSecret clientSecret,
    required final OAuthRedirectUri redirectUri,
    required final OAuthCustomUriScheme customUriScheme,
    final OAuthScopes? scopes,
  }) => OAuthConfig({
    'platform': GitPlatform.gitlab.name,
    'client_id': clientId.value,
    'client_secret': clientSecret.value,
    'redirect_uri': redirectUri.value,
    'custom_uri_scheme': customUriScheme.value,
    'scopes': (scopes ?? OAuthScopes.gitlabDefault).value,
  });

  /// Create Bitbucket OAuth configuration
  factory OAuthConfig.bitbucket({
    required final OAuthClientId clientId,
    required final OAuthClientSecret clientSecret,
    required final OAuthRedirectUri redirectUri,
    required final OAuthCustomUriScheme customUriScheme,
    final OAuthScopes? scopes,
  }) => OAuthConfig({
    'platform': GitPlatform.bitbucket.name,
    'client_id': clientId.value,
    'client_secret': clientSecret.value,
    'redirect_uri': redirectUri.value,
    'custom_uri_scheme': customUriScheme.value,
    'scopes': (scopes ?? OAuthScopes.bitbucketDefault).value,
  });

  /// Git platform for this configuration
  GitPlatform get platform {
    final platformName = jsonDecodeString(value['platform']);
    return GitPlatform.values.firstWhere(
      (final p) => p.name == platformName,
      orElse: () => GitPlatform.github,
    );
  }

  /// OAuth client ID
  OAuthClientId get clientId => OAuthClientId.fromJson(value['client_id']);

  /// OAuth client secret
  OAuthClientSecret get clientSecret =>
      OAuthClientSecret.fromJson(value['client_secret']);

  /// OAuth redirect URI
  OAuthRedirectUri get redirectUri =>
      OAuthRedirectUri.fromJson(value['redirect_uri']);

  /// Custom URI scheme for mobile deep links
  OAuthCustomUriScheme get customUriScheme =>
      OAuthCustomUriScheme.fromJson(value['custom_uri_scheme']);

  /// OAuth scopes requested
  OAuthScopes get scopes => OAuthScopes.fromJson(value['scopes']);

  /// Whether this is a GitHub configuration
  bool get isGitHub => platform == GitPlatform.github;

  /// Whether this is a GitLab configuration
  bool get isGitLab => platform == GitPlatform.gitlab;

  /// Whether this is a Bitbucket configuration
  bool get isBitbucket => platform == GitPlatform.bitbucket;

  Map<String, dynamic> toJson() => value;

  static const empty = OAuthConfig({});
}

/// GitHub-specific OAuth configuration.
///
/// Extension type that provides a convenient way to create GitHub OAuth configurations
/// with sensible defaults for GitHub-specific use cases.
extension type const GitHubOAuthConfig._(OAuthConfig config) {
  /// Create a GitHub OAuth configuration
  factory GitHubOAuthConfig({
    required final String clientId,
    required final String clientSecret,
    required final String redirectUri,
    required final String customUriScheme,
    final List<String>? scopes,
  }) => GitHubOAuthConfig._(
    OAuthConfig.github(
      clientId: OAuthClientId(clientId),
      clientSecret: OAuthClientSecret(clientSecret),
      redirectUri: OAuthRedirectUri(redirectUri),
      customUriScheme: OAuthCustomUriScheme(customUriScheme),
      scopes: scopes != null ? OAuthScopes(scopes) : null,
    ),
  );

  /// OAuth client ID
  String get clientId => config.clientId.value;

  /// OAuth client secret
  String get clientSecret => config.clientSecret.value;

  /// OAuth redirect URI
  String get redirectUri => config.redirectUri.value;

  /// Custom URI scheme for mobile deep links
  String get customUriScheme => config.customUriScheme.value;

  /// OAuth scopes requested
  List<String> get scopes => config.scopes.value;

  /// Git platform (always GitHub)
  GitPlatform get platform => config.platform;

  Map<String, dynamic> toJson() => config.toJson();
}
