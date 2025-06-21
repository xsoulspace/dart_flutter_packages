import '../models/models.dart';

/// Base interface for OAuth providers
abstract class OAuthProvider {
  /// The platform this provider handles
  GitPlatform get platform;

  /// Current configuration
  OAuthConfig get config;

  /// Start OAuth authentication flow
  Future<OAuthResult> authenticate();

  /// Refresh access token if possible
  Future<OAuthResult> refreshToken(final String refreshToken);

  /// Check if currently authenticated
  Future<bool> isAuthenticated();

  /// Sign out and clear credentials
  Future<void> signOut();

  /// Get current user information
  Future<OAuthUser?> getCurrentUser();
}
