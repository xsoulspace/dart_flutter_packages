import 'package:meta/meta.dart';

import 'vkplay_social_gateway.dart';

typedef VkPlaySdkScriptLoader = Future<void> Function(Uri scriptUrl);

@immutable
final class VkPlayPlatformConfig {
  const VkPlayPlatformConfig({
    this.appId,
    this.expectedSdkGlobal = 'iframeApi',
    this.sdkUrl,
    this.autoLoadSdk = false,
    this.sdkScriptLoader,
    this.sdkInjected,
    this.socialGateway,
    this.enableInviteCapability = true,
    this.enableFeedShareCapability = true,
    this.enableRawCapability = true,
  });

  final String? appId;
  final String expectedSdkGlobal;
  final Uri? sdkUrl;
  final bool autoLoadSdk;
  final VkPlaySdkScriptLoader? sdkScriptLoader;

  /// Optional explicit override for SDK presence checks.
  final bool? sdkInjected;

  /// Optional backend gateway for invite/feed-share server-side flows.
  final VkPlaySocialGateway? socialGateway;

  final bool enableInviteCapability;
  final bool enableFeedShareCapability;
  final bool enableRawCapability;
}
