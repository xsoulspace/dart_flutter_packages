/// Public facts xAI needs in order to allowlist Last Answer the way
/// OpenCode was allowlisted. This is Last Answer's own client. The Grok
/// CLI client id is not embedded here.
final class LastAnswerGrokRegistration {
  const LastAnswerGrokRegistration({
    required this.clientId,
    this.apiBase = defaultApiBase,
  });

  static const referrer = 'last-answer';
  static const redirectUri = 'http://127.0.0.1:56123/callback';
  static const redirectPort = 56123;
  static const issuer = 'https://auth.x.ai';
  static const defaultApiBase = 'https://api.x.ai/v1';
  static const scopes = <String>[
    'openid',
    'profile',
    'email',
    'offline_access',
    'api:access',
  ];

  /// Plan inference is granted only when the token includes this scope.
  static const planScope = 'api:access';

  /// Compile-time drop-in once xAI issues a public client id.
  /// `--dart-define=LAST_ANSWER_GROK_CLIENT_ID=...`
  static const environmentClientId = String.fromEnvironment(
    'LAST_ANSWER_GROK_CLIENT_ID',
  );

  /// `--dart-define=LAST_ANSWER_GROK_API_BASE=...` when xAI names a host
  /// other than the public Responses API.
  static const environmentApiBase = String.fromEnvironment(
    'LAST_ANSWER_GROK_API_BASE',
    defaultValue: defaultApiBase,
  );

  final String clientId;
  final String apiBase;

  bool get isRegistered => clientId.trim().isNotEmpty;

  String get scopeString => scopes.join(' ');

  static LastAnswerGrokRegistration fromEnvironment() =>
      LastAnswerGrokRegistration(
        clientId: environmentClientId.trim(),
        apiBase: environmentApiBase,
      );

  @override
  String toString() =>
      'LastAnswerGrokRegistration(referrer: $referrer, '
      'redirect: $redirectUri, registered: $isRegistered)';
}
