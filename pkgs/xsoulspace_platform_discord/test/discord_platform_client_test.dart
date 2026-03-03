import 'package:test/test.dart';
import 'package:xsoulspace_discord_js/xsoulspace_discord_js.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_discord/xsoulspace_platform_discord.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';
import 'package:xsoulspace_platform_social_interface/xsoulspace_platform_social_interface.dart';

void main() {
  test('returns notAvailable when SDK global is missing', () async {
    final client = DiscordPlatformClient(
      config: const DiscordPlatformConfig(
        clientId: 'app-1',
        sdkInjected: false,
      ),
      initClient: ({required final clientId, required final expectedGlobal}) {
        throw StateError('should not initialize');
      },
    );

    final result = await client.init(const PlatformInitOptions());
    expect(result.isNotAvailable, isTrue);
  });

  test('returns notAvailable when Activity context is missing', () async {
    final sdk = _FakeDiscordClient()..hasActivityContext = false;

    final client = DiscordPlatformClient(
      config: const DiscordPlatformConfig(clientId: 'app-1', sdkInjected: true),
      initClient:
          ({required final clientId, required final expectedGlobal}) async {
            return sdk;
          },
    );

    final result = await client.init(const PlatformInitOptions());
    expect(result.isNotAvailable, isTrue);
  });

  test('registers capabilities and maps relationship-to-friends', () async {
    final sdk = _FakeDiscordClient();
    final gateway = _FakeOAuthGateway();

    final client = DiscordPlatformClient(
      config: DiscordPlatformConfig(
        clientId: 'app-1',
        sdkInjected: true,
        oauthGateway: gateway,
      ),
      initClient:
          ({required final clientId, required final expectedGlobal}) async {
            return sdk;
          },
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    expect(client.supports<IdentityCapability>(), isTrue);
    expect(client.supports<FriendsCapability>(), isTrue);
    expect(client.supports<InviteCapability>(), isTrue);
    expect(client.supports<FeedShareCapability>(), isTrue);
    expect(client.supports<DiscordRawCapability>(), isTrue);

    final identity = await client.require<IdentityCapability>().currentPlayer();
    expect(identity?.id, 'u-1');

    final friends = await client.require<FriendsCapability>().listFriends();
    expect(friends, hasLength(2));
    expect(friends.first.id, 'f-1');

    expect(gateway.lastCode, 'oauth-code-1');
    expect(sdk.lastAuthenticatedToken, 'access-token-1');
  });

  test('invite/share behavior and fallback paths', () async {
    final sdk = _FakeDiscordClient()..shareShouldFail = true;

    final client = DiscordPlatformClient(
      config: const DiscordPlatformConfig(clientId: 'app-1', sdkInjected: true),
      initClient:
          ({required final clientId, required final expectedGlobal}) async {
            return sdk;
          },
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);

    final inviteCapability = client.require<InviteCapability>();
    final sentToUser = await inviteCapability.invite(
      const InviteRequest(message: 'join', recipientIds: <String>['f-1']),
    );
    expect(sentToUser.sent, isTrue);
    expect(sdk.lastInviteUserId, 'f-1');

    final dialogInvite = await inviteCapability.invite(
      const InviteRequest(message: 'open dialog'),
    );
    expect(dialogInvite.sent, isTrue);
    expect(sdk.openInviteDialogCalls, 1);

    final feedCapability = client.require<FeedShareCapability>();
    final fallbackShare = await feedCapability.shareToFeed(
      const FeedShareRequest(
        message: 'share',
        imageUrl: 'https://cdn.discordapp.com/1.png',
      ),
    );
    expect(fallbackShare.shared, isTrue);
    expect(sdk.openShareMomentCalls, 1);
  });

  test('OAuth handshake failure propagates as init failure', () async {
    final sdk = _FakeDiscordClient();
    final gateway = _FakeOAuthGateway()..shouldThrow = true;

    final client = DiscordPlatformClient(
      config: DiscordPlatformConfig(
        clientId: 'app-1',
        sdkInjected: true,
        oauthGateway: gateway,
      ),
      initClient:
          ({required final clientId, required final expectedGlobal}) async {
            return sdk;
          },
    );

    final result = await client.init(const PlatformInitOptions());
    expect(result.isFailure, isTrue);
  });

  test('runtime smoke selects PlatformId.discord', () async {
    final sdk = _FakeDiscordClient();
    final gateway = _FakeOAuthGateway();

    final runtime = PlatformRuntime(
      factories: <PlatformAdapterFactory>[
        DiscordPlatformFactory(
          config: DiscordPlatformConfig(
            clientId: 'app-1',
            oauthGateway: gateway,
            sdkInjected: true,
          ),
          environmentProbe: (final expectedGlobal) => true,
          initClient:
              ({required final clientId, required final expectedGlobal}) async {
                return sdk;
              },
        ),
      ],
    );

    final start = await runtime.start();
    expect(start.activePlatform, PlatformId.discord);

    final identity = await runtime
        .require<IdentityCapability>()
        .currentPlayer();
    expect(identity?.id, 'u-1');
  });
}

final class _FakeOAuthGateway implements DiscordOAuthGateway {
  bool shouldThrow = false;
  String? lastCode;

  @override
  Future<DiscordOAuthExchangeResult> exchangeAuthorizationCode(
    final DiscordOAuthExchangeRequest request,
  ) async {
    if (shouldThrow) {
      throw StateError('OAuth exchange failed');
    }
    lastCode = request.code;
    return const DiscordOAuthExchangeResult(accessToken: 'access-token-1');
  }
}

final class _FakeDiscordClient extends DiscordClient {
  _FakeDiscordClient();

  bool hasActivityContext = true;
  bool shareShouldFail = false;

  String? lastAuthenticatedToken;
  String? lastInviteUserId;
  int openInviteDialogCalls = 0;
  int openShareMomentCalls = 0;

  @override
  Future<void> ready() async {}

  @override
  Future<Map<String, Object?>> authorize(
    final DiscordAuthorizeRequest request,
  ) async {
    return <String, Object?>{'code': 'oauth-code-1'};
  }

  @override
  Future<DiscordAuthenticateResult> authenticate({
    final String? accessToken,
  }) async {
    lastAuthenticatedToken = accessToken;
    return DiscordAuthenticateResult(
      accessToken: accessToken ?? 'none',
      user: const DiscordUser(
        id: 'u-1',
        displayName: 'Player One',
        username: 'player1',
      ),
      scopes: const <String>['identify', 'relationships.read'],
    );
  }

  @override
  Future<List<DiscordRelationship>> getRelationships() async {
    return const <DiscordRelationship>[
      DiscordRelationship(
        type: 1,
        user: DiscordUser(id: 'f-1', displayName: 'Friend 1', username: 'f1'),
      ),
      DiscordRelationship(
        type: 2,
        user: DiscordUser(
          id: 'blocked-1',
          displayName: 'Blocked',
          username: 'b',
        ),
      ),
      DiscordRelationship(
        type: 1,
        user: DiscordUser(id: 'f-2', displayName: 'Friend 2', username: 'f2'),
      ),
    ];
  }

  @override
  Future<Map<String, Object?>> openInviteDialog() async {
    openInviteDialogCalls += 1;
    return <String, Object?>{'opened': true};
  }

  @override
  Future<Map<String, Object?>> inviteUserEmbedded({
    required final String userId,
    final String? content,
  }) async {
    lastInviteUserId = userId;
    return <String, Object?>{'sent': true, 'userId': userId};
  }

  @override
  Future<DiscordShareLinkResult> shareLink({
    required final String message,
    final String? customId,
    final String? linkId,
  }) async {
    if (shareShouldFail) {
      return const DiscordShareLinkResult(
        success: false,
        didCopyLink: false,
        didSendMessage: false,
      );
    }
    return const DiscordShareLinkResult(
      success: true,
      didCopyLink: true,
      didSendMessage: true,
    );
  }

  @override
  Future<Map<String, Object?>> openShareMomentDialog({
    required final String mediaUrl,
  }) async {
    openShareMomentCalls += 1;
    return <String, Object?>{'opened': true, 'mediaUrl': mediaUrl};
  }

  @override
  Future<DiscordEventSubscription> onCurrentUserUpdate(
    final void Function(DiscordUser? user) listener,
  ) async {
    return DiscordEventSubscription(onCancel: () async {});
  }

  @override
  Future<DiscordEventSubscription> onRelationshipUpdate(
    final void Function(DiscordRelationship relationship) listener,
  ) async {
    return DiscordEventSubscription(onCancel: () async {});
  }

  @override
  Future<Object?> callRawCommand(
    final String methodName, {
    final Map<String, Object?>? params,
  }) async {
    if (methodName == 'getChannel') {
      if (!hasActivityContext) {
        throw StateError('No Discord Activity context');
      }
      return <String, Object?>{'id': 'channel-1'};
    }
    if (methodName == 'custom') {
      return <String, Object?>{'ok': true};
    }
    throw StateError('Unknown method: $methodName');
  }
}
