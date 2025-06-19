import '../storage/credential_storage.dart';
import 'oauth_user.dart';

/// Result of an OAuth authentication attempt
class OAuthResult {
  const OAuthResult({required this.credentials, this.user, this.error});

  final StoredCredentials credentials;
  final OAuthUser? user;
  final String? error;

  bool get isSuccess => error == null;
  bool get hasUser => user != null;

  @override
  String toString() =>
      'OAuthResult(success: $isSuccess, user: ${user?.login}, error: $error)';
}
