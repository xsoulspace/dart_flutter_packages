/// Supported Git hosting platforms for OAuth authentication
enum GitPlatform {
  /// GitHub - The world's leading software development platform
  ///
  /// API Base: https://api.github.com
  /// Web URL: https://github.com
  github('GitHub', 'https://api.github.com', 'https://github.com'),

  /// GitLab - Complete DevOps platform delivered as a single application
  ///
  /// API Base: https://gitlab.com/api/v4
  /// Web URL: https://gitlab.com
  gitlab('GitLab', 'https://gitlab.com/api/v4', 'https://gitlab.com'),

  /// Bitbucket - Git code hosting solution for teams using Mercurial,
  /// Git or SVN
  ///
  /// API Base: https://api.bitbucket.org/2.0
  /// Web URL: https://bitbucket.org
  bitbucket(
    'Bitbucket',
    'https://api.bitbucket.org/2.0',
    'https://bitbucket.org',
  );

  /// Creates a new GitPlatform instance
  ///
  /// [displayName] - Human-readable name for the platform
  /// [apiBaseUrl] - Base URL for the platform's REST API
  /// [webUrl] - Base URL for the platform's web interface
  const GitPlatform(this.displayName, this.apiBaseUrl, this.webUrl);

  /// Human-readable display name for the platform
  final String displayName;

  /// Base URL for the platform's REST API endpoints
  final String apiBaseUrl;

  /// Base URL for the platform's web interface
  final String webUrl;

  /// Get OAuth authorization URL for this platform
  ///
  /// Returns the URL where users are redirected to authorize the application
  /// and grant access to their account.
  String get authUrl {
    switch (this) {
      case GitPlatform.github:
        return 'https://github.com/login/oauth/authorize';
      case GitPlatform.gitlab:
        return 'https://gitlab.com/oauth/authorize';
      case GitPlatform.bitbucket:
        return 'https://bitbucket.org/site/oauth2/authorize';
    }
  }

  /// Get OAuth token URL for this platform
  ///
  /// Returns the URL where the application exchanges authorization codes
  /// for access tokens during the OAuth flow.
  String get tokenUrl {
    switch (this) {
      case GitPlatform.github:
        return 'https://github.com/login/oauth/access_token';
      case GitPlatform.gitlab:
        return 'https://gitlab.com/oauth/token';
      case GitPlatform.bitbucket:
        return 'https://bitbucket.org/site/oauth2/access_token';
    }
  }
}
