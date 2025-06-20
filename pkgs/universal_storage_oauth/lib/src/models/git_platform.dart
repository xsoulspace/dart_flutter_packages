enum GitPlatform {
  github('GitHub', 'https://api.github.com', 'https://github.com'),
  gitlab('GitLab', 'https://gitlab.com/api/v4', 'https://gitlab.com'),
  bitbucket(
    'Bitbucket',
    'https://api.bitbucket.org/2.0',
    'https://bitbucket.org',
  );

  const GitPlatform(this.displayName, this.apiBaseUrl, this.webUrl);

  final String displayName;
  final String apiBaseUrl;
  final String webUrl;

  /// Get OAuth authorization URL for this platform
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
