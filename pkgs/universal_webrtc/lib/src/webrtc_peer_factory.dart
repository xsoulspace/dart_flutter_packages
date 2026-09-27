import 'dart:async';

import 'package:meta/meta.dart';
import 'package:universal_webrtc_raw/universal_webrtc_raw.dart';

import 'signaling_channel.dart';

/// Who a peer is in the frame-flow contract.
///
/// Per ADR 0037's proven loopback semantics: the **offerer receives**
/// frames; the **answerer sends** them.
enum PeerRole {
  /// Creates the offer and the data channel; receives frames.
  offerer,

  /// Accepts the offer; sends frames through the received channel.
  answerer,
}

/// One STUN or TURN server for NAT traversal.
///
/// Host candidates alone only reach same-host and LAN peers; STUN lets
/// peers on different networks find each other directly, and TURN relays
/// the traffic when no direct path exists (symmetric NATs, restrictive
/// firewalls). Credentials apply to TURN (`turn:` URLs), not STUN.
@immutable
final class IceServerSpec {
  /// Creates a server spec.
  const IceServerSpec({
    required this.urls,
    this.username,
    this.credential,
  });

  /// A public STUN server, for quick cross-network reachability.
  static const IceServerSpec stunGoogle = IceServerSpec(
    urls: ['stun:stun.l.google.com:19302'],
  );

  /// STUN or TURN URL(s): `stun:host:port`,
  /// `turn:host:port?transport=udp`, etc.
  final List<String> urls;

  /// TURN username (ignored for STUN).
  final String? username;

  /// TURN credential — short-lived tokens are the recommended shape;
  /// never bake long-lived secrets into clients.
  final String? credential;

  Map<String, Object?> toJson() => {
        'urls': urls,
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };
}

/// A peer whose data channel is open and whose signaling loop is wired.
@immutable
final class WebrtcPeer {
  /// Creates the handle.
  const WebrtcPeer({
    required this.peerId,
    required this.role,
    required this.opened,
  });

  /// Sidecar peer id.
  final String peerId;

  /// This side's role.
  final PeerRole role;

  /// Completes when the data channel is open on this side.
  final Future<void> opened;
}

/// Establishes peers across a [SignalingChannel], wired to a sidecar.
///
/// One factory per sidecar process; both sides point their factories at
/// the same signaling channel pair. ICE candidates trickle through the
/// signaling plane; frame bytes never touch it.
class SidecarPeerFactory {
  /// Creates a factory. [label] distinguishes the side in logs.
  SidecarPeerFactory({
    required SidecarClient sidecar,
    required SignalingChannel signaling,
    this.label = 'side',
    this.iceServers = const [],
  }) : _sidecar = sidecar,
       _signaling = signaling {
    _subscription = sidecar.events.listen(_onSidecarEvent);
    _signalSubscription = signaling.messages.listen(_onSignal);
  }

  final SidecarClient _sidecar;
  final SignalingChannel _signaling;
  final String label;
  final List<IceServerSpec> iceServers;
  final _peers = <String, _PeerState>{};
  final _pendingOffers = <String, String>{};
  StreamSubscription<SidecarEvent>? _subscription;
  StreamSubscription<SignalMessage>? _signalSubscription;
  bool _closed = false;

  /// Brings up a peer with [role]; resolves once its channel is open.
  Future<WebrtcPeer> createPeer(String peerId, PeerRole role) async {
    if (_closed) throw StateError('SidecarPeerFactory is closed');
    final state = _PeerState(role);
    _peers[peerId] = state;
    await _sidecar.request('create_peer', {
      'peerId': peerId,
      if (role == PeerRole.answerer) 'createChannel': false,
    });
    switch (role) {
      case PeerRole.offerer:
        final offer = await _sidecar.request('create_offer', {
          'peerId': peerId,
        });
        await _signaling.send(SdpOffer(peerId, offer['sdp']! as String));
      case PeerRole.answerer:
        // An offer that arrived before this peer existed is buffered;
        // answer it now.
        final pending = _pendingOffers.remove(peerId);
        if (pending != null) {
          await _answer(peerId, pending);
        }
    }
    await state.opened.future.timeout(const Duration(seconds: 20));
    return WebrtcPeer(peerId: peerId, role: role, opened: state.opened.future);
  }

  /// Stops the signaling pump. Peers keep living in their sidecars.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _signalSubscription?.cancel();
  }

  void _onSidecarEvent(SidecarEvent event) {
    final peerId = event.payload['peerId'] as String?;
    if (peerId == null) return;
    final state = _peers[peerId];
    if (state == null) return;
    switch (event.kind) {
      case 'open':
        state.opened.complete();
      case 'ice':
        final candidate = event.payload['candidate'];
        unawaited(
          _signaling.send(
            IceCandidate(
              peerId,
              candidate is Map<String, Object?> ? candidate : null,
            ),
          ),
        );
    }
  }

  void _onSignal(SignalMessage message) {
    final state = _peers[message.peerId];
    switch (message) {
      case SdpOffer(:final sdp):
        if (state == null) {
          // The answerer side has not created its peer yet; buffer.
          _pendingOffers[message.peerId] = sdp;
          return;
        }
        if (state.role != PeerRole.answerer) return;
        unawaited(_answer(message.peerId, sdp));
      case SdpAnswer(:final sdp):
        if (state == null || state.role != PeerRole.offerer) return;
        unawaited(
          _sidecar.request('accept_answer', {
            'peerId': message.peerId,
            'sdp': sdp,
          }),
        );
      case IceCandidate(:final candidate):
        if (state == null) return;
        unawaited(
          _sidecar.request('add_remote_ice', {
            'peerId': message.peerId,
            'candidate': candidate,
          }),
        );
    }
  }

  Future<void> _answer(String peerId, String offerSdp) async {
    final answer = await _sidecar.request('accept_offer', {
      'peerId': peerId,
      'sdp': offerSdp,
    });
    await _signaling.send(SdpAnswer(peerId, answer['sdp']! as String));
  }
}

class _PeerState {
  _PeerState(this.role);

  final PeerRole role;
  final opened = Completer<void>();
}
