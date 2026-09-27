import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// One signaling-plane message.
@immutable
sealed class SignalMessage {
  /// Creates a message for [peerId].
  const SignalMessage(this.peerId);

  /// The peer this message concerns.
  final String peerId;

  Map<String, Object?> toJson();

  /// Decodes a signaling envelope produced by [toJson].
  static SignalMessage fromJson(Map<String, Object?> json) {
    final peerId = json['peerId'] as String? ?? '';
    switch (json['kind']) {
      case 'offer':
        return SdpOffer(peerId, json['sdp'] as String? ?? '');
      case 'answer':
        return SdpAnswer(peerId, json['sdp'] as String? ?? '');
      case 'ice':
        return IceCandidate(
          peerId,
          json['candidate'] == null
              ? null
              : (json['candidate']! as Map).cast<String, Object?>(),
        );
      default:
        throw FormatException('unknown signal kind: $json');
    }
  }
}

/// An SDP offer for [peerId].
@immutable
final class SdpOffer extends SignalMessage {
  /// Creates the message.
  const SdpOffer(super.peerId, this.sdp);

  /// SDP text.
  final String sdp;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'offer',
    'peerId': peerId,
    'sdp': sdp,
  };
}

/// An SDP answer for [peerId].
@immutable
final class SdpAnswer extends SignalMessage {
  /// Creates the message.
  const SdpAnswer(super.peerId, this.sdp);

  /// SDP text.
  final String sdp;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'answer',
    'peerId': peerId,
    'sdp': sdp,
  };
}

/// A trickle ICE candidate (or end-of-candidates when [candidate] is
/// null) for [peerId].
@immutable
final class IceCandidate extends SignalMessage {
  /// Creates the message.
  const IceCandidate(super.peerId, this.candidate);

  /// Candidate in RTCIceCandidateInit shape, or null for end-of-candidates.
  final Map<String, Object?>? candidate;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'ice',
    'peerId': peerId,
    'candidate': candidate,
  };
}

/// The control-plane transport: signaling only, never frame bytes.
abstract interface class SignalingChannel {
  /// Sends one message.
  Future<void> send(SignalMessage message);

  /// Incoming messages.
  Stream<SignalMessage> get messages;

  /// Closes the channel. Idempotent.
  Future<void> close();
}

/// A pair of in-memory channels wired to each other — same-host peers
/// and tests. Production peers use [WebSocketSignalingChannel].
final class LoopbackSignalingChannel implements SignalingChannel {
  LoopbackSignalingChannel._();
  LoopbackSignalingChannel? _peer;
  final _messages = StreamController<SignalMessage>.broadcast();
  bool _closed = false;

  /// Creates two channels wired to each other.
  static (LoopbackSignalingChannel, LoopbackSignalingChannel) pair() {
    final first = LoopbackSignalingChannel._();
    final second = LoopbackSignalingChannel._();
    first._peer = second;
    second._peer = first;
    return (first, second);
  }

  @override
  Future<void> send(SignalMessage message) async {
    if (_closed) throw StateError('signaling channel is closed');
    _peer!._messages.add(message);
  }

  @override
  Stream<SignalMessage> get messages => _messages.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _messages.close();
  }
}

/// JSON-lines signaling over a WebSocket URI (control plane only).
final class WebSocketSignalingChannel implements SignalingChannel {
  WebSocketSignalingChannel._(this._socket) {
    _subscription = _socket
        .map(
          (data) => jsonDecode(data as String) as Map<String, Object?>,
        )
        .map(SignalMessage.fromJson)
        .listen(_messages.add, onError: _messages.addError);
  }

  final WebSocket _socket;
  final _messages = StreamController<SignalMessage>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;

  /// Connects to a WebSocket signaling endpoint.
  static Future<WebSocketSignalingChannel> connect(Uri uri) async {
    final socket = await WebSocket.connect(uri.toString());
    return WebSocketSignalingChannel._(socket);
  }

  @override
  Future<void> send(SignalMessage message) async {
    if (_closed) throw StateError('signaling channel is closed');
    _socket.add(jsonEncode(message.toJson()));
  }

  @override
  Stream<SignalMessage> get messages => _messages.stream;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _socket.close();
    await _messages.close();
  }
}
