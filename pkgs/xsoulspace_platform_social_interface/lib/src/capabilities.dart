import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

import 'models.dart';

abstract interface class IdentityCapability implements PlatformCapability {
  Future<PlayerIdentity?> currentPlayer();

  Stream<PlayerIdentity?> get authChanges;
}

abstract interface class FriendsCapability implements PlatformCapability {
  Future<List<PlayerFriend>> listFriends({int? limit, int? offset});
}

abstract interface class InviteCapability implements PlatformCapability {
  Future<InviteResult> invite(InviteRequest request);
}

abstract interface class FeedShareCapability implements PlatformCapability {
  Future<FeedShareResult> shareToFeed(FeedShareRequest request);
}
