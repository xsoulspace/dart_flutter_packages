import 'package:from_json_to_json/from_json_to_json.dart';

import 'git_platform.dart';

/// Extension type that represents a client ID for OAuth applications.
///
/// Type-safe wrapper around OAuth client identifiers to prevent mixing
/// with other string types at compile time.
extension type const OAuthClientId(String value) {
  /// Creates an [OAuthClientId] from JSON data.
  ///
  /// Uses type-safe JSON decoding to handle dynamic input safely.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthClientId.fromJson(final dynamic value) =>
      OAuthClientId(jsonDecodeString(value));

  /// Converts this [OAuthClientId] to JSON.
  ///
  /// Returns the underlying string value directly.
  String toJson() => value;

  /// Whether this client ID is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this client ID is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns [other] if this client ID is empty, otherwise returns this.
  ///
  /// Useful for providing fallback values when the current client ID is empty.
  OAuthClientId whenEmptyUse(final OAuthClientId other) =>
      isEmpty ? other : this;

  /// An empty client ID instance.
  static const empty = OAuthClientId('');
}

/// Extension type that represents a client secret for OAuth applications.
///
/// Type-safe wrapper around OAuth client secrets to prevent mixing
/// with other string types at compile time.
extension type const OAuthClientSecret(String value) {
  /// Creates an [OAuthClientSecret] from JSON data.
  ///
  /// Uses type-safe JSON decoding to handle dynamic input safely.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthClientSecret.fromJson(final dynamic value) =>
      OAuthClientSecret(jsonDecodeString(value));

  /// Converts this [OAuthClientSecret] to JSON.
  ///
  /// Returns the underlying string value directly.
  String toJson() => value;

  /// Whether this client secret is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this client secret is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns [other] if this client secret is empty, otherwise returns this.
  ///
  /// Useful for providing fallback values when the current
  /// client secret is empty.
  OAuthClientSecret whenEmptyUse(final OAuthClientSecret other) =>
      isEmpty ? other : this;

  /// An empty client secret instance.
  static const empty = OAuthClientSecret('');
}

/// Extension type that represents a redirect URI for OAuth flows.
///
/// Type-safe wrapper around OAuth redirect URIs to prevent mixing
/// with other string types at compile time.
extension type const OAuthRedirectUri(String value) {
  /// Creates an [OAuthRedirectUri] from JSON data.
  ///
  /// Uses type-safe JSON decoding to handle dynamic input safely.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthRedirectUri.fromJson(final dynamic value) =>
      OAuthRedirectUri(jsonDecodeString(value));

  /// Converts this [OAuthRedirectUri] to JSON.
  ///
  /// Returns the underlying string value directly.
  String toJson() => value;

  /// Whether this redirect URI is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this redirect URI is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns [other] if this redirect URI is empty, otherwise returns this.
  ///
  /// Useful for providing fallback values when the current
  /// redirect URI is empty.
  OAuthRedirectUri whenEmptyUse(final OAuthRedirectUri other) =>
      isEmpty ? other : this;

  /// An empty redirect URI instance.
  static const empty = OAuthRedirectUri('');
}

/// Extension type that represents a custom URI scheme for OAuth flows.
///
/// Type-safe wrapper around custom URI schemes to prevent mixing
/// with other string types at compile time.
extension type const OAuthCustomUriScheme(String value) {
  /// Creates an [OAuthCustomUriScheme] from JSON data.
  ///
  /// Uses type-safe JSON decoding to handle dynamic input safely.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthCustomUriScheme.fromJson(final dynamic value) =>
      OAuthCustomUriScheme(jsonDecodeString(value));

  /// Converts this [OAuthCustomUriScheme] to JSON.
  ///
  /// Returns the underlying string value directly.
  String toJson() => value;

  /// Whether this custom URI scheme is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this custom URI scheme is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns [other] if this custom URI scheme is empty,
  /// otherwise returns this.
  ///
  /// Useful for providing fallback values when the current
  /// custom URI scheme is empty.
  OAuthCustomUriScheme whenEmptyUse(final OAuthCustomUriScheme other) =>
      isEmpty ? other : this;

  /// An empty custom URI scheme instance.
  static const empty = OAuthCustomUriScheme('');
}

/// Extension type that represents OAuth scopes list.
///
/// Type-safe wrapper around OAuth scopes with convenient methods
/// for managing scope collections.
extension type const OAuthScopes(List<String> value) {
  /// Creates [OAuthScopes] from JSON data.
  ///
  /// Expects a list of strings and uses type-safe JSON decoding.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthScopes.fromJson(final dynamic jsonData) {
    final list = jsonDecodeList(jsonData);
    return OAuthScopes(jsonDecodeListAs<String>(list));
  }

  /// Creates [OAuthScopes] from a list of scope strings.
  ///
  /// Convenient factory for creating scopes from an existing list.
  factory OAuthScopes.from(final List<String> scopes) => OAuthScopes(scopes);

  /// Converts this [OAuthScopes] to JSON.
  ///
  /// Returns the underlying list of strings directly.
  List<String> toJson() => value;

  /// Whether this scopes list is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this scopes list is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// The number of scopes in this list.
  int get length => value.length;

  /// Checks if a specific scope is included in this list.
  ///
  /// Returns true if [scope] is present in the scopes list.
  bool contains(final String scope) => value.contains(scope);

  /// Adds a scope if not already present.
  ///
  /// Returns a new [OAuthScopes] instance with the scope added,
  /// or this instance if the scope was already present.
  OAuthScopes addScope(final String scope) =>
      contains(scope) ? this : OAuthScopes([...value, scope]);

  /// Removes a scope if present.
  ///
  /// Returns a new [OAuthScopes] instance with the scope removed,
  /// or this instance if the scope was not present.
  OAuthScopes removeScope(final String scope) =>
      OAuthScopes(value.where((final s) => s != scope).toList());

  /// Joins scopes into a space-separated string.
  ///
  /// This is the common format used in OAuth authorization requests.
  String get asSpaceSeparatedString => value.join(' ');

  /// An empty scopes instance.
  static const empty = OAuthScopes([]);

  /// Default scopes for GitHub OAuth applications.
  ///
  /// Includes 'repo' and 'user:email' scopes which are commonly needed
  /// for GitHub API access.
  static const githubDefault = OAuthScopes(['repo', 'user:email']);

  /// Default scopes for GitLab OAuth applications.
  ///
  /// Includes read and write repository access along with user read access.
  static const gitlabDefault = OAuthScopes([
    'read_user',
    'read_repository',
    'write_repository',
  ]);

  /// Default scopes for Bitbucket OAuth applications.
  ///
  /// Includes repository and account access scopes.
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
  /// Creates an [OAuthConfig] from JSON data.
  ///
  /// Expects a map containing OAuth configuration fields and uses
  /// type-safe JSON decoding for all fields.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthConfig.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return OAuthConfig(map);
  }

  /// Creates a GitHub-specific OAuth configuration.
  ///
  /// All parameters are required except [scopes], which defaults to
  /// [OAuthScopes.githubDefault] if not provided.
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

  /// {@macro gitlab_oauth_config}
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

  /// {@macro bitbucket_oauth_config}
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

  /// Converts this [OAuthConfig] to JSON.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => value;

  /// An empty OAuth configuration instance.
  static const empty = OAuthConfig({});
}

/// GitHub-specific OAuth configuration.
///
/// Extension type that provides a convenient way to create GitHub OAuth
/// configurations with sensible defaults for GitHub-specific use cases.
extension type const GitHubOAuthConfig._(OAuthConfig config) {
  /// Creates a GitHub-specific OAuth configuration.
  ///
  /// All parameters are required except [scopes], which defaults to
  /// [OAuthScopes.githubDefault] if not provided.
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

  /// The OAuth client ID.
  String get clientId => config.clientId.value;

  /// The OAuth client secret.
  String get clientSecret => config.clientSecret.value;

  /// OAuth redirect URI
  String get redirectUri => config.redirectUri.value;

  /// Custom URI scheme for mobile deep links
  String get customUriScheme => config.customUriScheme.value;

  /// OAuth scopes requested
  List<String> get scopes => config.scopes.value;

  /// Git platform (always GitHub)
  GitPlatform get platform => config.platform;

  /// Converts this [GitHubOAuthConfig] to JSON.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => config.toJson();
}
