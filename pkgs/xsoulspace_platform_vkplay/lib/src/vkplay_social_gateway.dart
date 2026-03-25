import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';

abstract interface class VkPlaySocialGateway {
  Future<InviteResult> invite(InviteRequest request);

  Future<FeedShareResult> shareToFeed(FeedShareRequest request);
}
