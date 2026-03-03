import 'dart:async';

import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';

import 'discord_oauth_gateway.dart';
import 'discord_platform_config.dart';
import 'discord_raw_capability.dart';

typedef DiscordClientInitializer =
    Future<DiscordClient> Function({
      required String clientId,
      required String expectedGlobal,
    });

final class DiscordPlatformClient implements PlatformClient {
  DiscordPlatformClient({required this.config, required this.initClient});

  final DiscordPlatformConfig config;
  final DiscordClientInitializer initClient;

  final CapabilityRegistry _capabilities = CapabilityRegistry();
  final StreamController<PlatformEvent> _eventsController =
      StreamController<PlatformEvent>.broadcast();

  final StreamController<PlayerIdentity?> _authController =
      StreamController<PlayerIdentity?>.broadcast();

  DiscordClient? _sdkClient;
  PlayerIdentity? _currentIdentity;

  DiscordEventSubscription? _currentUserSubscription;
  DiscordEventSubscription? _relationshipSubscription;

  @override
  PlatformId get platformId => PlatformId.discord;

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    final bool sdkReady;
    try {
      sdkReady = await _ensureSdkReady();
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'Discord SDK loader failed.',
        error: error,
      );
    }

    if (!sdkReady) {
      return PlatformInitResult.notAvailable(
        message:
            'Discord SDK global `${config.expectedSdkGlobal}` was not detected.',
      );
    }

    try {
      _sdkClient = await initClient(
        clientId: config.clientId,
        expectedGlobal: config.expectedSdkGlobal,
      );
    } on UnsupportedError catch (error) {
      return PlatformInitResult.notAvailable(message: error.toString());
    } on StateError catch (error) {
      return PlatformInitResult.notAvailable(message: error.message);
    } on Object catch (error) {
      return PlatformInitResult.failure(
        message: 'Discord init failed.',
        error: error,
      );
    }

    final sdk = _sdkClient!;

    if (config.requireActivityContext) {
      final hasContext = await _hasActivityContext(sdk);
      if (!hasContext) {
        return PlatformInitResult.notAvailable(
          message: 'Discord Activity context is not available.',
        );
      }
    }

    try {
      await _runOAuthHandshakeIfNeeded(sdk);
    } on Object catch (error) {
      _eventsController.add(
        PlatformEvent.now(
          name: 'discord.error',
          payload: <String, Object?>{
            'stage': 'oauth',
            'error': error.toString(),
          },
        ),
      );
      return PlatformInitResult.failure(
        message: 'Discord OAuth handshake failed.',
        error: error,
      );
    }

    final identity = _DiscordIdentityCapability(this);
    _capabilities.register<IdentityCapability>(identity);
    _capabilities.registerDynamic(identity.runtimeType, identity);

    final friends = _DiscordFriendsCapability(sdk);
    _capabilities.register<FriendsCapability>(friends);
    _capabilities.registerDynamic(friends.runtimeType, friends);

    if (config.enableInviteCapability) {
      final invite = _DiscordInviteCapability(sdk);
      _capabilities.register<InviteCapability>(invite);
      _capabilities.registerDynamic(invite.runtimeType, invite);
    }

    if (config.enableFeedShareCapability) {
      final feed = _DiscordFeedShareCapability(sdk);
      _capabilities.register<FeedShareCapability>(feed);
      _capabilities.registerDynamic(feed.runtimeType, feed);
    }

    if (config.enableRawCapability) {
      final raw = _DiscordRawCapabilityImpl(sdk);
      _capabilities.register<DiscordRawCapability>(raw);
      _capabilities.registerDynamic(raw.runtimeType, raw);
    }

    await _bindSdkEvents(sdk);

    _eventsController.add(
      PlatformEvent.now(
        name: 'discord.initialized',
        payload: <String, Object?>{
          'expectedSdkGlobal': config.expectedSdkGlobal,
          'capabilities': capabilityTypes
              .map((final type) => type.toString())
              .toList(growable: false),
        },
      ),
    );

    return PlatformInitResult.success(message: 'Discord initialized.');
  }

  @override
  Future<void> dispose() async {
    await _currentUserSubscription?.cancel();
    await _relationshipSubscription?.cancel();
    _currentUserSubscription = null;
    _relationshipSubscription = null;
    _sdkClient = null;

    await _authController.close();
    await _eventsController.close();
  }

  @override
  bool supports<T extends PlatformCapability>() => _capabilities.supports<T>();

  @override
  T require<T extends PlatformCapability>() {
    final capability = maybe<T>();
    if (capability == null) {
      throw MissingPlatformCapabilityException(
        capabilityType: T,
        supportedCapabilities: capabilityTypes,
        behavior: MissingCapabilityBehavior.strict,
        platformId: platformId,
      );
    }
    return capability;
  }

  @override
  T? maybe<T extends PlatformCapability>() => _capabilities.maybe<T>();

  @override
  Set<Type> get capabilityTypes => _capabilities.types;

  @override
  Stream<PlatformEvent> get events => _eventsController.stream;

  Future<bool> _ensureSdkReady() async {
    final injectedOverride = config.sdkInjected;
    if (injectedOverride != null) {
      return injectedOverride;
    }

    final available = Discord.isAvailable(
      expectedGlobal: config.expectedSdkGlobal,
    );
    if (available) {
      return true;
    }

    if (!config.autoLoadBridge) {
      return false;
    }

    final loader = config.bridgeAutoloadHook;
    final scriptUrl = config.bridgeScriptUrl;
    if (loader == null || scriptUrl == null) {
      return false;
    }

    await loader(scriptUrl);
    return Discord.isAvailable(expectedGlobal: config.expectedSdkGlobal);
  }

  Future<bool> _hasActivityContext(final DiscordClient sdk) async {
    final probe = config.activityContextProbe;
    if (probe != null) {
      return probe(sdk);
    }

    try {
      await sdk.callRawCommand('getChannel');
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _runOAuthHandshakeIfNeeded(final DiscordClient sdk) async {
    final gateway = config.oauthGateway;
    if (gateway == null) {
      return;
    }

    final authorizePayload = await sdk.authorize(
      DiscordAuthorizeRequest(
        clientId: config.clientId,
        scope: config.oauthScopes,
        state: config.oauthState,
        codeChallenge: config.oauthCodeChallenge,
        codeChallengeMethod: config.oauthCodeChallengeMethod,
      ),
    );

    final code = authorizePayload['code']?.toString();
    if (code == null || code.isEmpty) {
      throw StateError('Discord authorize did not return OAuth code.');
    }

    final exchange = await gateway.exchangeAuthorizationCode(
      DiscordOAuthExchangeRequest(
        code: code,
        state: config.oauthState,
        codeChallenge: config.oauthCodeChallenge,
        codeChallengeMethod: config.oauthCodeChallengeMethod,
      ),
    );

    final authResult = await sdk.authenticate(
      accessToken: exchange.accessToken,
    );
    _currentIdentity = _toIdentity(authResult.user);
    _authController.add(_currentIdentity);

    _eventsController.add(
      PlatformEvent.now(
        name: 'discord.auth.updated',
        payload: <String, Object?>{
          'userId': authResult.user.id,
          'scopes': authResult.scopes,
          if (exchange.expiresAt != null)
            'expiresAt': exchange.expiresAt!.toUtc().toIso8601String(),
        },
      ),
    );
  }

  Future<void> _bindSdkEvents(final DiscordClient sdk) async {
    _currentUserSubscription = await sdk.onCurrentUserUpdate((final user) {
      _currentIdentity = user == null ? null : _toIdentity(user);
      _authController.add(_currentIdentity);
      _eventsController.add(
        PlatformEvent.now(
          name: 'discord.auth.updated',
          payload: <String, Object?>{
            if (user != null) 'userId': user.id,
            'source': 'CURRENT_USER_UPDATE',
          },
        ),
      );
    });

    _relationshipSubscription = await sdk.onRelationshipUpdate((final value) {
      _eventsController.add(
        PlatformEvent.now(
          name: 'discord.relationship.updated',
          payload: <String, Object?>{
            'userId': value.user.id,
            'type': value.type,
          },
        ),
      );
    });
  }

  PlayerIdentity _toIdentity(final DiscordUser user) {
    return PlayerIdentity(
      id: user.id,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      isAnonymous: false,
      metadata: user.metadata,
    );
  }
}

final class _DiscordIdentityCapability implements IdentityCapability {
  const _DiscordIdentityCapability(this._client);

  final DiscordPlatformClient _client;

  @override
  String get capabilityName => 'identity';

  @override
  Stream<PlayerIdentity?> get authChanges => _client._authController.stream;

  @override
  Future<PlayerIdentity?> currentPlayer() async {
    return _client._currentIdentity;
  }
}

final class _DiscordFriendsCapability implements FriendsCapability {
  const _DiscordFriendsCapability(this._sdk);

  final DiscordClient _sdk;

  @override
  String get capabilityName => 'friends';

  @override
  Future<List<PlayerFriend>> listFriends({
    final int? limit,
    final int? offset,
  }) async {
    final relationships = await _sdk.getRelationships();

    final friends = relationships
        .where((final value) => value.type == 1)
        .map(
          (final value) => PlayerFriend(
            id: value.user.id,
            displayName: value.user.displayName,
            avatarUrl: value.user.avatarUrl,
          ),
        )
        .toList(growable: false);

    final safeOffset = (offset ?? 0).clamp(0, friends.length);
    final sliced = friends.skip(safeOffset);

    if (limit == null) {
      return sliced.toList(growable: false);
    }

    return sliced.take(limit.clamp(0, friends.length)).toList(growable: false);
  }
}

final class _DiscordInviteCapability implements InviteCapability {
  const _DiscordInviteCapability(this._sdk);

  final DiscordClient _sdk;

  @override
  String get capabilityName => 'invite';

  @override
  Future<InviteResult> invite(final InviteRequest request) async {
    try {
      if (request.recipientIds.isNotEmpty) {
        final response = await _sdk.inviteUserEmbedded(
          userId: request.recipientIds.first,
          content: request.message ?? request.payload,
        );

        return InviteResult(
          sent: true,
          inviteId: response['inviteId']?.toString(),
          metadata: response,
        );
      }

      final response = await _sdk.openInviteDialog();
      return InviteResult(
        sent: response['opened'] == true || response.isEmpty,
        metadata: response,
      );
    } on Object catch (error) {
      return InviteResult(
        sent: false,
        metadata: <String, Object?>{'error': error.toString()},
      );
    }
  }
}

final class _DiscordFeedShareCapability implements FeedShareCapability {
  const _DiscordFeedShareCapability(this._sdk);

  final DiscordClient _sdk;

  @override
  String get capabilityName => 'feed.share';

  @override
  Future<FeedShareResult> shareToFeed(final FeedShareRequest request) async {
    try {
      final message =
          request.message ?? request.linkUrl ?? 'Shared from Discord';
      final share = await _sdk.shareLink(message: message);

      if (share.success) {
        return FeedShareResult(shared: true, metadata: share.metadata);
      }

      if (request.imageUrl != null && request.imageUrl!.isNotEmpty) {
        final dialog = await _sdk.openShareMomentDialog(
          mediaUrl: request.imageUrl!,
        );
        return FeedShareResult(
          shared: dialog['opened'] == true || dialog.isEmpty,
          metadata: dialog,
        );
      }

      return FeedShareResult(shared: false, metadata: share.metadata);
    } on Object catch (error) {
      return FeedShareResult(
        shared: false,
        metadata: <String, Object?>{'error': error.toString()},
      );
    }
  }
}

final class _DiscordRawCapabilityImpl implements DiscordRawCapability {
  const _DiscordRawCapabilityImpl(this.client);

  @override
  final DiscordClient client;

  @override
  String get capabilityName => 'discord.raw';

  @override
  Future<Object?> callRaw(
    final String methodName, {
    final Map<String, Object?>? params,
  }) {
    return client.callRawCommand(methodName, params: params);
  }
}
