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
class PathNormalizer {
  /// {@macro path_normalizer}
  const PathNormalizer();

  /// Normalizes a path for the specified provider type
  static String normalize(String path, ProviderType providerType) {
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
  static String _normalizeFilesystemPath(String path) {
    // Convert forward slashes to platform-specific separators
    // Remove redundant separators and resolve relative paths
    return path
        .replaceAll(RegExp(r'[/\\]+'), _platformSeparator)
        .replaceAll(RegExp(r'^[/\\]+'), '') // Remove leading separators
        .replaceAll(RegExp(r'[/\\]+$'), ''); // Remove trailing separators
  }

  /// Normalizes paths for GitHub API operations
  static String _normalizeGitHubPath(String path) {
    // GitHub API always uses forward slashes
    // Remove leading/trailing slashes and resolve relative paths
    return path
        .replaceAll(
            RegExp(r'\\+'), '/') // Convert backslashes to forward slashes
        .replaceAll(RegExp('/+'), '/') // Remove duplicate slashes
        .replaceAll(RegExp('^/+'), '') // Remove leading slashes
        .replaceAll(RegExp(r'/+$'), ''); // Remove trailing slashes
  }

  /// Normalizes paths for Git operations
  static String _normalizeGitPath(String path) {
    // Git uses forward slashes regardless of platform
    return path
        .replaceAll(
            RegExp(r'\\+'), '/') // Convert backslashes to forward slashes
        .replaceAll(RegExp('/+'), '/') // Remove duplicate slashes
        .replaceAll(RegExp('^/+'), '') // Remove leading slashes
        .replaceAll(RegExp(r'/+$'), ''); // Remove trailing slashes
  }

  /// Gets the platform-specific path separator
  static String get _platformSeparator {
    // This is a simplified version - in real implementation,
    // you'd use dart:io's Platform.pathSeparator
    return '/'; // Default to forward slash for cross-platform compatibility
  }

  /// Validates if a path is safe for the given provider
  static bool isSafePath(String path, ProviderType providerType) {
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
  static bool _isValidGitHubPath(String path) {
    // GitHub has specific requirements for file paths
    return path.length <= 255 && // Max path length
        !path.startsWith('.') && // No hidden files at root
        !path.endsWith('.') && // No paths ending with dot
        !path.contains(RegExp(r'[<>:"|?*\x00-\x1f]')); // No control characters
  }

  /// Validates filesystem path requirements
  static bool _isValidFilesystemPath(String path) {
    // Basic filesystem validation
    return path.length <= 260 && // Windows MAX_PATH limit
        !path.contains(RegExp(r'[<>:"|?*\x00-\x1f]')); // No invalid characters
  }

  /// Validates Git path requirements
  static bool _isValidGitPath(String path) {
    // Git path validation
    return path.length <= 255 && // Max path length
            !path.contains(
                RegExp(r'[<>:"|?*\x00-\x1f]')) && // No control characters
            !path.contains(' ') || // Prefer no spaces or properly escaped
        path.contains(RegExp(r'^[a-zA-Z0-9._/-]+$')); // Only safe characters
  }

  /// Joins path segments with the appropriate separator for the provider
  static String join(List<String> segments, ProviderType providerType) {
    if (segments.isEmpty) return '';

    final separator =
        providerType == ProviderType.filesystem ? _platformSeparator : '/';

    return segments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => normalize(segment, providerType))
        .join(separator);
  }

  /// Splits a path into its component segments
  static List<String> split(String path, ProviderType providerType) {
    final normalizedPath = normalize(path, providerType);
    if (normalizedPath.isEmpty) return [];

    return normalizedPath
        .split(RegExp(r'[/\\]'))
        .where((segment) => segment.isNotEmpty)
        .toList();
  }
}
