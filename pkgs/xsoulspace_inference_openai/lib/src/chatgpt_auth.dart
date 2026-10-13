import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;

/// Never includes response bodies, URLs, credentials or provider messages.
final class ChatGptAuthException implements Exception {
  const ChatGptAuthException(this.code);
  final String code;
  @override
  String toString() => 'ChatGptAuthException($code)';
}

/// The application supplies protected storage. One record per issued client.
/// Implementations must atomically replace the whole record on refresh.
abstract interface class ChatGptCredentialStore {
  Future<ChatGptAccount?> read(String clientId);
  Future<void> write(ChatGptAccount account);
  Future<void> removeTokens(String clientId);
}

/// Protected-store crash fence, persisted before any remote token mutation.
/// Ordinary reads refuse while fenced. Only explicit authorization or signout
/// may inspect the retained tokens for recovery; they are not inference grants.
abstract interface class RecoverableChatGptCredentialStore
    implements ChatGptCredentialStore {
  Future<ChatGptCredentialMutation> beginMutation(String clientId);
  Future<void> cancelMutation(String clientId);
  Future<void> finishMutation(
    String clientId, {
    bool cleanupConfirmed = true,
    bool rollback = false,
  });
}

final class ChatGptCredentialMutation {
  const ChatGptCredentialMutation({
    this.previous,
    required this.wasUnsettled,
    this.hasUnconfirmedCleanup = false,
  });
  final ChatGptAccount? previous;
  final bool wasUnsettled;
  final bool hasUnconfirmedCleanup;
}

/// Returning registration identity also survives sign-out without tokens.
final class ChatGptRegistration {
  const ChatGptRegistration({
    required this.clientId,
    required this.hostId,
    required this.subject,
    this.email,
    this.idTokenHint,
  });
  final String clientId;
  final String hostId;
  final String subject;
  final String? email;
  final String? idTokenHint;
  @override
  String toString() => 'ChatGptRegistration(identity and hint redacted)';
}

final class ChatGptAccount {
  ChatGptAccount({
    required this.clientId,
    required this.hostId,
    required this.subject,
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.expiresAt,
    required Set<String> scopes,
    this.email,
  }) : scopes = Set.unmodifiable(scopes);

  final String clientId;
  final String hostId;
  final String subject;
  final String? email;
  final String accessToken;
  final String refreshToken;
  final String idToken;
  final DateTime expiresAt;
  final Set<String> scopes;
  bool get planEnabled => scopes.contains('chatgpt.tokens.use.direct');
  ChatGptRegistration get registration => ChatGptRegistration(
    clientId: clientId,
    hostId: hostId,
    subject: subject,
    email: email,
    idTokenHint: idToken,
  );

  /// Secret-bearing serialization: only pass to protected credential storage.
  Map<String, Object?> toStorageJson() => {
    'client_id': clientId,
    'host_id': hostId,
    'subject': subject,
    'email': email,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'id_token': idToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'scopes': scopes.toList()..sort(),
  };

  factory ChatGptAccount.fromStorageJson(Map<String, dynamic> json) =>
      ChatGptAccount(
        clientId: json['client_id'] as String,
        hostId: json['host_id'] as String,
        subject: json['subject'] as String,
        email: json['email'] as String?,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        idToken: json['id_token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        scopes: (json['scopes'] as List).cast<String>().toSet(),
      );

  @override
  String toString() => 'ChatGptAccount(credentials redacted)';
}

final class ChatGptAuthorizationAttempt {
  ChatGptAuthorizationAttempt._({
    required this.authorizationUri,
    required this.redirectUri,
    required this.state,
    required this.nonce,
    required this.verifier,
    required this.hostId,
    required this.createdAt,
    this.account,
    this.registration,
    this.generation,
    required this.unboundGeneration,
  });
  final Uri authorizationUri;
  final Uri redirectUri;
  final String state;
  final String nonce;
  final String verifier;
  final String hostId;
  final DateTime createdAt;
  final ChatGptAccount? account;
  final ChatGptRegistration? registration;
  final int? generation;
  final int unboundGeneration;
  bool _consumed = false;
  bool _cancelled = false;
  bool _terminal = false;
  String? _clientId;
  Future<void>? _cancellation;
  Future<void>? _settlement;
  @override
  String toString() => 'ChatGptAuthorizationAttempt(redacted)';
}

/// Public-client SIWC registration. Authentication remains independent of
/// actor identity, world grants and model entitlement.
final class ChatGptAuth {
  ChatGptAuth({
    required this.store,
    http.Client? client,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? DateTime.now;

  static final _issuer = Uri.parse('https://auth.openai.com');
  static const _resource = 'https://api.openai.com/v1';
  final ChatGptCredentialStore store;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  final Map<String, Future<ChatGptAccount>> _refreshes = {};
  final Set<String> _signedOut = {};
  final Set<String> _quarantined = {};
  final Map<String, bool> _discardedRevocations = {};
  final Map<String, int> _generations = {};
  final Map<String, Future<void>> _lanes = {};
  int _unboundGeneration = 0;

  bool get hasUnconfirmedAuthorizationCleanup =>
      _discardedRevocations.values.any((confirmed) => !confirmed);

  /// Cancels an unfinished browser attempt, including token validation already
  /// in flight. No credentials may be published after its listener closes.
  Future<void> cancelAuthorization(ChatGptAuthorizationAttempt attempt) {
    if (attempt._terminal) return Future.value();
    attempt._cancelled = true;
    return attempt._cancellation ??= switch ((store, attempt._clientId)) {
      (
        final RecoverableChatGptCredentialStore durable,
        final String clientId,
      ) =>
        durable.cancelMutation(clientId),
      _ => Future.value(),
    };
  }

  Future<void> settleAuthorization(ChatGptAuthorizationAttempt attempt) async {
    await attempt._cancellation;
    await attempt._settlement;
  }

  Future<T> _serial<T>(String clientId, Future<T> Function() operation) {
    final result = Completer<T>();
    final preceding = _lanes[clientId] ?? Future<void>.value();
    final next = preceding.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _lanes[clientId] = next;
    unawaited(
      next.then((_) {
        if (identical(_lanes[clientId], next)) _lanes.remove(clientId);
      }),
    );
    return result.future;
  }

  static String createHostId() {
    final bytes = _randomBytes(16);
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  ChatGptAuthorizationAttempt begin({
    required String hostId,
    required String appName,
    required Uri redirectUri,
    ChatGptAccount? account,
    ChatGptRegistration? registration,
  }) {
    if (account != null && registration != null) {
      throw const ChatGptAuthException('ambiguous_registration');
    }
    final selected = registration ?? account?.registration;
    if (!RegExp(
          r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(hostId) ||
        redirectUri.scheme != 'http' ||
        redirectUri.host != '127.0.0.1' ||
        redirectUri.path != '/auth/callback' ||
        !redirectUri.hasPort ||
        redirectUri.userInfo.isNotEmpty ||
        redirectUri.hasQuery ||
        redirectUri.hasFragment ||
        appName.trim().isEmpty ||
        (selected != null &&
            (selected.hostId != hostId ||
                selected.clientId.isEmpty ||
                selected.clientId == 'dynamic_agent_client' ||
                selected.subject.isEmpty))) {
      throw const ChatGptAuthException('invalid_authorization_configuration');
    }
    final state = _randomToken();
    final nonce = _randomToken();
    final verifier = _randomToken();
    return ChatGptAuthorizationAttempt._(
      redirectUri: redirectUri,
      state: state,
      nonce: nonce,
      verifier: verifier,
      hostId: hostId,
      account: account,
      registration: selected,
      unboundGeneration: _unboundGeneration,
      generation: selected == null
          ? null
          : (_generations[selected.clientId] ?? 0),
      createdAt: _clock(),
      authorizationUri: _issuer
          .resolve('/api/accounts/authorize')
          .replace(
            queryParameters: {
              'client_id': selected?.clientId ?? 'dynamic_agent_client',
              if (selected == null) 'agent_name_hint': appName,
              'ext_agent_host_id': hostId,
              if (selected?.idTokenHint?.isNotEmpty == true &&
                  !_signedOut.contains(selected!.clientId))
                'id_token_hint': selected.idTokenHint!,
              'response_type': 'code',
              'redirect_uri': redirectUri.toString(),
              'scope':
                  'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct',
              'resource': _resource,
              'state': state,
              'nonce': nonce,
              'code_challenge_method': 'S256',
              'code_challenge': _base64(
                sha256.convert(utf8.encode(verifier)).bytes,
              ),
            },
          ),
    );
  }

  Future<ChatGptAccount> complete(
    ChatGptAuthorizationAttempt attempt,
    Uri callback,
  ) async {
    if (attempt._consumed ||
        attempt._cancelled ||
        _clock().difference(attempt.createdAt) > const Duration(minutes: 10)) {
      throw const ChatGptAuthException('authorization_expired');
    }
    final qp = callback.queryParametersAll;
    if (callback.scheme != attempt.redirectUri.scheme ||
        callback.host != attempt.redirectUri.host ||
        callback.port != attempt.redirectUri.port ||
        callback.path != attempt.redirectUri.path ||
        callback.hasFragment ||
        callback.userInfo.isNotEmpty ||
        qp.values.any((v) => v.length != 1) ||
        !_constantEquals(
          callback.queryParameters['state'] ?? '',
          attempt.state,
        )) {
      throw const ChatGptAuthException('invalid_callback');
    }
    attempt._consumed = true;
    if (callback.queryParameters.containsKey('error')) {
      throw const ChatGptAuthException('authorization_declined');
    }
    final clientId =
        callback.queryParameters['client_id'] ?? attempt.registration?.clientId;
    final code = callback.queryParameters['code'];
    if (clientId == null ||
        clientId.isEmpty ||
        clientId == 'dynamic_agent_client' ||
        code == null ||
        code.isEmpty ||
        (attempt.registration != null &&
            clientId != attempt.registration!.clientId)) {
      throw const ChatGptAuthException('registration_incomplete');
    }
    final generation = attempt.generation ?? (_generations[clientId] ?? 0);
    if (attempt.registration == null &&
        attempt.unboundGeneration != _unboundGeneration) {
      throw const ChatGptAuthException('authorization_cancelled');
    }
    final completion = _serial(
      clientId,
      () => _complete(attempt, clientId, code, generation),
    );
    attempt._clientId = clientId;
    attempt._settlement = completion.then<void>(
      (_) => attempt._terminal = true,
      onError: (Object _) {
        attempt._terminal = true;
      },
    );
    return completion;
  }

  Future<ChatGptAccount> _complete(
    ChatGptAuthorizationAttempt attempt,
    String clientId,
    String code,
    int generation,
  ) async {
    bool cancelled() =>
        attempt._cancelled || (_generations[clientId] ?? 0) != generation;
    if (cancelled()) {
      throw const ChatGptAuthException('authorization_cancelled');
    }
    final recoveryStore = store is RecoverableChatGptCredentialStore
        ? store as RecoverableChatGptCredentialStore
        : null;
    final mutation = await recoveryStore?.beginMutation(clientId);
    if (mutation?.hasUnconfirmedCleanup == true) {
      _discardedRevocations[clientId] = false;
    }
    final previous = mutation == null
        ? await store.read(clientId)
        : mutation.wasUnsettled
        ? null
        : mutation.previous;
    if (cancelled()) {
      await attempt._cancellation;
      if (mutation?.wasUnsettled != true) {
        await recoveryStore?.finishMutation(clientId, rollback: true);
      }
      throw const ChatGptAuthException('authorization_cancelled');
    }
    final token = await _postToken({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'code_verifier': attempt.verifier,
      'redirect_uri': attempt.redirectUri.toString(),
      'resource': _resource,
    });
    var rolledBack = false;
    Future<void> rollback() async {
      if (previous == null) {
        await store.removeTokens(clientId);
      } else {
        await store.write(previous);
      }
      rolledBack = true;
      _quarantined.remove(clientId);
    }

    try {
      final claims = await _validateIdToken(
        token['id_token'],
        clientId,
        attempt.nonce,
      );
      if (attempt.registration != null &&
          claims['sub'] != attempt.registration!.subject) {
        throw const ChatGptAuthException('account_mismatch');
      }
      final account = _account(token, clientId, attempt.hostId, claims);
      if (cancelled()) {
        await attempt._cancellation;
        if (mutation?.wasUnsettled != true) await rollback();
        throw const ChatGptAuthException('authorization_cancelled');
      }
      // Fence access until publication and any cancellation rollback settle.
      _quarantined.add(clientId);
      await store.write(account);
      await attempt._cancellation;
      if (cancelled()) {
        await rollback();
        throw const ChatGptAuthException('authorization_cancelled');
      }
      await recoveryStore?.finishMutation(clientId);
      await attempt._cancellation;
      if (cancelled()) {
        await rollback();
        throw const ChatGptAuthException('authorization_cancelled');
      }
      _quarantined.remove(clientId);
      _signedOut.remove(clientId);
      return account;
    } catch (error) {
      if (error is ChatGptAuthException &&
          error.code == 'credential_mutation_cancelled') {
        await attempt._cancellation;
        await rollback();
      }
      final refresh = token['refresh_token'];
      final confirmed = refresh is String && refresh.isNotEmpty
          ? await _revoke(clientId, refresh)
          : false;
      _discardedRevocations[clientId] =
          (_discardedRevocations[clientId] ?? true) && confirmed;
      if (_quarantined.contains(clientId)) {
        throw const ChatGptAuthException('credential_publication_unsettled');
      }
      // A failed recovery does not reauthorize abandoned retained credentials.
      if (mutation?.wasUnsettled != true || rolledBack) {
        await recoveryStore?.finishMutation(
          clientId,
          cleanupConfirmed: confirmed,
          rollback: rolledBack,
        );
      }
      if (!confirmed) {
        throw const ChatGptAuthException('authorization_cleanup_unconfirmed');
      }
      if (rolledBack) {
        throw const ChatGptAuthException('authorization_cancelled');
      }
      rethrow;
    }
  }

  Future<ChatGptAccount> accountForInference(String clientId) async {
    // Join the live mutation owner; an abandoned fence requires recovery.
    final activeRefresh = _refreshes[clientId];
    if (activeRefresh != null) await activeRefresh;
    if (_quarantined.contains(clientId)) {
      throw const ChatGptAuthException('credential_publication_unsettled');
    }
    if (_signedOut.contains(clientId)) {
      throw const ChatGptAuthException('sign_in_required');
    }
    var account = await _serial(clientId, () => store.read(clientId));
    if (_quarantined.contains(clientId)) {
      throw const ChatGptAuthException('credential_publication_unsettled');
    }
    if (account == null) throw const ChatGptAuthException('sign_in_required');
    if (!account.planEnabled) {
      throw const ChatGptAuthException('plan_permission_required');
    }
    if (!account.expiresAt.isAfter(_clock().add(const Duration(minutes: 1)))) {
      account = await refresh(clientId);
    }
    if (_signedOut.contains(clientId)) {
      throw const ChatGptAuthException('sign_in_required');
    }
    if (!account.planEnabled) {
      throw const ChatGptAuthException('plan_permission_required');
    }
    return account;
  }

  /// Coalesces rotation per registration. One auth owner must serve a shared
  /// credential store; separate processes must serialize through that owner.
  Future<ChatGptAccount> refresh(String clientId) => _refreshes.putIfAbsent(
    clientId,
    () => _serial(clientId, () => _refresh(clientId)).whenComplete(() {
      _refreshes.remove(clientId);
    }),
  );

  Future<ChatGptAccount> _refresh(String clientId) async {
    if (_quarantined.contains(clientId)) {
      throw const ChatGptAuthException('credential_publication_unsettled');
    }
    if (_signedOut.contains(clientId)) {
      throw const ChatGptAuthException('sign_in_required');
    }
    final old = await store.read(clientId);
    if (old == null) throw const ChatGptAuthException('sign_in_required');
    final recoveryStore = store is RecoverableChatGptCredentialStore
        ? store as RecoverableChatGptCredentialStore
        : null;
    await recoveryStore?.beginMutation(clientId);
    _quarantined.add(clientId);
    final token = await _postToken({
      'grant_type': 'refresh_token',
      'client_id': old.clientId,
      'refresh_token': old.refreshToken,
      'resource': _resource,
    });
    // A refresh need not supply a new ID token. A supplied one must validate.
    final claims = token['id_token'] == null
        ? <String, dynamic>{'sub': old.subject, 'email': old.email}
        : await _validateIdToken(token['id_token'], clientId, null);
    if (claims['sub'] != old.subject) {
      throw const ChatGptAuthException('account_mismatch');
    }
    final updated = _account(
      token,
      clientId,
      old.hostId,
      claims,
      previous: old,
    );
    await store.write(updated);
    await recoveryStore?.finishMutation(clientId);
    _quarantined.remove(clientId);
    return updated;
  }

  /// Returns whether remote revocation was confirmed. Local tokens are always
  /// cleared; the UI must disclose unconfirmed remote revocation.
  Future<bool> signOut(String clientId) async {
    _signedOut.add(clientId);
    _unboundGeneration++;
    _generations[clientId] = (_generations[clientId] ?? 0) + 1;
    return _serial(clientId, () => _signOut(clientId));
  }

  Future<bool> _signOut(String clientId) async {
    final recoveryStore = store is RecoverableChatGptCredentialStore
        ? store as RecoverableChatGptCredentialStore
        : null;
    final mutation = await recoveryStore?.beginMutation(clientId);
    final account = mutation == null
        ? await store.read(clientId)
        : mutation.previous;
    final revoked =
        account == null || await _revoke(clientId, account.refreshToken);
    await store.removeTokens(clientId);
    final cleanupConfirmed =
        revoked &&
        !(mutation?.wasUnsettled ?? false) &&
        !(mutation?.hasUnconfirmedCleanup ?? false) &&
        (_discardedRevocations.remove(clientId) ?? true);
    await recoveryStore?.finishMutation(
      clientId,
      cleanupConfirmed: cleanupConfirmed,
    );
    _quarantined.remove(clientId);
    return cleanupConfirmed;
  }

  Future<bool> _revoke(String clientId, String refreshToken) async {
    try {
      final discovery = await _getJson(
        _issuer.resolve('/.well-known/openid-configuration'),
      );
      final endpoint = _trustedAuthUri(discovery['revocation_endpoint']);
      final response = await _request(
        endpoint,
        body: {
          'token': refreshToken,
          'token_type_hint': 'refresh_token',
          'client_id': clientId,
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  ChatGptAccount _account(
    Map<String, dynamic> token,
    String clientId,
    String hostId,
    Map<String, dynamic> claims, {
    ChatGptAccount? previous,
  }) {
    final access = token['access_token'];
    final refresh = token['refresh_token'] ?? previous?.refreshToken;
    final id = token['id_token'] ?? previous?.idToken;
    final expiry = token['expires_in'];
    final scope = token['scope'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        id is! String ||
        id.isEmpty ||
        expiry is! int ||
        expiry <= 0 ||
        token['token_type'] != 'Bearer' ||
        (scope != null && scope is! String) ||
        (scope == null && previous == null)) {
      throw const ChatGptAuthException('invalid_token_response');
    }
    return ChatGptAccount(
      clientId: clientId,
      hostId: hostId,
      subject: claims['sub'] as String,
      email: claims['email'] as String?,
      accessToken: access,
      refreshToken: refresh,
      idToken: id,
      expiresAt: _clock().add(Duration(seconds: expiry)),
      scopes: scope is String
          ? scope.split(' ').where((s) => s.isNotEmpty).toSet()
          : previous!.scopes,
    );
  }

  Future<Map<String, dynamic>> _postToken(Map<String, String> body) async {
    try {
      final response = await _request(
        _issuer.resolve('/api/accounts/oauth/token'),
        body: body,
      );
      if (response.statusCode != 200) {
        throw const ChatGptAuthException('token_exchange_failed');
      }
      return _decodeObject(response.body);
    } on ChatGptAuthException {
      rethrow;
    } catch (_) {
      throw const ChatGptAuthException('auth_transport_failed');
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _request(uri);
    if (response.statusCode != 200) {
      throw const ChatGptAuthException('identity_discovery_failed');
    }
    return _decodeObject(response.body);
  }

  Future<http.Response> _request(Uri uri, {Map<String, String>? body}) async {
    final request = http.Request(body == null ? 'GET' : 'POST', uri)
      ..followRedirects = false;
    if (body != null) request.bodyFields = body;
    return await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(requestTimeout);
  }

  Future<Map<String, dynamic>> _validateIdToken(
    Object? raw,
    String clientId,
    String? nonce,
  ) async {
    try {
      if (raw is! String || raw.length > 32768) throw const FormatException();
      final parts = raw.split('.');
      if (parts.length != 3) throw const FormatException();
      final header = _decodeObject(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      if (header['alg'] != 'RS256' ||
          header['kid'] is! String ||
          header.containsKey('crit')) {
        throw const FormatException();
      }
      final discovery = await _getJson(
        _issuer.resolve('/.well-known/openid-configuration'),
      );
      if (discovery['issuer'] != _issuer.toString()) {
        throw const FormatException();
      }
      final jwks = await _getJson(_trustedAuthUri(discovery['jwks_uri']));
      final keys = (jwks['keys'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (k) =>
                k['kid'] == header['kid'] &&
                k['kty'] == 'RSA' &&
                (k['alg'] == null || k['alg'] == 'RS256') &&
                (k['use'] == null || k['use'] == 'sig'),
          )
          .toList();
      if (keys.length != 1) throw const FormatException();
      final key = keys.single;
      final modulus = _unsigned(key['n'] as String);
      if (modulus.bitLength < 2048) throw const FormatException();
      final signer = pc.Signer('SHA-256/RSA')
        ..init(
          false,
          pc.PublicKeyParameter<pc.RSAPublicKey>(
            pc.RSAPublicKey(modulus, _unsigned(key['e'] as String)),
          ),
        );
      if (!signer.verifySignature(
        Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}')),
        pc.RSASignature(base64Url.decode(base64Url.normalize(parts[2]))),
      )) {
        throw const FormatException();
      }
      final claims = _decodeObject(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final audience = claims['aud'];
      final now = _clock().millisecondsSinceEpoch ~/ 1000;
      if (claims['iss'] != _issuer.toString() ||
          !(audience == clientId ||
              audience is List && audience.contains(clientId)) ||
          (audience is List &&
              audience.length > 1 &&
              claims['azp'] != clientId) ||
          claims['exp'] is! int ||
          (claims['exp'] as int) <= now ||
          (claims['nbf'] != null &&
              (claims['nbf'] is! int || (claims['nbf'] as int) > now)) ||
          claims['sub'] is! String ||
          (claims['sub'] as String).isEmpty ||
          (nonce != null &&
              !_constantEquals(claims['nonce'] as String? ?? '', nonce))) {
        throw const FormatException();
      }
      return claims;
    } catch (_) {
      throw const ChatGptAuthException('invalid_id_token');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

Uri _trustedAuthUri(Object? raw) {
  final uri = Uri.tryParse(raw is String ? raw : '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'auth.openai.com' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const ChatGptAuthException('untrusted_identity_endpoint');
  }
  return uri;
}

Map<String, dynamic> _decodeObject(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const ChatGptAuthException('invalid_json');
  }
  return decoded;
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

String _base64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
String _randomToken() => _base64(_randomBytes(32));
bool _constantEquals(String a, String b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ (i < b.length ? b.codeUnitAt(i) : 0);
  }
  return difference == 0;
}

BigInt _unsigned(String value) => base64Url
    .decode(base64Url.normalize(value))
    .fold(BigInt.zero, (result, byte) => (result << 8) | BigInt.from(byte));
