import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh_transport/'
    'universal_storage_mesh_transport.dart';

import 'pairing_service.dart';

/// Composable lifecycle for a signed `mesh-pair/v1` exchange.
///
/// The SDK owns payload encoding, cryptographic verification, and peer
/// registration. Hosts own QR rendering/scanning and relay configuration.
final class MeshPairingSession {
  MeshPairingSession({
    required this.selfId,
    required this.identityKeyPair,
    Future<SimpleKeyPair>? ephemeralKeyPair,
    this.transportHint,
    this.applicationData,
  }) : _ephemeralKeyPair = ephemeralKeyPair ?? X25519().newKeyPair();

  final String selfId;
  final SimpleKeyPair identityKeyPair;
  final Future<SimpleKeyPair> _ephemeralKeyPair;

  /// Connection hint embedded in the signed advertisement (e.g. a relay
  /// endpoint scanners should connect to).
  final String? transportHint;

  /// Optional signed application data embedded in the advertisement
  /// (ADR 0072) — opaque to the mesh; consumers own shape and trust.
  final Map<String, Object?>? applicationData;

  Uint8List? _payload;
  var _accepted = false;

  /// The signed advertisement to render as a QR code.
  Future<Uint8List> createQrPayload() async {
    if (_accepted) {
      throw StateError('Pairing session already accepted a peer');
    }
    return _payload ??= await PairingService.buildQrPayload(
      identityKeyPair: identityKeyPair,
      ephemeralKeyPair: await _ephemeralKeyPair,
      peerId: selfId,
      transportHint: transportHint,
      applicationData: applicationData,
    );
  }

  String pairingCode() => base64Encode(_payload!);

  /// Verifies and accepts an incoming signed advertisement.
  ///
  /// The returned record carries the peer's advertised connection hint
  /// under the `ws` key of [MeshPeerRecord.endpointHints] when present.
  Future<MeshPeerRecord> acceptQrPayload(final Uint8List qrPayload) async {
    if (_accepted) {
      throw StateError('Pairing session already accepted a peer');
    }
    final result = await PairingService.acceptQrPayload(
      qrPayload: qrPayload,
      peerIdentityKey: PairingIdentity.extractIdentityKey(qrPayload),
      ownEphemeralKeyPair: await X25519().newKeyPair(),
      ourPeerId: selfId,
    );
    _accepted = true;
    return MeshPeerRecord(
      peerId: result.peerId,
      displayName: result.peerId,
      identityKey: result.peerIdentityKey,
      // The signed application data rides the record under 'data'
      // (ADR 0072) — JSON-encoded to keep the wire shape
      // (Map<String, String>) intact; consumers own the decode.
      endpointHints: {
        if (result.transportHint != null && result.transportHint!.isNotEmpty)
          'ws': result.transportHint!,
        if (result.applicationData != null)
          'data': jsonEncode(result.applicationData),
      },
    );
  }
}

/// Canonical access to the self-describing identity key embedded in
/// `mesh-pair/v1`. This keeps example compatibility explicit while the
/// signature remains authoritative.
extension type const PairingIdentity._(Uint8List _value) {
  static Uint8List extractIdentityKey(final Uint8List qrPayload) =>
      Uint8List.fromList(PairingService.extractIdentityKey(qrPayload));
}
