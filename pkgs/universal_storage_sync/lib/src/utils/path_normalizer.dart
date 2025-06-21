/// {@template provider_type}
/// Enumeration of supported storage provider types.
/// {@endtemplate}
enum ProviderType {
  /// Local filesystem provider
  filesystem,

  /// GitHub API provider
  github,

  /// Offline Git provider
  git,
}

/// {@template path_normalizer}
/// Utility class for normalizing file paths across different storage providers.
/// Each provider may have different path requirements and conventions.
/// {@endtemplate}
mixin PathNormalizer {
  /// Normalizes a path for the specified provider type
  static String normalize(final String path, final ProviderType providerType) {
    if (path.isEmpty) return path;

    switch (providerType) {
      case ProviderType.filesystem:
        return _normalizeFilesystemPath(path);
      case ProviderType.github:
        return _normalizeGitHubPath(path);
      case ProviderType.git:
        return _normalizeGitPath(path);
    }
  }

  /// Normalizes paths for filesystem operations
  // Convert forward slashes to platform-specific separators
  // Remove redundant separators and resolve relative paths
  static String _normalizeFilesystemPath(final String path) => path
      .replaceAll(RegExp(r'[/\\]+'), _platformSeparator)
      .replaceAll(RegExp(r'^[/\\]+'), '') // Remove leading separators
      .replaceAll(RegExp(r'[/\\]+$'), ''); // Remove trailing separators

  /// Normalizes paths for GitHub API operations
  // GitHub API always uses forward slashes
  // Remove leading/trailing slashes and resolve relative paths
  static String _normalizeGitHubPath(final String path) => path
      .replaceAll(RegExp(r'\\+'), '/') // Convert backslashes to forward slashes
      .replaceAll(RegExp('/+'), '/') // Remove duplicate slashes
      .replaceAll(RegExp('^/+'), '') // Remove leading slashes
      .replaceAll(RegExp(r'/+$'), ''); // Remove trailing slashes

  /// Normalizes paths for Git operations
  // Git uses forward slashes regardless of platform
  static String _normalizeGitPath(final String path) => path
      .replaceAll(RegExp(r'\\+'), '/') // Convert backslashes to forward slashes
      .replaceAll(RegExp('/+'), '/') // Remove duplicate slashes
      .replaceAll(RegExp('^/+'), '') // Remove leading slashes
      .replaceAll(RegExp(r'/+$'), ''); // Remove trailing slashes

  /// Gets the platform-specific path separator
  // This is a simplified version - in real implementation,
  // you'd use dart:io's Platform.pathSeparator
  static String get _platformSeparator =>
      '/'; // Default to forward slash for cross-platform compatibility

  /// Validates if a path is safe for the given provider
  static bool isSafePath(final String path, final ProviderType providerType) {
    if (path.isEmpty) return false;

    // Check for dangerous path patterns
    if (path.contains('..') || // Parent directory traversal
        path.contains('//') || // Double slashes
        path.contains(r'\\') || // Double backslashes
        path.startsWith('/') &&
            providerType ==
                ProviderType.github || // Absolute paths not allowed in GitHub
        path.contains(RegExp('[<>:"|?*]'))) {
      // Invalid characters
      return false;
    }

    // Provider-specific validation
    switch (providerType) {
      case ProviderType.github:
        return _isValidGitHubPath(path);
      case ProviderType.filesystem:
        return _isValidFilesystemPath(path);
      case ProviderType.git:
        return _isValidGitPath(path);
    }
  }

  /// Validates GitHub API path requirements
  // GitHub has specific requirements for file paths
  static bool _isValidGitHubPath(final String path) =>
      path.length <= 255 && // Max path length
      !path.startsWith('.') && // No hidden files at root
      !path.endsWith('.') && // No paths ending with dot
      !path.contains(RegExp(r'[<>:"|?*\x00-\x1f]')); // No control characters

  /// Validates filesystem path requirements
  // Basic filesystem validation
  static bool _isValidFilesystemPath(final String path) =>
      path.length <= 260 && // Windows MAX_PATH limit
      !path.contains(RegExp(r'[<>:"|?*\x00-\x1f]')); // No invalid characters

  /// Validates Git path requirements
  // Git path validation
  static bool _isValidGitPath(final String path) =>
      path.length <= 255 && // Max path length
          !path.contains(
            RegExp(r'[<>:"|?*\x00-\x1f]'),
          ) && // No control characters
          !path.contains(' ') || // Prefer no spaces or properly escaped
      path.contains(RegExp(r'^[a-zA-Z0-9._/-]+$')); // Only safe characters

  /// Joins path segments with the appropriate separator for the provider
  static String join(
    final List<String> segments,
    final ProviderType providerType,
  ) {
    if (segments.isEmpty) return '';

    final separator = providerType == ProviderType.filesystem
        ? _platformSeparator
        : '/';

    return segments
        .where((final segment) => segment.isNotEmpty)
        .map((final segment) => normalize(segment, providerType))
        .join(separator);
  }

  /// Splits a path into its component segments
  static List<String> split(
    final String path,
    final ProviderType providerType,
  ) {
    final normalizedPath = normalize(path, providerType);
    if (normalizedPath.isEmpty) return [];

    return normalizedPath
        .split(RegExp(r'[/\\]'))
        .where((final segment) => segment.isNotEmpty)
        .toList();
  }
}
