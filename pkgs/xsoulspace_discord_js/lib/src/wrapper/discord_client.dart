import 'converters.dart';
import 'models.dart';

/// High-level Discord Embedded App SDK wrapper.
class DiscordClient {
  DiscordClient(this._sdk);

  final Object _sdk;

  Object get rawClient => _sdk;

  Future<void> ready() async {
    await jsCallPromise(_sdk, 'ready');
  }

  Future<Map<String, Object?>> authorize(
    final DiscordAuthorizeRequest request,
  ) async {
    final result = await _callCommand('authorize', request.toJson());
    return asMap(result);
  }

  Future<DiscordAuthenticateResult> authenticate({
    final String? accessToken,
  }) async {
    final payload = <String, Object?>{};
    if (accessToken != null && accessToken.isNotEmpty) {
      payload['access_token'] = accessToken;
    }

    final result = await _callCommand(
      'authenticate',
      payload.isEmpty ? null : payload,
    );

    return DiscordAuthenticateResult.fromMap(asMap(result));
  }

  Future<DiscordUser?> getUser({required final String id}) async {
    final result = await _callCommand('getUser', <String, Object?>{'id': id});
    final map = asMap(result);
    if (map.isEmpty) {
      return null;
    }
    return DiscordUser.fromMap(map);
  }

  Future<List<DiscordRelationship>> getRelationships() async {
    final result = asMap(await _callCommand('getRelationships'));
    final relationships = asList(result['relationships'] ?? result['items']);

    return relationships
        .map(asMap)
        .where((final map) => map.isNotEmpty)
        .map(DiscordRelationship.fromMap)
        .toList(growable: false);
  }

  Future<Map<String, Object?>> openInviteDialog() async {
    return asMap(await _callCommand('openInviteDialog'));
  }

  Future<Map<String, Object?>> inviteUserEmbedded({
    required final String userId,
    final String? content,
  }) async {
    return asMap(
      await _callCommand('inviteUserEmbedded', <String, Object?>{
        'user_id': userId,
        if (content != null && content.isNotEmpty) 'content': content,
      }),
    );
  }

  Future<DiscordShareLinkResult> shareLink({
    required final String message,
    final String? customId,
    final String? linkId,
  }) async {
    final result = asMap(
      await _callCommand('shareLink', <String, Object?>{
        'message': message,
        if (customId != null && customId.isNotEmpty) 'custom_id': customId,
        if (linkId != null && linkId.isNotEmpty) 'link_id': linkId,
      }),
    );
    return DiscordShareLinkResult.fromMap(result);
  }

  Future<Map<String, Object?>> openShareMomentDialog({
    required final String mediaUrl,
  }) async {
    return asMap(
      await _callCommand('openShareMomentDialog', <String, Object?>{
        'mediaUrl': mediaUrl,
      }),
    );
  }

  Future<DiscordEventSubscription> onCurrentUserUpdate(
    final void Function(DiscordUser? user) listener,
  ) {
    return onRawEvent('CURRENT_USER_UPDATE', (final event) {
      final data = event.data['user'];
      final map = data == null ? event.data : asMap(data);
      if (map.isEmpty) {
        listener(null);
        return;
      }
      listener(DiscordUser.fromMap(map));
    });
  }

  Future<DiscordEventSubscription> onRelationshipUpdate(
    final void Function(DiscordRelationship relationship) listener,
  ) {
    return onRawEvent('RELATIONSHIP_UPDATE', (final event) {
      final relationshipMap = asMap(event.data['relationship']);
      final payload = relationshipMap.isEmpty ? event.data : relationshipMap;
      if (payload.isEmpty) {
        return;
      }
      listener(DiscordRelationship.fromMap(payload));
    });
  }

  Future<DiscordEventSubscription> onRawEvent(
    final String event,
    final void Function(DiscordEventData event) listener, {
    final Map<String, Object?>? subscribeArgs,
  }) async {
    final jsListener = allowInterop((final Object? payload) {
      runGuarded(() {
        listener(DiscordEventData(event: event, data: asMap(payload)));
      });
    });

    final args = <Object?>[event, jsListener];
    if (subscribeArgs != null && subscribeArgs.isNotEmpty) {
      args.add(jsify(subscribeArgs));
    }

    await jsCallPromise(_sdk, 'subscribe', args);

    return DiscordEventSubscription(
      onCancel: () async {
        final unsubscribeArgs = <Object?>[event, jsListener];
        if (subscribeArgs != null && subscribeArgs.isNotEmpty) {
          unsubscribeArgs.add(jsify(subscribeArgs));
        }
        await jsCallPromise(_sdk, 'unsubscribe', unsubscribeArgs);
      },
    );
  }

  Future<Object?> callRawCommand(
    final String methodName, {
    final Map<String, Object?>? params,
  }) async {
    final commands = _commandsObject();

    if (prop(commands, methodName) != null) {
      return _callCommand(methodName, params);
    }

    if (prop(_sdk, methodName) != null) {
      if (params == null || params.isEmpty) {
        return jsCallPromise(_sdk, methodName);
      }
      return jsCallPromise(_sdk, methodName, <Object?>[jsify(params)]);
    }

    throw StateError('Discord SDK method `$methodName` is not available.');
  }

  Future<Object?> _callCommand(
    final String methodName, [
    final Map<String, Object?>? payload,
  ]) {
    final commands = _commandsObject();
    if (prop(commands, methodName) == null) {
      throw StateError('Discord SDK command `$methodName` is not available.');
    }

    if (payload == null || payload.isEmpty) {
      return jsCallPromise(commands, methodName);
    }
    return jsCallPromise(commands, methodName, <Object?>[jsify(payload)]);
  }

  Object _commandsObject() {
    final commands = prop(_sdk, 'commands');
    if (commands == null) {
      throw StateError('Discord SDK commands object is not available.');
    }
    return commands;
  }
}
