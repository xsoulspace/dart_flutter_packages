// ignore_for_file: close_sinks
// (the inbound controllers close in close()/transport close(); the lint
// cannot trace the indirection)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ephemeral_frame.dart';
import 'mesh_peer.dart';
import 'mesh_transport.dart';

/// A LAN transport that owns a listening socket: the host-side lifecycle
/// ([start]/[port]/[close]) plus the generic [MeshTransport] seams.
///
/// Proven in vosges' gesture mesh (controller/desktop, paired sessions)
/// and lifted here (2026-10-06) so every mesh family member shares one
/// LAN control-channel transport instead of forking it.
abstract interface class LanMeshTransport implements MeshTransport {
  /// Binds the LAN listener. Idempotent per instance.
  Future<void> start({int port = 0});

  /// The bound port (0 before [start], or after an explicit rebind).
  int get port;

  /// Closes the listener and every socket it owns.
  Future<void> close();
}

/// Signs (or verifies) an authentication frame over this channel. The
/// frame carries purpose + nonce + sequence in its payload; the
/// signature commits to the whole frame (ADR 0031 §3 canonical bytes).
/// Closure seams, not interfaces: implementers already hold identity
/// material shaped for their own package (vosges' `EphemeralFrameSigner`,
/// the doc mesh's presence signer) — a lambda adapts in one line.
typedef LanFrameSealer =
    Future<Uint8List> Function(MeshEphemeralFrame frame);

/// Verifies an authentication frame against the sender's REGISTERED
/// identity key. False (or a throw) means the frame is untrusted.
typedef LanFrameVerifier = Future<bool> Function(MeshEphemeralFrame frame);

/// Publishes this device's identity key bytes for the peer to verify
/// against (optional; null = the peer already knows this identity from
/// pairing).
typedef LanIdentityPublisher = Future<List<int>?> Function();

/// Direct same-LAN WebSocket transport for paired mesh sessions.
///
/// Wire: one JSON hello/ack handshake (nonce-bound), then binary-or-text
/// payload frames. When [frameSealer] and [frameVerifier] are supplied,
/// the hello is nonce-bound and every payload frame is signed and
/// verified with the paired Ed25519 identity material, with strict
/// inbound sequence monotonicity. Authentication failure is
/// CONNECTION-FATAL by law: a peer that cannot prove its paired identity
/// must not remain a session source. The unsigned mode is retained only
/// for deterministic local tests and must not be used for paired LAN
/// sessions.
final class WebSocketLanTransport implements LanMeshTransport {
  WebSocketLanTransport({
    required this.selfId,
    this.bindHost = '0.0.0.0',
    this.path = '/mesh/lan',
    this.helloKind = 'mesh_hello',
    this.helloAckKind = 'mesh_hello_ack',
    this.channelId = 'mesh/lan',
    this.frameSealer,
    this.frameVerifier,
    this.identityPublisher,
    this.requireAuthentication = false,
  }) : assert(
         !requireAuthentication ||
             (frameSealer != null && frameVerifier != null),
         'authenticated mode requires both sealer and verifier',
       ),
       assert(
         (frameSealer == null) == (frameVerifier == null),
         'sealer and verifier must be supplied together',
       );

  final String selfId;
  final String bindHost;
  final String path;

  /// The hello/ack `kind` discriminators on the wire. Override to
  /// interoperate with an existing deployment's vocabulary (vosges uses
  /// `vosges_hello`/`vosges_hello_ack`).
  final String helloKind;
  final String helloAckKind;

  /// The ephemeral-frame `docId` this channel signs under (opaque to the
  /// frame codec; names the channel in every auth frame).
  final String channelId;
  final LanFrameSealer? frameSealer;
  final LanFrameVerifier? frameVerifier;
  final LanIdentityPublisher? identityPublisher;
  final bool requireAuthentication;
  final StreamController<MeshSession> _incoming =
      StreamController<MeshSession>.broadcast();
  HttpServer? _server;

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  @override
  int get port => _server?.port ?? 0;

  @override
  Future<void> start({int port = 0}) async {
    if (_server != null) return;
    _server = await HttpServer.bind(bindHost, port);
    _server!.listen((request) => unawaited(_handleRequest(request)));
  }

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final host = peer.endpointHints['host'];
    final portText = peer.endpointHints['port'];
    final port = int.tryParse(portText ?? '');
    if (host == null || port == null || port <= 0) {
      throw MeshConnectionException(peer.peerId, 'missing host/port hint');
    }
    final endpointPath = peer.endpointHints['path'] ?? path;
    final normalizedPath = endpointPath.startsWith('/')
        ? endpointPath
        : '/$endpointPath';
    try {
      final socket = await WebSocket.connect('ws://$host:$port$normalizedPath');
      final session = _LanSocketSession(
        socket,
        channelId: channelId,
        helloKind: helloKind,
        helloAckKind: helloAckKind,
        requireAuthentication: requireAuthentication,
        frameSealer: frameSealer,
        frameVerifier: frameVerifier,
        identityPublisher: identityPublisher,
        remotePeerId: peer.peerId,
      );
      await session.clientHandshake(selfId, expectedPeerId: peer.peerId);
      return session;
    } on Object catch (error) {
      throw MeshConnectionException(peer.peerId, '$error');
    }
  }

  Future<void> _handleRequest(final HttpRequest request) async {
    if (request.uri.path != path ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      final response = request.response..statusCode = HttpStatus.notFound;
      unawaited(response.close());
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final session = _LanSocketSession(
      socket,
      channelId: channelId,
      helloKind: helloKind,
      helloAckKind: helloAckKind,
      requireAuthentication: requireAuthentication,
      frameSealer: frameSealer,
      frameVerifier: frameVerifier,
    );
    try {
      final remotePeerId = await session.serverHandshake(selfId);
      session.remotePeerIdValue = remotePeerId;
      _incoming.add(session);
    } on Object {
      await session.close();
    }
  }

  @override
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    await _incoming.close();
  }
}

final class _LanSocketSession implements MeshSession {
  _LanSocketSession(
    this._socket, {
    required this.channelId,
    required this.helloKind,
    required this.helloAckKind,
    required this.requireAuthentication,
    this.frameSealer,
    this.frameVerifier,
    this.identityPublisher,
    String? remotePeerId,
  }) : remotePeerIdValue = remotePeerId {
    _subscription = _socket.listen(
      _receive,
      onError: _inbound.addError,
      onDone: _inbound.close,
      cancelOnError: false,
    );
  }

  final WebSocket _socket;
  final String channelId;
  final String helloKind;
  final String helloAckKind;
  final LanFrameSealer? frameSealer;
  final LanFrameVerifier? frameVerifier;
  final LanIdentityPublisher? identityPublisher;
  final bool requireAuthentication;
  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  // ignore: use_late_for_private_fields_and_variables — assigned in
  // the constructor BODY (needs the socket first), which `late final`
  // allows; the lint still flags it, keep the honest form.
  late final StreamSubscription<Object?> _subscription;
  String? remotePeerIdValue;
  String? _localPeerId;
  String? _sessionNonce;
  final Completer<Object?> _handshake = Completer<Object?>();
  bool _handshaken = false;
  bool _closed = false;
  int _nextAuthSequence = 0;
  int _lastInboundAuthSequence = -1;

  @override
  String get remotePeerId => remotePeerIdValue ?? '';

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  Future<void> clientHandshake(
    final String peerId, {
    required final String expectedPeerId,
  }) async {
    _localPeerId = peerId;
    _sessionNonce = _newNonce();
    final auth = await _encodeAuthFrame(
      fromPeerId: peerId,
      nonce: _sessionNonce!,
      sequence: 0,
      purpose: 'hello',
    );
    _socket.add(
      jsonEncode(<String, Object?>{
        'kind': helloKind,
        'peer_id': peerId,
        if (auth != null) 'auth': base64Encode(auth),
      }),
    );
    final response = await _handshake.future.timeout(
      const Duration(seconds: 5),
    );
    if (response is! Map ||
        response['kind'] != helloAckKind ||
        response['peer_id'] != expectedPeerId) {
      throw const FormatException('invalid mesh hello acknowledgement');
    }
    final nonce = _sessionNonce;
    if (nonce == null) throw StateError('handshake lost its nonce');
    await _verifyAuth(
      response['auth'],
      expectedPeerId: expectedPeerId,
      nonce: nonce,
      purpose: 'hello_ack',
    );
    _handshaken = true;
  }

  Future<String> serverHandshake(final String selfId) async {
    final message = await _handshake.future.timeout(const Duration(seconds: 5));
    if (message is! Map ||
        message['kind'] != helloKind ||
        message['peer_id'] is! String ||
        (message['peer_id'] as String).isEmpty) {
      throw const FormatException('invalid mesh hello');
    }
    final remotePeerId = message['peer_id'] as String;
    _localPeerId = selfId;
    _sessionNonce = await _verifyAuth(
      message['auth'],
      expectedPeerId: remotePeerId,
      purpose: 'hello',
    );
    final auth = await _encodeAuthFrame(
      fromPeerId: selfId,
      nonce: _sessionNonce!,
      sequence: 0,
      purpose: 'hello_ack',
    );
    _socket.add(
      jsonEncode(<String, Object?>{
        'kind': helloAckKind,
        'peer_id': selfId,
        if (auth != null) 'auth': base64Encode(auth),
      }),
    );
    _handshaken = true;
    return remotePeerId;
  }

  void _receive(final Object? data) {
    if (!_handshake.isCompleted) {
      try {
        final decoded = data is String
            ? jsonDecode(data)
            : jsonDecode(utf8.decode(_bytes(data)));
        _handshake.complete(decoded);
      } on Object catch (error, stackTrace) {
        _handshake.completeError(error, stackTrace);
      }
      return;
    }
    if (!_handshaken) return;
    if (frameVerifier == null) {
      _inbound.add(_bytes(data));
      return;
    }
    unawaited(_receiveAuthenticated(data));
  }

  Future<void> _receiveAuthenticated(final Object? data) async {
    try {
      final frame = _decodeAuthFrame(data);
      if (frame == null ||
          frame.fromPeerId != remotePeerId ||
          frame.payload['purpose'] != 'payload' ||
          frame.payload['nonce'] != _sessionNonce) {
        throw const FormatException('invalid authenticated payload frame');
      }
      final sequence = frame.payload['sequence'];
      if (sequence is! int || sequence <= _lastInboundAuthSequence) return;
      if (!await frameVerifier!(frame)) {
        throw const FormatException('payload frame authentication failed');
      }
      final encodedPayload = frame.payload['payload'];
      if (encodedPayload is! String) {
        throw const FormatException('authenticated payload is missing');
      }
      _lastInboundAuthSequence = sequence;
      _inbound.add(Uint8List.fromList(base64Decode(encodedPayload)));
    } on Object {
      // Authentication failures are connection-fatal. A peer that cannot
      // prove its paired identity must not remain a session source.
      await close();
    }
  }

  @override
  Future<void> send(final Uint8List payload) async {
    if (_closed || !_handshaken) throw StateError('session is not ready');
    if (frameSealer == null) {
      _socket.add(payload);
      return;
    }
    final encoded = await _encodeAuthFrame(
      fromPeerId: _localPeerId!,
      nonce: _sessionNonce!,
      sequence: ++_nextAuthSequence,
      purpose: 'payload',
      payload: payload,
    );
    _socket.add(encoded);
  }

  Future<Uint8List?> _encodeAuthFrame({
    required final String fromPeerId,
    required final String nonce,
    required final int sequence,
    required final String purpose,
    Uint8List? payload,
  }) async {
    final sealer = frameSealer;
    if (sealer == null) {
      if (requireAuthentication) {
        throw StateError('authenticated transport sealer is unavailable');
      }
      return null;
    }
    final framePayload = <String, Object?>{
      'purpose': purpose,
      'nonce': nonce,
      'sequence': sequence,
      if (payload != null) 'payload': base64Encode(payload),
    };
    final identity = identityPublisher;
    if (identity != null) {
      final identityKey = await identity();
      if (identityKey != null && identityKey.isNotEmpty) {
        framePayload['identity_key'] = base64Encode(identityKey);
      }
    }
    final frame = MeshEphemeralFrame(
      docId: channelId,
      fromPeerId: fromPeerId,
      event: MeshEphemeralEvent.ping,
      ttl: const Duration(seconds: 30),
      issuedAtMs: DateTime.now().millisecondsSinceEpoch,
      payload: framePayload,
    );
    final signature = await sealer(frame);
    return frame.withSignature(signature).encode();
  }

  Future<String> _verifyAuth(
    final Object? encoded, {
    required final String expectedPeerId,
    required final String purpose,
    String? nonce,
  }) async {
    final frame = _decodeAuthFrame(encoded);
    if (frame == null) {
      if (requireAuthentication) {
        throw const FormatException('authenticated mesh hello is required');
      }
      return nonce ?? '';
    }
    if (frame.fromPeerId != expectedPeerId ||
        frame.payload['purpose'] != purpose ||
        (nonce != null && frame.payload['nonce'] != nonce)) {
      throw const FormatException('invalid authenticated mesh hello');
    }
    if (!await frameVerifier!(frame)) {
      throw const FormatException('mesh hello authentication failed');
    }
    final frameNonce = frame.payload['nonce'];
    if (frameNonce is! String || frameNonce.isEmpty) {
      throw const FormatException('mesh hello nonce is missing');
    }
    return frameNonce;
  }

  MeshEphemeralFrame? _decodeAuthFrame(final Object? encoded) {
    try {
      final bytes = encoded is String ? base64Decode(encoded) : _bytes(encoded);
      return MeshEphemeralFrame.decode(bytes);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _socket.close();
    await _inbound.close();
  }
}

String _newNonce() {
  final random = math.Random.secure();
  return base64UrlEncode(
    List<int>.generate(24, (_) => random.nextInt(256), growable: false),
  );
}

Uint8List _bytes(final Object? data) => data is Uint8List
    ? data
    : data is List<int>
    ? Uint8List.fromList(data)
    : Uint8List.fromList(utf8.encode(data?.toString() ?? ''));
