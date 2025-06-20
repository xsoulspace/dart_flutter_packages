import '../exceptions/storage_exceptions.dart';

/// {@template authenticated_provider}
/// Mixin providing common authentication functionality for storage providers.
/// Reduces code duplication for authentication checks and token management.
/// {@endtemplate}
mixin AuthenticatedProvider {
  /// Authentication token or credential
  String? get authToken;

  /// Checks if the provider has valid authentication credentials
  bool get hasValidCredentials => authToken != null && authToken!.isNotEmpty;

  /// Ensures the provider is authenticated before operations
  void ensureAuthenticated() {
    if (!hasValidCredentials) {
      throw const AuthenticationException(
        'Provider is not authenticated. Please provide valid credentials.',
      );
    }
  }

  /// Validates authentication token format (basic validation)
  bool isValidTokenFormat(final String? token) {
    if (token == null || token.isEmpty) return false;

    // Basic token validation - must be at least 8 characters
    if (token.length < 8) return false;

    // Check for common token patterns
    if (token.startsWith('github_pat_') || // GitHub personal access token
        token.startsWith('ghp_') || // GitHub personal access token (classic)
        token.startsWith('gho_') || // GitHub OAuth token
        token.startsWith('ghu_') || // GitHub user token
        token.startsWith('ghs_') || // GitHub server token
        token.startsWith('ghr_') || // GitHub refresh token
        token.length >= 20) {
      // Generic long token
      return true;
    }

    return false;
  }

  /// Handles authentication-related errors uniformly
  StorageException handleAuthError(final Object error, final String operation) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('401') || errorString.contains('unauthorized')) {
      return AuthenticationException(
        'Authentication failed during $operation. Please check your credentials.',
      );
    }

    if (errorString.contains('403') || errorString.contains('forbidden')) {
      return RemoteAccessDeniedException(
        'Access denied during $operation. Please check your permissions.',
      );
    }

    if (errorString.contains('token') || errorString.contains('auth')) {
      return AuthenticationFailedException(
        'Authentication error during $operation: $error',
      );
    }

    // Return generic network exception for other errors
    return NetworkException('Network error during $operation: $error');
  }

  /// Checks if an error is authentication-related
  bool isAuthenticationError(final Object error) {
    if (error is AuthenticationException) return true;

    final errorString = error.toString().toLowerCase();
    return errorString.contains('401') ||
        errorString.contains('403') ||
        errorString.contains('unauthorized') ||
        errorString.contains('forbidden') ||
        errorString.contains('authentication') ||
        errorString.contains('invalid token');
  }
}
