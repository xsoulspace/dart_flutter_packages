import 'models.dart';

export 'models.dart';

Never _unsupported() {
  throw UnsupportedError(
    'VK Play SDK is available only on web (dart.library.js_interop).',
  );
}

/// Non-web fallback for VK Play wrapper.
abstract final class VkPlay {
  static Future<VkPlayClient> init({
    final String? appId,
    final String expectedGlobal = 'iframeApi',
  }) async => _unsupported();

  static bool isAvailable({final String expectedGlobal = 'iframeApi'}) => false;
}

class VkPlayClient {
  Future<void> init({final String? appId}) async => _unsupported();

  Future<VkPlayLoginStatus> getLoginStatus() async => _unsupported();

  Future<VkPlayUserInfo?> userInfo() async => _unsupported();

  Future<VkPlayUserProfile?> userProfile() async => _unsupported();

  Future<List<VkPlayFriend>> userFriends({
    final int? limit,
    final int? offset,
  }) async => _unsupported();

  Future<List<VkPlayFriend>> userSocialFriends({
    final int? limit,
    final int? offset,
  }) async => _unsupported();

  Future<Map<String, Object?>> invite(
    final VkPlayInvitePayload payload,
  ) async => _unsupported();

  Future<Map<String, Object?>> shareToFeed(
    final VkPlayFeedSharePayload payload,
  ) async => _unsupported();

  Future<Object?> callRaw(
    final String methodName, {
    final Map<String, Object?>? params,
  }) async => _unsupported();
}
