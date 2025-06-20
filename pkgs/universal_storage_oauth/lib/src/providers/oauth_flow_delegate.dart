/// {@template oauth_flow_delegate}
/// Abstract delegate for handling platform-specific OAuth flow operations.
///
/// This delegate pattern allows the OAuth provider to remain platform-agnostic
/// while delegating UI-specific operations (like opening browsers, handling
/// redirects, etc.) to platform-specific implementations.
///
/// Platform implementations should handle:
/// - Browser launching for authorization
/// - Deep link/redirect handling
/// - User consent flow management
/// - Platform-specific UI elements
/// {@endtemplate}
abstract interface class OAuthFlowDelegate {
  /// {@macro oauth_flow_delegate}
  const OAuthFlowDelegate();

  /// Obtains authorization code through platform-specific OAuth flow.
  ///
  /// This method should handle the complete authorization flow:
  /// 1. Open the authorization URL in appropriate manner (browser, webview, etc.)
  /// 2. Handle the redirect/callback with authorization code
  /// 3. Return the authorization code for token exchange
  ///
  /// [authorizationUrl] - The OAuth provider's authorization endpoint
  /// [redirectUrl] - The configured redirect URI
  /// [state] - Optional state parameter for security
  ///
  /// Throws [OAuthFlowCancelledException] if user cancels the flow.
  /// Throws [OAuthFlowException] for other flow-related errors.
  Future<String> getAuthorizationCode(
    final Uri authorizationUrl,
    final Uri redirectUrl, {
    final String? state,
  });

  /// Handles device flow verification for CLI/desktop applications.
  ///
  /// This method should display the device code and verification URL to the user
  /// and wait for them to complete the authorization on another device.
  ///
  /// [deviceCode] - The device code to display to the user
  /// [userCode] - The user-friendly code to display
  /// [verificationUrl] - The URL where user should authorize
  /// [verificationUrlComplete] - Optional direct URL with code embedded
  /// [expiresIn] - Time in seconds until codes expire
  /// [interval] - Polling interval in seconds
  ///
  /// Returns when user has completed authorization or throws exception.
  /// Implementation should handle the display and polling logic.
  Future<void> handleDeviceFlow({
    required final String deviceCode,
    required final String userCode,
    required final Uri verificationUrl,
    required final int expiresIn,
    required final int interval,
    final Uri? verificationUrlComplete,
  });

  /// Called when OAuth flow completes successfully.
  ///
  /// Platform implementations can use this to show success messages,
  /// close browser windows, navigate to success pages, etc.
  ///
  /// [accessToken] - The obtained access token (masked for security)
  /// [scopes] - The granted scopes
  Future<void> onAuthorizationSuccess({
    required final String maskedToken,
    required final List<String> scopes,
  });

  /// Called when OAuth flow fails.
  ///
  /// Platform implementations can use this to show error messages,
  /// log errors, navigate to error pages, etc.
  ///
  /// [error] - The error that occurred
  /// [description] - Optional error description
  Future<void> onAuthorizationError({
    required final String error,
    final String? description,
  });
}

/// {@template oauth_flow_cancelled_exception}
/// Exception thrown when user cancels the OAuth flow.
/// {@endtemplate}
class OAuthFlowCancelledException implements Exception {
  /// {@macro oauth_flow_cancelled_exception}
  const OAuthFlowCancelledException([
    this.message = 'OAuth flow was cancelled by user',
  ]);

  /// The error message.
  final String message;

  @override
  String toString() => 'OAuthFlowCancelledException: $message';
}

/// {@template oauth_flow_exception}
/// Exception thrown when OAuth flow encounters an error.
/// {@endtemplate}
class OAuthFlowException implements Exception {
  /// {@macro oauth_flow_exception}
  const OAuthFlowException(this.message, [this.cause]);

  /// The error message.
  final String message;

  /// The underlying cause of the error.
  final Object? cause;

  @override
  String toString() =>
      'OAuthFlowException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}
