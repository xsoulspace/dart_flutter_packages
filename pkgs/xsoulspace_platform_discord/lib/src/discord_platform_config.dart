import 'dart:async';

import 'package:meta/meta.dart';
import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';

import 'discord_oauth_gateway.dart';

typedef DiscordBridgeAutoloadHook = Future<void> Function(Uri bridgeScriptUrl);
typedef DiscordActivityContextProbe =
    FutureOr<bool> Function(DiscordClient client);

@immutable
final class DiscordPlatformConfig {
  const DiscordPlatformConfig({
    required this.clientId,
    this.expectedSdkGlobal = 'DiscordSDK',
    this.bridgeScriptUrl,
    this.autoLoadBridge = false,
    this.bridgeAutoloadHook,
    this.sdkInjected,
    this.oauthGateway,
    this.oauthScopes = const <String>['identify', 'relationships.read'],
    this.oauthState,
    this.oauthCodeChallenge,
    this.oauthCodeChallengeMethod,
    this.enableInviteCapability = true,
    this.enableFeedShareCapability = true,
    this.enableRawCapability = true,
    this.requireActivityContext = true,
    this.activityContextProbe,
  });

  final String clientId;

  /// JavaScript global expected to expose Discord constructor/instance.
  final String expectedSdkGlobal;

  /// Optional bridge script URL used by [autoLoadBridge].
  final Uri? bridgeScriptUrl;

  /// Enables bridge auto-load when SDK global is missing.
  final bool autoLoadBridge;

  /// Hook to inject bridge script dynamically.
  final DiscordBridgeAutoloadHook? bridgeAutoloadHook;

  /// Optional explicit override for SDK presence checks.
  final bool? sdkInjected;

  /// Backend gateway for OAuth code exchange.
  final DiscordOAuthGateway? oauthGateway;

  /// Scopes requested by `authorize` command.
  final List<String> oauthScopes;
  final String? oauthState;
  final String? oauthCodeChallenge;
  final String? oauthCodeChallengeMethod;

  final bool enableInviteCapability;
  final bool enableFeedShareCapability;
  final bool enableRawCapability;

  /// When enabled, adapter returns `notAvailable` outside Discord Activity context.
  final bool requireActivityContext;

  /// Optional probe override for Discord Activity context detection.
  final DiscordActivityContextProbe? activityContextProbe;
}
