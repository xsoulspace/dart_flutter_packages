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
    required final String clientId,
    final String expectedGlobal = 'DiscordSDK',
    final Map<String, Object?> configuration = const <String, Object?>{},
    final bool waitReady = true,
  }) async => _unsupported();

  static bool isAvailable({final String expectedGlobal = 'DiscordSDK'}) =>
      false;
}

class DiscordClient {
  Object get rawClient => _unsupported();

  Future<void> ready() async => _unsupported();

  Future<Map<String, Object?>> authorize(
    final DiscordAuthorizeRequest request,
  ) async => _unsupported();

  Future<DiscordAuthenticateResult> authenticate({
    final String? accessToken,
  }) async => _unsupported();

  Future<DiscordUser?> getUser({required final String id}) async =>
      _unsupported();

  Future<List<DiscordRelationship>> getRelationships() async => _unsupported();

  Future<Map<String, Object?>> openInviteDialog() async => _unsupported();

  Future<Map<String, Object?>> inviteUserEmbedded({
    required final String userId,
    final String? content,
  }) async => _unsupported();

  Future<DiscordShareLinkResult> shareLink({
    required final String message,
    final String? customId,
    final String? linkId,
  }) async => _unsupported();

  Future<Map<String, Object?>> openShareMomentDialog({
    required final String mediaUrl,
  }) async => _unsupported();

  Future<DiscordEventSubscription> onCurrentUserUpdate(
    final void Function(DiscordUser? user) listener,
  ) async => _unsupported();

  Future<DiscordEventSubscription> onRelationshipUpdate(
    final void Function(DiscordRelationship relationship) listener,
  ) async => _unsupported();

  Future<DiscordEventSubscription> onRawEvent(
    final String event,
    final void Function(DiscordEventData event) listener, {
    final Map<String, Object?>? subscribeArgs,
  }) async => _unsupported();

  Future<Object?> callRawCommand(
    final String methodName, {
    final Map<String, Object?>? params,
  }) async => _unsupported();
}
