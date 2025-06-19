import 'git_platform.dart';

/// Base OAuth configuration
abstract class OAuthConfig {
  const OAuthConfig({
    required this.platform,
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    required this.scopes,
  });

  final GitPlatform platform;
  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final List<String> scopes;
}

/// GitHub-specific OAuth configuration
class GitHubOAuthConfig extends OAuthConfig {
  const GitHubOAuthConfig({
    required super.clientId,
    required super.clientSecret,
    required super.redirectUri,
    required this.customUriScheme,
    super.scopes = const ['repo', 'user:email'],
  }) : super(platform: GitPlatform.github);

  final String customUriScheme;

  @override
  String toString() =>
      'GitHubOAuthConfig(clientId: $clientId, redirectUri: $redirectUri, scopes: $scopes)';
}

/// GitLab-specific OAuth configuration
class GitLabOAuthConfig extends OAuthConfig {
  const GitLabOAuthConfig({
    required super.clientId,
    required super.clientSecret,
    required super.redirectUri,
    required this.customUriScheme,
    super.scopes = const ['read_user', 'read_repository', 'write_repository'],
  }) : super(platform: GitPlatform.gitlab);

  final String customUriScheme;

  @override
  String toString() =>
      'GitLabOAuthConfig(clientId: $clientId, redirectUri: $redirectUri, scopes: $scopes)';
}

/// Bitbucket-specific OAuth configuration
class BitbucketOAuthConfig extends OAuthConfig {
  const BitbucketOAuthConfig({
    required super.clientId,
    required super.clientSecret,
    required super.redirectUri,
    required this.customUriScheme,
    super.scopes = const ['repositories', 'account'],
  }) : super(platform: GitPlatform.bitbucket);

  final String customUriScheme;

  @override
  String toString() =>
      'BitbucketOAuthConfig(clientId: $clientId, redirectUri: $redirectUri, scopes: $scopes)';
}
