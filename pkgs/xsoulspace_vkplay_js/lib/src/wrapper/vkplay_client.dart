import 'converters.dart';
import 'models.dart';

/// High-level VK Play SDK wrapper around `iframeApi` JS object.
class VkPlayClient {
  VkPlayClient(this._api);

  final Object _api;

  Future<void> init({final String? appId}) async {
    final args = <Object?>[
      if (appId == null) null else jsify(<String, Object?>{'app_id': appId}),
    ];

    if (!_hasMethod('init')) {
      return;
    }

    await jsCallPromise(_api, 'init', args);
  }

  Future<VkPlayLoginStatus> getLoginStatus() async {
    if (!_hasMethod('getLoginStatus')) {
      return const VkPlayLoginStatus(authorized: false);
    }

    final result = await jsCallPromise(_api, 'getLoginStatus');
    if (result is bool) {
      return VkPlayLoginStatus(authorized: result);
    }
    return VkPlayLoginStatus.fromMap(asMap(result));
  }

  Future<VkPlayUserInfo?> userInfo() async {
    if (!_hasMethod('userInfo')) {
      return null;
    }
    final result = asMap(await jsCallPromise(_api, 'userInfo'));
    if (result.isEmpty) {
      return null;
    }
    return VkPlayUserInfo.fromMap(result);
  }

  Future<VkPlayUserProfile?> userProfile() async {
    if (!_hasMethod('userProfile')) {
      return null;
    }
    final result = asMap(await jsCallPromise(_api, 'userProfile'));
    if (result.isEmpty) {
      return null;
    }
    return VkPlayUserProfile.fromMap(result);
  }

  Future<List<VkPlayFriend>> userFriends({
    final int? limit,
    final int? offset,
  }) async {
    return _readFriends(
      methodName: 'userFriends',
      limit: limit,
      offset: offset,
      isSocial: false,
    );
  }

  Future<List<VkPlayFriend>> userSocialFriends({
    final int? limit,
    final int? offset,
  }) async {
    return _readFriends(
      methodName: 'userSocialFriends',
      limit: limit,
      offset: offset,
      isSocial: true,
    );
  }

  Future<Map<String, Object?>> invite(final VkPlayInvitePayload payload) async {
    final result = await _callFirstAvailable(<String>[
      'showInviteBox',
      'invite',
    ], payload.toJson());
    return asMap(result);
  }

  Future<Map<String, Object?>> shareToFeed(
    final VkPlayFeedSharePayload payload,
  ) async {
    final result = await _callFirstAvailable(<String>[
      'postToFeed',
      'share',
      'wallPost',
    ], payload.toJson());
    return asMap(result);
  }

  Future<Object?> callRaw(
    final String methodName, {
    final Map<String, Object?>? params,
  }) async {
    if (!_hasMethod(methodName)) {
      throw StateError('VK Play SDK method `$methodName` is not available.');
    }

    if (params == null || params.isEmpty) {
      return jsCallPromise(_api, methodName);
    }
    return jsCallPromise(_api, methodName, <Object?>[jsify(params)]);
  }

  Future<List<VkPlayFriend>> _readFriends({
    required final String methodName,
    required final bool isSocial,
    final int? limit,
    final int? offset,
  }) async {
    if (!_hasMethod(methodName)) {
      return const <VkPlayFriend>[];
    }

    final params = <String, Object?>{};
    if (limit != null) {
      params['limit'] = limit;
    }
    if (offset != null) {
      params['offset'] = offset;
    }

    final response = params.isEmpty
        ? await jsCallPromise(_api, methodName)
        : await jsCallPromise(_api, methodName, <Object?>[jsify(params)]);

    final map = asMap(response);
    final list = map.isNotEmpty
        ? asList(map['items'] ?? map['friends'] ?? map['result'])
        : asList(response);

    return list
        .map(asMap)
        .where((final item) => item.isNotEmpty)
        .map((final item) => VkPlayFriend.fromMap(item, isSocial: isSocial))
        .where((final item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Object?> _callFirstAvailable(
    final List<String> methods,
    final Map<String, Object?> payload,
  ) async {
    for (final method in methods) {
      if (_hasMethod(method)) {
        return jsCallPromise(_api, method, <Object?>[jsify(payload)]);
      }
    }
    throw StateError(
      'None of the VK Play SDK methods are available: ${methods.join(', ')}.',
    );
  }

  bool _hasMethod(final String methodName) => prop(_api, methodName) != null;
}
