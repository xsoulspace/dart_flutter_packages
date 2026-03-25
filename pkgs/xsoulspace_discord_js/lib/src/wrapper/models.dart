import 'package:meta/meta.dart';

@immutable
final class DiscordAuthorizeRequest {
  const DiscordAuthorizeRequest({
    required this.clientId,
    required this.scope,
    this.responseType = 'code',
    this.codeChallenge,
    this.state,
    this.prompt,
    this.codeChallengeMethod,
  });

  final String clientId;
  final List<String> scope;
  final String responseType;
  final String? codeChallenge;
  final String? state;
  final String? prompt;
  final String? codeChallengeMethod;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'client_id': clientId,
      'scope': scope,
      'response_type': responseType,
      if (codeChallenge != null) 'code_challenge': codeChallenge,
      if (state != null) 'state': state,
      if (prompt != null) 'prompt': prompt,
      if (codeChallengeMethod != null)
        'code_challenge_method': codeChallengeMethod,
    };
  }
}

@immutable
final class DiscordUser {
  const DiscordUser({
    required this.id,
    required this.displayName,
    this.username,
    this.discriminator,
    this.avatarUrl,
    this.isBot = false,
    this.metadata = const <String, Object?>{},
  });

  factory DiscordUser.fromMap(final Map<String, Object?> map) {
    final id = (map['id'] ?? map['user_id'])?.toString() ?? 'unknown';
    final username = map['username']?.toString();
    final globalName = map['global_name']?.toString();
    final displayName = _firstNonEmpty(<String?>[
      globalName,
      username,
      map['displayName']?.toString(),
    ]);

    return DiscordUser(
      id: id,
      displayName: displayName ?? 'Unknown',
      username: username,
      discriminator: map['discriminator']?.toString(),
      avatarUrl: _avatarUrl(map),
      isBot: map['bot'] == true,
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String id;
  final String displayName;
  final String? username;
  final String? discriminator;
  final String? avatarUrl;
  final bool isBot;
  final Map<String, Object?> metadata;
}

@immutable
final class DiscordRelationship {
  const DiscordRelationship({
    required this.type,
    required this.user,
    this.metadata = const <String, Object?>{},
  });

  factory DiscordRelationship.fromMap(final Map<String, Object?> map) {
    final userMap = map['user'];
    return DiscordRelationship(
      type: (map['type'] as num?)?.toInt() ?? 0,
      user: DiscordUser.fromMap(
        userMap is Map<Object?, Object?>
            ? userMap.map(
                (final key, final value) => MapEntry(key.toString(), value),
              )
            : const <String, Object?>{},
      ),
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  /// Discord relationship type. `1` is friendship.
  final int type;
  final DiscordUser user;
  final Map<String, Object?> metadata;
}

@immutable
final class DiscordAuthenticateResult {
  const DiscordAuthenticateResult({
    required this.accessToken,
    required this.user,
    this.scopes = const <String>[],
    this.expires,
    this.application = const <String, Object?>{},
    this.metadata = const <String, Object?>{},
  });

  factory DiscordAuthenticateResult.fromMap(final Map<String, Object?> map) {
    final scopesRaw = map['scopes'];
    final scopes = scopesRaw is List
        ? scopesRaw
              .map((final value) => value.toString())
              .toList(growable: false)
        : const <String>[];

    final appRaw = map['application'];
    final application = appRaw is Map<Object?, Object?>
        ? Map<String, Object?>.unmodifiable(
            appRaw.map(
              (final key, final value) => MapEntry(key.toString(), value),
            ),
          )
        : const <String, Object?>{};

    return DiscordAuthenticateResult(
      accessToken:
          (map['access_token'] ?? map['accessToken'])?.toString() ?? '',
      user: DiscordUser.fromMap(
        map['user'] is Map<Object?, Object?>
            ? (map['user']! as Map<Object?, Object?>).map(
                (final key, final value) => MapEntry(key.toString(), value),
              )
            : const <String, Object?>{},
      ),
      scopes: scopes,
      expires: map['expires']?.toString(),
      application: application,
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String accessToken;
  final DiscordUser user;
  final List<String> scopes;
  final String? expires;
  final Map<String, Object?> application;
  final Map<String, Object?> metadata;
}

@immutable
final class DiscordShareLinkResult {
  const DiscordShareLinkResult({
    required this.success,
    required this.didCopyLink,
    required this.didSendMessage,
    this.metadata = const <String, Object?>{},
  });

  factory DiscordShareLinkResult.fromMap(final Map<String, Object?> map) {
    return DiscordShareLinkResult(
      success: map['success'] == true,
      didCopyLink: map['didCopyLink'] == true,
      didSendMessage: map['didSendMessage'] == true,
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final bool success;
  final bool didCopyLink;
  final bool didSendMessage;
  final Map<String, Object?> metadata;
}

@immutable
final class DiscordEventData {
  const DiscordEventData({required this.event, required this.data});

  final String event;
  final Map<String, Object?> data;
}

final class DiscordEventSubscription {
  DiscordEventSubscription({required final Future<void> Function() onCancel})
    : _onCancel = onCancel;

  final Future<void> Function() _onCancel;

  var _isCancelled = false;

  Future<void> cancel() async {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    await _onCancel();
  }
}

String? _firstNonEmpty(final Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _avatarUrl(final Map<String, Object?> map) {
  final explicit = map['avatarUrl']?.toString();
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }

  final id = map['id']?.toString();
  final avatarHash = map['avatar']?.toString();
  if (id == null || id.isEmpty || avatarHash == null || avatarHash.isEmpty) {
    return null;
  }

  return 'https://cdn.discordapp.com/avatars/$id/$avatarHash.png';
}
