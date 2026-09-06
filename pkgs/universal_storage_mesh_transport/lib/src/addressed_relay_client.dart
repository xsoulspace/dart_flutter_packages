import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'addressed_relay_protocol.dart';
import 'mesh_peer.dart';
import 'mesh_transport.dart';

/// Client half of the reusable WebSocket addressed-relay SDK.
///
/// One physical socket can carry many logical [MeshSession]s. This keeps
/// sync semantics identical to direct transports while supporting browsers.
final class AddressedRelayClient implements MeshTransport {
  AddressedRelayClient({required this.selfId, required this.endpoint});

  final String selfId;
  final Uri endpoint;

  WebSocketChannel? _channel;
  final _incoming = StreamController<MeshSession>();
  final _ephemeralIncoming = StreamController<Uint8List>();
  final _connectionStates = StreamController<bool>.broadcast();
  var _connected = false;
  final Map<String, _AddressedSession> _sessions = {};

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

  /// Inbound ephemeral-frame payloads (ADR 0029 §1, ADR 0031 §2).
  ///
  /// Delivered in ADDITION to the historical session path below: existing
  /// consumers of [MeshSession.inbound] keep seeing every envelope kind,
  /// while ephemeral-frame adapters consume this dedicated stream so
  /// presence traffic never mixes with sync data. Buffered until listened.
  Stream<Uint8List> get ephemeralIncoming => _ephemeralIncoming.stream;

  /// Whether the relay socket is currently attached.
  bool get isConnected => _connected;

  /// Emits `true` when the relay socket attaches and `false` when it
  /// drops or is closed.
  Stream<bool> get onConnectionChanged => _connectionStates.stream;

  /// Connects to an addressed relay and registers [selfId].
  Future<void> openRelay() async {
    if (_channel != null) return;
    final channel = WebSocketChannel.connect(endpoint);
    await channel.ready;
    _attach(channel);
  }

  /// Attaches a channel already supplied by the host (useful on web or
  /// when the application owns connection lifecycle).
  void attach(final WebSocketChannel channel) {
    if (_channel != null && identical(_channel, channel)) return;
    _attach(channel);
  }

  void _attach(final WebSocketChannel channel) {
    _channel = channel;
    _setConnected(true);
    _sendEnvelope(
      toPeerId: '',
      payload: utf8.encode('register'),
      kind: AddressedRelayProtocol.registerKind,
    );
    channel.stream.listen(
      (message) {
        if (message is! List<int>) return;
        final envelope = AddressedRelayProtocol.decode(message);
        // Broadcast envelopes (empty `to`, ADR 0031 §2) are addressed to
        // every peer; directed ones only to us.
        if (envelope.toPeerId != selfId && envelope.toPeerId.isNotEmpty) {
          return;
        }
        if (envelope.kind == AddressedRelayProtocol.registerKind) return;
        // [AddressedRelayProtocol.ephemeralKind] (ADR 0029 §1) falls
        // through to the same delivery path as data: ephemeral frames are
        // relayed like other frames, with no durable treatment anywhere.
        // A copy also lands on [ephemeralIncoming] for the dedicated
        // presence channel (ADR 0031 §2).
        if (envelope.kind == AddressedRelayProtocol.ephemeralKind) {
          _ephemeralIncoming.add(Uint8List.fromList(envelope.payload));
        }
        if (envelope.kind == AddressedRelayProtocol.openKind) {
          _sessions.putIfAbsent(envelope.fromPeerId, () {
            final created = _AddressedSession(envelope.fromPeerId);
            created.client = this;
            scheduleMicrotask(() => _incoming.add(created));
            return created;
          });
          return;
        }
        final session = _sessions.putIfAbsent(envelope.fromPeerId, () {
          final created = _AddressedSession(envelope.fromPeerId);
          created.client = this;
          scheduleMicrotask(() => _incoming.add(created));
          return created;
        });
        session.receive(envelope.payload);
      },
      onDone: () {
        for (final session in _sessions.values) {
          session.closeRemote();
        }
        _sessions.clear();
        _channel = null;
        _setConnected(false);
      },
    );
  }

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    await _requireChannel();
    final session = _AddressedSession(peer.peerId);
    session.client = this;
    _sessions[peer.peerId] = session;
    _sendEnvelope(
      toPeerId: peer.peerId,
      payload: utf8.encode('open'),
      kind: AddressedRelayProtocol.openKind,
    );
    return session;
  }

  Future<WebSocketChannel> _requireChannel() async {
    if (_channel == null) await openRelay();
    return _channel!;
  }

  /// Closes the relay socket and all logical sessions.
  Future<void> close() async {
    for (final session in _sessions.values) {
      session.closeRemote();
    }
    _sessions.clear();
    await _incoming.close();
    await _ephemeralIncoming.close();
    _setConnected(false);
    await _connectionStates.close();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  void _setConnected(final bool value) {
    if (_connected == value) return;
    _connected = value;
    _connectionStates.add(value);
  }

  void _sendEnvelope({
    required final String toPeerId,
    required final List<int> payload,
    final String kind = AddressedRelayProtocol.dataKind,
  }) => _channel?.sink.add(
    AddressedRelayProtocol.encode(
      fromPeerId: selfId,
      toPeerId: toPeerId,
      payload: payload,
      kind: kind,
    ),
  );

  Future<void> _route(final String peerId, final Uint8List bytes) async {
    await _requireChannel();
    _sendEnvelope(toPeerId: peerId, payload: bytes);
  }

  /// Sends an ephemeral-frame payload (ADR 0029 §1) under the relay's
  /// [AddressedRelayProtocol.ephemeralKind] envelope kind. Ephemeral
  /// frames are relayed exactly like data — the receiver's delivery path
  /// is identical — but the explicit kind lets observability at the relay
  /// tell unlogged traffic apart from sync traffic, with no durable
  /// treatment anywhere.
  Future<void> sendEphemeral({
    required final String toPeerId,
    required final List<int> payload,
  }) async {
    await _requireChannel();
    _sendEnvelope(
      toPeerId: toPeerId,
      payload: payload,
      kind: AddressedRelayProtocol.ephemeralKind,
    );
  }
}

final class _AddressedSession implements MeshSession {
  _AddressedSession(this.remotePeerId);
  @override
  final String remotePeerId;
  final _inbound = StreamController<Uint8List>();
  AddressedRelayClient? _client;
  var _closed = false;

  // Assigned after construction because sessions are owned by the client.
  // ignore: avoid_setters_without_getters
  set client(final AddressedRelayClient client) => _client = client;

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  void receive(final Uint8List bytes) {
    if (!_closed) _inbound.add(bytes);
  }

  void closeRemote() {
    if (_closed) return;
    unawaited(_inbound.close());
  }

  @override
  Future<void> send(final Uint8List payload) =>
      _client?._route(remotePeerId, payload) ?? Future<void>.value();

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inbound.close();
  }
}
