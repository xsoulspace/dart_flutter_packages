import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_webrtc_raw/universal_webrtc_raw.dart';

/// In-memory sidecar stand-in speaking `xs-webrtc-sidecar/1` on a
/// scriptable transport.
class FakeSidecarTransport implements SidecarTransport {
  final _controller = StreamController<String>.broadcast();
  final List<String> written = [];
  int _id = 0;

  /// When set, the next request is answered with this error text.
  String? failNext;

  @override
  Stream<String> get lines => _controller.stream;

  /// Simulates a sidecar message.
  void emitLine(String line) => _controller.add(line);

  @override
  Future<void> writeLine(String line) async {
    written.add(line);
    final message = jsonDecode(line) as Map<String, Object?>;
    final op = message['op'] as String?;
    if (op == null) return;
    final id = message['id']! as int;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      emitLine(jsonEncode({'id': id, 'error': failure}));
      return;
    }
    switch (op) {
      case 'send_frame':
        _id++;
        emitLine(
          jsonEncode({
            'event': 'frame',
            'peerId': message['peerId'],
            'seq': message['seq'],
            'revision': message['revision'],
            'bytes': message['bytes'],
          }),
        );
        emitLine(
          jsonEncode({
            'id': id,
            'result': {'seq': message['seq'], 'chunks': 1},
          }),
        );
      default:
        _id++;
        emitLine(
          jsonEncode({
            'id': id,
            'result': {'ok': op},
          }),
        );
    }
  }

  @override
  Future<void> kill() async {
    await _controller.close();
  }
}

void main() {
  test('handshake completes and requests correlate', () async {
    final transport = FakeSidecarTransport();
    final client = SidecarClient(transport);
    transport.emitLine(jsonEncode({'sidecar': 'xs-webrtc-sidecar/1'}));
    expect(await client.handshake, 'xs-webrtc-sidecar/1');
    final results = await Future.wait([
      client.request('create_peer', {'peerId': 'p1'}),
      client.request('create_offer', {'peerId': 'p1'}),
    ]);
    expect(results[0]['ok'], 'create_peer');
    expect(results[1]['ok'], 'create_offer');
  });

  test('error responses surface as SidecarException', () async {
    final transport = FakeSidecarTransport();
    final client = SidecarClient(transport);
    transport.emitLine(jsonEncode({'sidecar': 'xs-webrtc-sidecar/1'}));
    await client.handshake;
    transport.failNext = 'unknown peer: nope';
    await expectLater(
      client.request('send_frame', {'peerId': 'nope'}),
      throwsA(isA<SidecarException>()),
    );
  });

  test('events reach the broadcast stream and frames round-trip', () async {
    final transport = FakeSidecarTransport();
    final client = SidecarClient(transport);
    transport.emitLine(jsonEncode({'sidecar': 'xs-webrtc-sidecar/1'}));
    await client.handshake;

    final events = client.events.take(1).toList();
    await client.request('send_frame', {
      'peerId': 'p1',
      'seq': 3,
      'revision': 1,
      'bytes': 'AAEC',
    });
    final received = await events.timeout(const Duration(seconds: 5));
    expect(received.map((e) => e.kind), ['frame']);
    expect(received.single.payload['seq'], 3);
    final payload = jsonDecode(transport.written.last) as Map<String, Object?>;
    expect(payload['op'], 'send_frame');
    expect(payload['seq'], 3);
  });

  test('close fails pending requests', () async {
    final transport = FakeSidecarTransport();
    final client = SidecarClient(transport);
    transport.emitLine(jsonEncode({'sidecar': 'xs-webrtc-sidecar/1'}));
    await client.handshake;
    await client.close();
    expect(() => client.request('ping'), throwsStateError);
  });
}
