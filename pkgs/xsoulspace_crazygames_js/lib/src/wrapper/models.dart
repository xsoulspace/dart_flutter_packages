import 'package:meta/meta.dart';

import 'enums.dart';

@immutable
class SdkError implements Exception {
  const SdkError({required this.code, required this.message, this.containerId});

  factory SdkError.fromMap(final Map<String, Object?> map) => SdkError(
    code: (map['code'] as String?) ?? 'other',
    message: (map['message'] as String?) ?? 'Unknown error',
    containerId: map['containerId'] as String?,
  );

  final String code;
  final String message;
  final String? containerId;

  @override
  String toString() => 'SdkError(code: $code, message: $message)';
}

@immutable
class User {
  const User({
    required this.username,
    required this.profilePictureUrl,
    this.id,
  });

  factory User.fromMap(final Map<String, Object?> map) => User(
    id: map['id'] as String?,
    username: (map['username'] as String?) ?? '',
    profilePictureUrl: (map['profilePictureUrl'] as String?) ?? '',
  );

  final String? id;
  final String username;
  final String profilePictureUrl;
}

@immutable
class BrowserInfo {
  const BrowserInfo({required this.name, required this.version});

  factory BrowserInfo.fromMap(final Map<String, Object?> map) => BrowserInfo(
    name: (map['name'] as String?) ?? '',
    version: (map['version'] as String?) ?? '',
  );

  final String name;
  final String version;
}

@immutable
class OsInfo {
  const OsInfo({required this.name, required this.version});

  factory OsInfo.fromMap(final Map<String, Object?> map) => OsInfo(
    name: (map['name'] as String?) ?? '',
    version: (map['version'] as String?) ?? '',
  );

  final String name;
  final String version;
}

@immutable
class DeviceInfo {
  const DeviceInfo({required this.type});

  factory DeviceInfo.fromMap(final Map<String, Object?> map) =>
      DeviceInfo(type: DeviceType.fromValue(map['type'] as String?));

  final DeviceType type;
}

@immutable
class SystemInfo {
  const SystemInfo({
    required this.countryCode,
    required this.locale,
    required this.device,
    required this.os,
    required this.browser,
    required this.applicationType,
  });

  factory SystemInfo.fromMap(final Map<String, Object?> map) => SystemInfo(
    countryCode: (map['countryCode'] as String?) ?? '',
    locale: (map['locale'] as String?) ?? '',
    device: DeviceInfo.fromMap(
      (map['device'] as Map<Object?, Object?>? ?? const <Object?, Object?>{})
          .map((final key, final value) => MapEntry(key.toString(), value)),
    ),
    os: OsInfo.fromMap(
      (map['os'] as Map<Object?, Object?>? ?? const <Object?, Object?>{}).map(
        (final key, final value) => MapEntry(key.toString(), value),
      ),
    ),
    browser: BrowserInfo.fromMap(
      (map['browser'] as Map<Object?, Object?>? ?? const <Object?, Object?>{})
          .map((final key, final value) => MapEntry(key.toString(), value)),
    ),
    applicationType: ApplicationType.fromValue(
      map['applicationType'] as String?,
    ),
  );

  final String countryCode;
  final String locale;
  final DeviceInfo device;
  final OsInfo os;
  final BrowserInfo browser;
  final ApplicationType applicationType;
}

@immutable
class Friend {
  const Friend({
    required this.id,
    required this.username,
    required this.profilePictureUrl,
  });

  factory Friend.fromMap(final Map<String, Object?> map) => Friend(
    id: (map['id'] as String?) ?? '',
    username: (map['username'] as String?) ?? '',
    profilePictureUrl: (map['profilePictureUrl'] as String?) ?? '',
  );

  final String id;
  final String username;
  final String profilePictureUrl;
}

@immutable
class FriendsPage {
  const FriendsPage({
    required this.friends,
    required this.page,
    required this.size,
    required this.hasMore,
    required this.total,
  });

  factory FriendsPage.fromMap(final Map<String, Object?> map) => FriendsPage(
    friends: (map['friends'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Object?>()
        .map(
          (final item) => Friend.fromMap(
            (item! as Map<Object?, Object?>).map(
              (final key, final value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false),
    page: (map['page'] as num?)?.toInt() ?? 1,
    size: (map['size'] as num?)?.toInt() ?? 0,
    hasMore: map['hasMore'] as bool? ?? false,
    total: (map['total'] as num?)?.toInt() ?? 0,
  );

  final List<Friend> friends;
  final int page;
  final int size;
  final bool hasMore;
  final int total;
}

@immutable
class AccountLinkResponse {
  const AccountLinkResponse({required this.answer});

  factory AccountLinkResponse.fromMap(final Map<String, Object?> map) =>
      AccountLinkResponse(
        answer: AccountLinkAnswer.fromValue(map['response'] as String?),
      );

  final AccountLinkAnswer answer;
}

@immutable
class GameSettings {
  const GameSettings({required this.disableChat, required this.muteAudio});

  factory GameSettings.fromMap(final Map<String, Object?> map) => GameSettings(
    disableChat: map['disableChat'] as bool? ?? false,
    muteAudio: map['muteAudio'] as bool? ?? false,
  );

  final bool disableChat;
  final bool muteAudio;
}

@immutable
class FriendsPageOptions {
  const FriendsPageOptions({required this.page, required this.size});

  final int page;
  final int size;

  Map<String, Object?> toJson() => <String, Object?>{
    'page': page,
    'size': size,
  };
}

@immutable
class BannerRequest {
  const BannerRequest({
    required this.id,
    required this.width,
    required this.height,
    this.x,
    this.y,
  });

  factory BannerRequest.fromMap(final Map<String, Object?> map) =>
      BannerRequest(
        id: (map['id'] as String?) ?? '',
        width: (map['width'] as num?)?.toInt() ?? 0,
        height: (map['height'] as num?)?.toInt() ?? 0,
        x: (map['x'] as num?)?.toInt(),
        y: (map['y'] as num?)?.toInt(),
      );

  final String id;
  final int width;
  final int height;
  final int? x;
  final int? y;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'width': width,
    'height': height,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };
}

@immutable
class OverlayPoint {
  const OverlayPoint({required this.x, required this.y});

  final num x;
  final num y;

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};
}

@immutable
class OverlayBannerRequest {
  const OverlayBannerRequest({
    required this.id,
    required this.size,
    required this.anchor,
    required this.position,
    this.pivot,
  });

  final String id;
  final String size;
  final OverlayPoint anchor;
  final OverlayPoint position;
  final OverlayPoint? pivot;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'size': size,
    'anchor': anchor.toJson(),
    'position': position.toJson(),
    if (pivot != null) 'pivot': pivot!.toJson(),
  };
}

@immutable
class PrefetchedBanner {
  const PrefetchedBanner({
    required this.id,
    required this.banner,
    required this.renderOptions,
  });

  factory PrefetchedBanner.fromMap(final Map<String, Object?> map) {
    final bannerMap =
        (map['banner'] as Map<Object?, Object?>? ?? const <Object?, Object?>{})
            .map((final key, final value) => MapEntry(key.toString(), value));
    final renderOptions =
        (map['renderOptions'] as Map<Object?, Object?>? ??
                const <Object?, Object?>{})
            .map((final key, final value) => MapEntry(key.toString(), value));

    return PrefetchedBanner(
      id: (map['id'] as String?) ?? '',
      banner: BannerRequest.fromMap(
        bannerMap.isNotEmpty
            ? bannerMap
            : <String, Object?>{
                'id': map['id'],
                'width': map['width'],
                'height': map['height'],
                'x': map['x'],
                'y': map['y'],
              },
      ),
      renderOptions: renderOptions,
    );
  }

  final String id;
  final BannerRequest banner;
  final Map<String, Object?> renderOptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'banner': banner.toJson(),
    'renderOptions': renderOptions,
  };
}
