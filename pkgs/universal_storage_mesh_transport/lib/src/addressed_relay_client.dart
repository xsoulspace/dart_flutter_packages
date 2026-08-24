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
  final Map<String, _AddressedSession> _sessions = {};

  @override
  Stream<MeshSession> get incoming => _incoming.stream;

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
    _sendEnvelope(
      toPeerId: '',
      payload: utf8.encode('register'),
      kind: AddressedRelayProtocol.registerKind,
    );
    channel.stream.listen(
      (message) {
        if (message is! List<int>) return;
        final envelope = AddressedRelayProtocol.decode(message);
        if (envelope.toPeerId != selfId) return;
        if (envelope.kind == AddressedRelayProtocol.registerKind) return;
        if (envelope.kind == AddressedRelayProtocol.openKind) {
          _sessions.putIfAbsent(envelope.fromPeerId, () {
            final created = _AddressedSession(selfId, envelope.fromPeerId);
            created.client = this;
            scheduleMicrotask(() => _incoming.add(created));
            return created;
          });
          return;
        }
        final session = _sessions.putIfAbsent(envelope.fromPeerId, () {
          final created = _AddressedSession(selfId, envelope.fromPeerId);
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
      },
    );
  }

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final channel = await _requireChannel();
    final session = _AddressedSession(selfId, peer.peerId);
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
}

final class _AddressedSession implements MeshSession {
  _AddressedSession(this._selfId, this.remotePeerId);

  final String _selfId;
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
    _inbound.close();
  }

  @override
  Future<void> send(final Uint8List payload) async {
    _client?._route(remotePeerId, payload);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _inbound.close();
  }
}
