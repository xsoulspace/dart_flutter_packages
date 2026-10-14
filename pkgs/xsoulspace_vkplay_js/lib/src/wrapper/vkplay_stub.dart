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
    String? appId,
    String expectedGlobal = 'iframeApi',
  }) async => _unsupported();

  static bool isAvailable({String expectedGlobal = 'iframeApi'}) => false;
}

class VkPlayClient {
  Future<void> init({String? appId}) async => _unsupported();

  Future<VkPlayLoginStatus> getLoginStatus() async => _unsupported();

  Future<VkPlayUserInfo?> userInfo() async => _unsupported();

  Future<VkPlayUserProfile?> userProfile() async => _unsupported();

  Future<List<VkPlayFriend>> userFriends({
    int? limit,
    int? offset,
  }) async => _unsupported();

  Future<List<VkPlayFriend>> userSocialFriends({
    int? limit,
    int? offset,
  }) async => _unsupported();

  Future<Map<String, Object?>> invite(
    VkPlayInvitePayload payload,
  ) async => _unsupported();

  Future<Map<String, Object?>> shareToFeed(
    VkPlayFeedSharePayload payload,
  ) async => _unsupported();

  Future<Object?> callRaw(
    String methodName, {
    Map<String, Object?>? params,
  }) async => _unsupported();
}
