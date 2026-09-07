import 'dart:async';
import 'dart:typed_data';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'ephemeral_frame_transport.dart';

/// [EphemeralFrameTransport] adapter over [AddressedRelayClient] — "the
/// mesh relay transport is one implementation" (ADR 0031 §2). Presence
/// rides the SAME relay connection as durable anti-entropy (one socket
/// per peer), as its own logical channel: sends go out under the relay's
/// ephemeral envelope kind, broadcast-addressed so the relay fans them
/// out to every other registered peer; inbound ephemeral payloads are
/// consumed from the client's dedicated `ephemeralIncoming` stream, so
/// presence traffic never mixes with sync data.
///
/// The embedding app owns the client (connection lifecycle is app-layer
/// per ADR 0031 §1); the adapter owns nothing but its subscriptions —
/// call [dispose] when done.
final class AddressedRelayEphemeralTransport
    implements EphemeralFrameTransport {
  AddressedRelayEphemeralTransport({required AddressedRelayClient client})
    : _client = client {
    _framesSub = client.ephemeralIncoming.listen((bytes) {
      final frame = MeshEphemeralFrame.tryDecode(bytes);
      if (frame != null) _frames.add(frame);
    });
    _linkSub = client.onConnectionChanged.listen((connected) {
      _state = connected
          ? EphemeralLinkState.connected
          : EphemeralLinkState.disconnected;
      if (!_changes.isClosed) _changes.add(_state);
    });
    if (client.isConnected) {
      _state = EphemeralLinkState.connected;
      _changes.add(_state);
    }
  }

  final AddressedRelayClient _client;

  final _frames = StreamController<MeshEphemeralFrame>();
  final _changes = StreamController<EphemeralLinkState>.broadcast();
  StreamSubscription<Uint8List>? _framesSub;
  StreamSubscription<bool>? _linkSub;
  var _state = EphemeralLinkState.disconnected;

  @override
  Stream<MeshEphemeralFrame> get frames => _frames.stream;

  @override
  EphemeralLinkState get connectionState => _state;

  @override
  Stream<EphemeralLinkState> get connectionChanges => _changes.stream;

  @override
  Future<void> send(final MeshEphemeralFrame frame) =>
      _client.sendEphemeral(toPeerId: '', payload: frame.encode());

  /// Stops consuming the client and closes the adapter's streams. The
  /// underlying [AddressedRelayClient] stays owned by the caller.
  Future<void> dispose() async {
    await _framesSub?.cancel();
    await _linkSub?.cancel();
    // Never awaited: a listener-less single-subscription controller's
    // close future does not complete.
    unawaited(_frames.close());
    unawaited(_changes.close());
  }
}
