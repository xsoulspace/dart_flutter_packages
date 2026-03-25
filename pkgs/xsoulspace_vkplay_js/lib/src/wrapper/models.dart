import 'package:meta/meta.dart';

@immutable
final class VkPlayLoginStatus {
  const VkPlayLoginStatus({
    required this.authorized,
    this.userId,
    this.metadata = const <String, Object?>{},
  });

  factory VkPlayLoginStatus.fromMap(final Map<String, Object?> map) {
    final authorized =
        map['authorized'] == true ||
        map['isAuthorized'] == true ||
        map['loggedIn'] == true ||
        map['status'] == 'authorized';

    return VkPlayLoginStatus(
      authorized: authorized,
      userId: (map['userId'] ?? map['uid'] ?? map['id'])?.toString(),
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final bool authorized;
  final String? userId;
  final Map<String, Object?> metadata;
}

@immutable
final class VkPlayUserInfo {
  const VkPlayUserInfo({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.metadata = const <String, Object?>{},
  });

  factory VkPlayUserInfo.fromMap(final Map<String, Object?> map) {
    final id =
        (map['id'] ?? map['userId'] ?? map['uid'])?.toString() ?? 'anonymous';
    final displayName =
        (map['name'] ?? map['displayName'] ?? map['nickname'])?.toString() ??
        'Guest';
    final avatar = (map['avatar'] ?? map['avatarUrl'] ?? map['photo'])
        ?.toString();

    return VkPlayUserInfo(
      id: id,
      displayName: displayName,
      avatarUrl: avatar == null || avatar.isEmpty ? null : avatar,
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String id;
  final String displayName;
  final String? avatarUrl;
  final Map<String, Object?> metadata;
}

@immutable
final class VkPlayUserProfile {
  const VkPlayUserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.metadata = const <String, Object?>{},
  });

  factory VkPlayUserProfile.fromMap(final Map<String, Object?> map) {
    final id =
        (map['id'] ?? map['userId'] ?? map['uid'])?.toString() ?? 'anonymous';
    final displayName =
        (map['name'] ?? map['displayName'] ?? map['nickname'])?.toString() ??
        'Guest';
    final avatar = (map['avatar'] ?? map['avatarUrl'] ?? map['photo'])
        ?.toString();

    return VkPlayUserProfile(
      id: id,
      displayName: displayName,
      avatarUrl: avatar == null || avatar.isEmpty ? null : avatar,
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String id;
  final String displayName;
  final String? avatarUrl;
  final Map<String, Object?> metadata;
}

@immutable
final class VkPlayFriend {
  const VkPlayFriend({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.isSocial = false,
    this.metadata = const <String, Object?>{},
  });

  factory VkPlayFriend.fromMap(
    final Map<String, Object?> map, {
    final bool isSocial = false,
  }) {
    final id = (map['id'] ?? map['uid'] ?? map['userId'])?.toString() ?? '';
    final displayName =
        (map['name'] ?? map['displayName'] ?? map['nickname'])?.toString() ??
        'Friend';
    final avatar = (map['avatar'] ?? map['avatarUrl'] ?? map['photo'])
        ?.toString();

    return VkPlayFriend(
      id: id,
      displayName: displayName,
      avatarUrl: avatar == null || avatar.isEmpty ? null : avatar,
      isSocial: isSocial,
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String id;
  final String displayName;
  final String? avatarUrl;
  final bool isSocial;
  final Map<String, Object?> metadata;
}

@immutable
final class VkPlayInvitePayload {
  const VkPlayInvitePayload({
    this.message,
    this.payload,
    this.recipientIds = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String? message;
  final String? payload;
  final List<String> recipientIds;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (message != null) 'message': message,
      if (payload != null) 'payload': payload,
      if (recipientIds.isNotEmpty) 'recipientIds': recipientIds,
      ...metadata,
    };
  }
}

@immutable
final class VkPlayFeedSharePayload {
  const VkPlayFeedSharePayload({
    this.message,
    this.linkUrl,
    this.imageUrl,
    this.metadata = const <String, Object?>{},
  });

  final String? message;
  final String? linkUrl;
  final String? imageUrl;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (message != null) 'message': message,
      if (linkUrl != null) 'linkUrl': linkUrl,
      if (imageUrl != null) 'imageUrl': imageUrl,
      ...metadata,
    };
  }
}
