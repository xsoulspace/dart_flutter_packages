import 'dart:convert';
import 'dart:typed_data';

/// Wire envelope for addressed WebSocket relay sessions.
///
/// A relay is an untrusted router, never a sync authority. The inner
/// payload remains opaque to the relay and is unchanged from the direct
/// mesh protocol.
final class AddressedRelayProtocol {
  static const version = 1;

  static const registerKind = 'register';
  static const openKind = 'open';
  static const dataKind = 'data';

  static Uint8List encode({
    required final String fromPeerId,
    required final String toPeerId,
    required final List<int> payload,
    final String kind = dataKind,
  }) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': version,
        'from': fromPeerId,
        'to': toPeerId,
        'kind': kind,
        'payload': base64Encode(payload),
      }),
    ),
  );

  static ({
    String fromPeerId,
    String toPeerId,
    Uint8List payload,
    String kind,
  })
  decode(final List<int> bytes) {
    final raw = jsonDecode(utf8.decode(bytes)) as Map<dynamic, dynamic>;
    if (raw['v'] != version) {
      throw ArgumentError('Unsupported relay protocol: ${raw['v']}');
    }
    return (
      fromPeerId: raw['from'] as String,
      toPeerId: raw['to'] as String,
      payload: base64Decode(raw['payload'] as String),
      kind: raw['kind'] as String? ?? dataKind,
    );
  }
}
