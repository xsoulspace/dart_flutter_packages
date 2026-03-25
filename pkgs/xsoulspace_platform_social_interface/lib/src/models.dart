import 'package:meta/meta.dart';

@immutable
final class PlayerIdentity {
  const PlayerIdentity({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.isAnonymous = false,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final bool isAnonymous;
  final Map<String, Object?> metadata;
}

@immutable
final class PlayerFriend {
  const PlayerFriend({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
}

@immutable
final class InviteRequest {
  const InviteRequest({
    this.message,
    this.payload,
    this.recipientIds = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String? message;
  final String? payload;
  final List<String> recipientIds;
  final Map<String, Object?> metadata;
}

@immutable
final class InviteResult {
  const InviteResult({
    required this.sent,
    this.inviteId,
    this.metadata = const <String, Object?>{},
  });

  final bool sent;
  final String? inviteId;
  final Map<String, Object?> metadata;
}

@immutable
final class FeedShareRequest {
  const FeedShareRequest({
    this.message,
    this.linkUrl,
    this.imageUrl,
    this.metadata = const <String, Object?>{},
  });

  final String? message;
  final String? linkUrl;
  final String? imageUrl;
  final Map<String, Object?> metadata;
}

@immutable
final class FeedShareResult {
  const FeedShareResult({
    required this.shared,
    this.postId,
    this.metadata = const <String, Object?>{},
  });

  final bool shared;
  final String? postId;
  final Map<String, Object?> metadata;
}
