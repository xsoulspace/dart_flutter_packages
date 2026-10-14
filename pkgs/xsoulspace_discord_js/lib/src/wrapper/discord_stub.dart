import 'models.dart';

export 'models.dart';

Never _unsupported() {
  throw UnsupportedError(
    'Discord Embedded SDK is available only on web (dart.library.js_interop).',
  );
}

/// Non-web fallback for Discord wrapper.
abstract final class Discord {
  static Future<DiscordClient> init({
    required String clientId,
    String expectedGlobal = 'DiscordSDK',
    Map<String, Object?> configuration = const <String, Object?>{},
    bool waitReady = true,
  }) async => _unsupported();

  static bool isAvailable({String expectedGlobal = 'DiscordSDK'}) =>
      false;
}

class DiscordClient {
  Object get rawClient => _unsupported();

  Future<void> ready() async => _unsupported();

  Future<Map<String, Object?>> authorize(
    DiscordAuthorizeRequest request,
  ) async => _unsupported();

  Future<DiscordAuthenticateResult> authenticate({
    String? accessToken,
  }) async => _unsupported();

  Future<DiscordUser?> getUser({required String id}) async =>
      _unsupported();

  Future<List<DiscordRelationship>> getRelationships() async => _unsupported();

  Future<Map<String, Object?>> openInviteDialog() async => _unsupported();

  Future<Map<String, Object?>> inviteUserEmbedded({
    required String userId,
    String? content,
  }) async => _unsupported();

  Future<DiscordShareLinkResult> shareLink({
    required String message,
    String? customId,
    String? linkId,
  }) async => _unsupported();

  Future<Map<String, Object?>> openShareMomentDialog({
    required String mediaUrl,
  }) async => _unsupported();

  Future<DiscordEventSubscription> onCurrentUserUpdate(
    void Function(DiscordUser? user) listener,
  ) async => _unsupported();

  Future<DiscordEventSubscription> onRelationshipUpdate(
    void Function(DiscordRelationship relationship) listener,
  ) async => _unsupported();

  Future<DiscordEventSubscription> onRawEvent(
    String event,
    void Function(DiscordEventData event) listener, {
    Map<String, Object?>? subscribeArgs,
  }) async => _unsupported();

  Future<Object?> callRawCommand(
    String methodName, {
    Map<String, Object?>? params,
  }) async => _unsupported();
}
