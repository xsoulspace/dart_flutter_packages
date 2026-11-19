import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'grok_registration.dart';

/// Never includes response bodies, URLs, credentials or provider messages.
final class GrokAuthException implements Exception {
  const GrokAuthException(this.code);
  final String code;
  @override
  String toString() => 'GrokAuthException($code)';
}

/// The application supplies protected storage. One record per xAI subject.
abstract interface class GrokCredentialStore {
  Future<GrokAccount?> read(String subject);
  Future<void> write(GrokAccount account);
  Future<void> removeTokens(String subject);
}

/// UI-safe device prompt. The device code itself stays on the attempt.
final class GrokDevicePrompt {
  const GrokDevicePrompt({
    required this.userCode,
    required this.verificationUri,
    this.verificationUriComplete,
  });
  final String userCode;
  final Uri verificationUri;
  final Uri? verificationUriComplete;
  @override
  String toString() => 'GrokDevicePrompt(code shown to the account holder)';
}

final class GrokAccount {
  GrokAccount({
    required this.clientId,
    required this.subject,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required Set<String> scopes,
    this.email,
    this.idToken,
  }) : scopes = Set.unmodifiable(scopes);

  final String clientId;
  final String subject;
  final String? email;
  final String accessToken;
  final String refreshToken;
  final String? idToken;
  final DateTime expiresAt;
  final Set<String> scopes;

  bool get planEnabled => scopes.contains(LastAnswerGrokRegistration.planScope);

  Map<String, Object?> toStorageJson() => {
    'client_id': clientId,
    'subject': subject,
    'email': email,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'id_token': idToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'scopes': scopes.toList()..sort(),
  };

  factory GrokAccount.fromStorageJson(Map<String, dynamic> json) =>
      GrokAccount(
        clientId: json['client_id'] as String,
        subject: json['subject'] as String,
        email: json['email'] as String?,
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        idToken: json['id_token'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        scopes: (json['scopes'] as List).cast<String>().toSet(),
      );

  @override
  String toString() => 'GrokAccount(credentials redacted)';
}

final class GrokAuthorizationAttempt {
  GrokAuthorizationAttempt._({
    required this.authorizationUri,
    required this.redirectUri,
    required this.state,
    required this.nonce,
    required this.verifier,
    required this.createdAt,
    required this.clientId,
    this.expectedSubject,
  });

  final Uri authorizationUri;
  final Uri redirectUri;
  final String state;
  final String nonce;
  final String verifier;
  final DateTime createdAt;
  final String clientId;
  final String? expectedSubject;
  bool _consumed = false;
  bool cancelled = false;

  @override
  String toString() => 'GrokAuthorizationAttempt(redacted)';
}

final class GrokDeviceAttempt {
  GrokDeviceAttempt._({
    required this.prompt,
    required this.deviceCode,
    required this.expiresAt,
    required this.interval,
    required this.clientId,
    this.expectedSubject,
  });

  final GrokDevicePrompt prompt;
  final String deviceCode;
  final DateTime expiresAt;
  final Duration interval;
  final String clientId;
  final String? expectedSubject;
  bool cancelled = false;

  @override
  String toString() => 'GrokDeviceAttempt(redacted)';
}

/// Public-client OAuth against auth.x.ai. A missing client id refuses
/// before any network call. Identity-token signatures are not checked
/// here: the token response arrives on the issuer's TLS channel. Signature
/// verification against the issuer JWKS is still an open qualification.
final class GrokAuth {
  GrokAuth({
    required this.store,
    required this.registration,
    http.Client? client,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 30),
    Uri? authorizeEndpoint,
    Uri? tokenEndpoint,
    Uri? deviceEndpoint,
    Uri? revokeEndpoint,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? DateTime.now,
       authorizeEndpoint =
           authorizeEndpoint ??
           Uri.parse('${LastAnswerGrokRegistration.issuer}/oauth2/authorize'),
       tokenEndpoint =
           tokenEndpoint ??
           Uri.parse('${LastAnswerGrokRegistration.issuer}/oauth2/token'),
       deviceEndpoint =
           deviceEndpoint ??
           Uri.parse(
             '${LastAnswerGrokRegistration.issuer}/oauth2/device/code',
           ),
       revokeEndpoint =
           revokeEndpoint ??
           Uri.parse('${LastAnswerGrokRegistration.issuer}/oauth2/revoke');

  final GrokCredentialStore store;
  final LastAnswerGrokRegistration registration;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  final Uri authorizeEndpoint;
  final Uri tokenEndpoint;
  final Uri deviceEndpoint;
  final Uri revokeEndpoint;
  final Map<String, Future<GrokAccount>> _refreshes = {};

  void _requireRegistered() {
    if (!registration.isRegistered ||
        registration.clientId.contains(RegExp(r'\s'))) {
      throw const GrokAuthException('client_not_registered');
    }
  }

  GrokAuthorizationAttempt begin({String? expectedSubject, String? loginHint}) {
    _requireRegistered();
    if (expectedSubject != null && expectedSubject.isEmpty) {
      throw const GrokAuthException('invalid_authorization_configuration');
    }
    final state = _token();
    final nonce = _token();
    final verifier = _token();
    final redirect = Uri.parse(LastAnswerGrokRegistration.redirectUri);
    return GrokAuthorizationAttempt._(
      redirectUri: redirect,
      state: state,
      nonce: nonce,
      verifier: verifier,
      createdAt: _clock(),
      clientId: registration.clientId,
      expectedSubject: expectedSubject,
      authorizationUri: authorizeEndpoint.replace(
        queryParameters: {
          'response_type': 'code',
          'client_id': registration.clientId,
          'redirect_uri': redirect.toString(),
          'scope': registration.scopeString,
          'state': state,
          'nonce': nonce,
          'code_challenge_method': 'S256',
          'code_challenge': _base64(
            sha256.convert(utf8.encode(verifier)).bytes,
          ),
          'referrer': LastAnswerGrokRegistration.referrer,
          'plan': 'generic',
          if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
        },
      ),
    );
  }

  Future<GrokAccount> complete(
    GrokAuthorizationAttempt attempt,
    Uri callback,
  ) async {
    if (attempt._consumed ||
        attempt.cancelled ||
        _clock().difference(attempt.createdAt) > const Duration(minutes: 10)) {
      throw const GrokAuthException('authorization_expired');
    }
    final qp = callback.queryParametersAll;
    if (callback.scheme != attempt.redirectUri.scheme ||
        callback.host != attempt.redirectUri.host ||
        callback.port != attempt.redirectUri.port ||
        callback.path != attempt.redirectUri.path ||
        callback.hasFragment ||
        callback.userInfo.isNotEmpty ||
        qp.values.any((values) => values.length != 1) ||
        !_equal(callback.queryParameters['state'] ?? '', attempt.state)) {
      throw const GrokAuthException('invalid_callback');
    }
    attempt._consumed = true;
    if (callback.queryParameters.containsKey('error')) {
      throw const GrokAuthException('authorization_declined');
    }
    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const GrokAuthException('invalid_callback');
    }
    if (attempt.cancelled) {
      throw const GrokAuthException('authorization_cancelled');
    }
    final token = await _post(tokenEndpoint, {
      'grant_type': 'authorization_code',
      'client_id': attempt.clientId,
      'code': code,
      'code_verifier': attempt.verifier,
      'redirect_uri': attempt.redirectUri.toString(),
    });
    if (attempt.cancelled) {
      throw const GrokAuthException('authorization_cancelled');
    }
    final account = _account(token, attempt.clientId, nonce: attempt.nonce);
    _expectSubject(account, attempt.expectedSubject);
    await store.write(account);
    return account;
  }

  Future<GrokDeviceAttempt> beginDevice({String? expectedSubject}) async {
    _requireRegistered();
    final body = await _post(deviceEndpoint, {
      'client_id': registration.clientId,
      'scope': registration.scopeString,
    });
    final deviceCode = body['device_code'];
    final userCode = body['user_code'];
    final verification = body['verification_uri'];
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        verification is! String) {
      throw const GrokAuthException('token_exchange_failed');
    }
    final complete = body['verification_uri_complete'];
    final expires = _positiveInt(body['expires_in']) ?? 600;
    final interval = _positiveInt(body['interval']) ?? 5;
    return GrokDeviceAttempt._(
      deviceCode: deviceCode,
      expiresAt: _clock().add(Duration(seconds: expires)),
      interval: Duration(seconds: interval.clamp(1, 30)),
      clientId: registration.clientId,
      expectedSubject: expectedSubject,
      prompt: GrokDevicePrompt(
        userCode: userCode,
        verificationUri: Uri.parse(verification),
        verificationUriComplete: complete is String && complete.isNotEmpty
            ? Uri.tryParse(complete)
            : null,
      ),
    );
  }

  Future<GrokAccount> completeDevice(GrokDeviceAttempt attempt) async {
    var interval = attempt.interval;
    while (_clock().isBefore(attempt.expiresAt)) {
      if (attempt.cancelled) {
        throw const GrokAuthException('authorization_cancelled');
      }
      await Future<void>.delayed(interval);
      if (attempt.cancelled) {
        throw const GrokAuthException('authorization_cancelled');
      }
      final outcome = await _pollDevice(attempt);
      if (outcome.pending) {
        if (outcome.slowDown) {
          final next = interval.inSeconds + 5;
          interval = Duration(seconds: next.clamp(1, 30));
        }
        continue;
      }
      final account = outcome.account!;
      _expectSubject(account, attempt.expectedSubject);
      await store.write(account);
      return account;
    }
    throw const GrokAuthException('device_expired');
  }

  Future<({bool pending, bool slowDown, GrokAccount? account})> _pollDevice(
    GrokDeviceAttempt attempt,
  ) async {
    final response = await _send(tokenEndpoint, {
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      'client_id': attempt.clientId,
      'device_code': attempt.deviceCode,
    });
    if (response.statusCode == 200) {
      final body = _jsonObject(response.body);
      return (
        pending: false,
        slowDown: false,
        account: _account(body, attempt.clientId),
      );
    }
    final error = _errorCode(response.body);
    if (error == 'authorization_pending') {
      return (pending: true, slowDown: false, account: null);
    }
    if (error == 'slow_down') {
      return (pending: true, slowDown: true, account: null);
    }
    if (error == 'access_denied' || error == 'authorization_declined') {
      throw const GrokAuthException('authorization_declined');
    }
    if (error == 'expired_token') {
      throw const GrokAuthException('device_expired');
    }
    throw const GrokAuthException('token_exchange_failed');
  }

  Future<GrokAccount> accountForInference(String subject) {
    final existing = _refreshes[subject];
    if (existing != null) return existing;
    final flight = _accountForInference(subject).whenComplete(() {
      _refreshes.remove(subject);
    });
    _refreshes[subject] = flight;
    return flight;
  }

  Future<GrokAccount> _accountForInference(String subject) async {
    final account = await store.read(subject);
    if (account == null || account.accessToken.isEmpty) {
      throw const GrokAuthException('sign_in_required');
    }
    if (account.expiresAt.isAfter(_clock().add(const Duration(seconds: 60)))) {
      return account;
    }
    final response = await _send(tokenEndpoint, {
      'grant_type': 'refresh_token',
      'client_id': account.clientId,
      'refresh_token': account.refreshToken,
    });
    if (response.statusCode != 200) {
      final code = _errorCode(response.body) == 'invalid_grant'
          ? 'sign_in_required'
          : 'refresh_failed';
      throw GrokAuthException(code);
    }
    final body = _jsonObject(response.body);
    final refreshed = _account(
      body,
      account.clientId,
      previous: account,
    );
    if (refreshed.subject != account.subject) {
      throw const GrokAuthException('account_mismatch');
    }
    await store.write(refreshed);
    return refreshed;
  }

  /// Local tokens are removed either way. A non-200 revoke is unconfirmed.
  Future<bool> signOut(String subject) async {
    final account = await store.read(subject);
    await store.removeTokens(subject);
    if (account == null) return true;
    try {
      final response = await _send(revokeEndpoint, {
        'client_id': account.clientId,
        'token': account.refreshToken,
      });
      return response.statusCode == 200;
    } on Object {
      return false;
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<Map<String, dynamic>> _post(
    Uri endpoint,
    Map<String, String> fields,
  ) async {
    final response = await _send(endpoint, fields);
    if (response.statusCode != 200) {
      throw const GrokAuthException('token_exchange_failed');
    }
    return _jsonObject(response.body);
  }

  Future<http.Response> _send(Uri endpoint, Map<String, String> fields) {
    final body = fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return _client
        .post(
          endpoint,
          headers: const {
            'content-type': 'application/x-www-form-urlencoded',
            'accept': 'application/json',
          },
          body: body,
        )
        .timeout(requestTimeout);
  }

  GrokAccount _account(
    Map<String, dynamic> token,
    String clientId, {
    String? nonce,
    GrokAccount? previous,
  }) {
    final access = token['access_token'];
    final refresh = token['refresh_token'] ?? previous?.refreshToken;
    final idToken = token['id_token'] ?? previous?.idToken;
    final expires = _positiveInt(token['expires_in']);
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        idToken is! String ||
        expires == null) {
      throw const GrokAuthException('token_exchange_failed');
    }
    final claims = _claims(idToken);
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) {
      throw const GrokAuthException('token_exchange_failed');
    }
    if (nonce != null && claims['nonce'] != nonce) {
      throw const GrokAuthException('invalid_callback');
    }
    final aud = claims['aud'];
    final audienceOk = aud == clientId ||
        (aud is List && aud.contains(clientId));
    if (!audienceOk) throw const GrokAuthException('token_exchange_failed');
    final exp = claims['exp'];
    if (exp is num &&
        DateTime.fromMillisecondsSinceEpoch(
          exp.toInt() * 1000,
          isUtc: true,
        ).isBefore(_clock())) {
      throw const GrokAuthException('authorization_expired');
    }
    final scope = token['scope'];
    final scopes = scope is String
        ? scope.split(' ').where((part) => part.isNotEmpty).toSet()
        : previous?.scopes ?? <String>{};
    final email = claims['email'];
    return GrokAccount(
      clientId: clientId,
      subject: sub,
      email: email is String && email.isNotEmpty ? email : previous?.email,
      accessToken: access,
      refreshToken: refresh,
      idToken: idToken,
      expiresAt: _clock().add(Duration(seconds: expires)),
      scopes: scopes,
    );
  }

  void _expectSubject(GrokAccount account, String? expected) {
    if (expected != null && account.subject != expected) {
      throw const GrokAuthException('account_mismatch');
    }
  }

  Map<String, dynamic> _claims(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) {
      throw const GrokAuthException('token_exchange_failed');
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is! Map<String, dynamic>) {
        throw const GrokAuthException('token_exchange_failed');
      }
      return decoded;
    } on GrokAuthException {
      rethrow;
    } on Object {
      throw const GrokAuthException('token_exchange_failed');
    }
  }

  Map<String, dynamic> _jsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // The caller gets a stable code, never the body.
    }
    throw const GrokAuthException('token_exchange_failed');
  }

  static String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on Object {
      return null;
    }
    return null;
  }

  static int? _positiveInt(Object? value) {
    final parsed = switch (value) {
      final int number => number,
      final String text => int.tryParse(text),
      _ => null,
    };
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static String _token() {
    final bytes = _randomBytes(32);
    return _base64(bytes);
  }

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return [for (var i = 0; i < length; i++) random.nextInt(256)];
  }

  static String _base64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static bool _equal(String a, String b) {
    final left = utf8.encode(a);
    final right = utf8.encode(b);
    var diff = left.length ^ right.length;
    final count = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < count; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      diff |= x ^ y;
    }
    return diff == 0;
  }
}
