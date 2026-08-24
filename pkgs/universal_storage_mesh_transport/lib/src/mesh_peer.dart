import 'dart:convert';

import 'package:meta/meta.dart';

/// Stable identity of a paired mesh peer (ADR 0010 §3).
@immutable
final class MeshPeerRecord {
  const MeshPeerRecord({
    required this.peerId,
    required this.displayName,
    this.endpointHints = const <String, String>{},
    this.identityKey = const <int>[],
  }) : assert(peerId != ''),
       assert(displayName != '');

  factory MeshPeerRecord.fromJson(final Map<String, dynamic> json) =>
      MeshPeerRecord(
        peerId: json['peer_id'] as String,
        displayName: (json['display_name'] ?? '') as String,
        endpointHints:
            (json['endpoint_hints'] as Map<dynamic, dynamic>?)?.map(
              (final k, final v) => MapEntry(k as String, v as String),
            ) ??
            const {},
        identityKey: base64Decode(json['identity_key'] as String? ?? ''),
      );

  /// Stable random identity issued at first pairing.
  final String peerId;

  final String displayName;

  /// Transport-specific reconnection hints (e.g. mDNS service name).
  final Map<String, String> endpointHints;

  /// Ed25519 public identity key used to verify signed pairing payloads.
  final List<int> identityKey;

  Map<String, dynamic> toJson() => {
    'peer_id': peerId,
    'display_name': displayName,
    'endpoint_hints': endpointHints,
    if (identityKey.isNotEmpty) 'identity_key': base64Encode(identityKey),
  };

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is MeshPeerRecord && other.peerId == peerId);

  @override
  int get hashCode => peerId.hashCode;

  @override
  String toString() => 'MeshPeerRecord($peerId)';
}

/// A live advertisement from a reachable peer.
@immutable
final class MeshPeerDiscovery {
  const MeshPeerDiscovery({required this.peer, this.metadata = const {}});

  final MeshPeerRecord peer;
  final Map<String, String> metadata;
}

/// Raised when a transport cannot reach a peer. Sync is opportunistic
/// (ADR 0010 §4): callers treat this as "try again later", never as an
/// error condition for local operations.
final class MeshConnectionException implements Exception {
  const MeshConnectionException(this.peerId, this.reason);

  final String peerId;
  final String reason;

  @override
  String toString() =>
      'MeshConnectionException(peer: $peerId, reason: $reason)';
}
