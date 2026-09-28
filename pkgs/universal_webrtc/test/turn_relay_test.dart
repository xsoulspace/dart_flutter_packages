import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_screencast/universal_screencast.dart';
import 'package:universal_webrtc/universal_webrtc.dart';
import 'package:universal_webrtc_raw/universal_webrtc_raw.dart';

Uint8List frameBytes([int fill = 0]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, fill, 0xFF, 0xD9]);

String? _turnServerBinary() =>
    Platform.environment['COTURN_BIN'] ?? 'turnserver';

/// Boots a loopback coturn and returns its process + parameters.
Future<({Process process, String uri, String user, String credential})>
_turnServer() async {
  final binary = _turnServerBinary()!;
  final port = int.parse(
    Platform.environment['XS_TURN_PORT'] ?? '3478',
  );
  final process = await Process.start(binary, [
    '--listening-ip=127.0.0.1',
    '--relay-ip=127.0.0.1',
    '--listening-port=$port',
    // The proof runs both peers on one host, so the relayed addresses
    // are loopback — coturn refuses that for production servers.
    '--allow-loopback-peers',
    '--no-multicast-peers',
    '--no-tls',
    '--no-dtls',
    '--min-port=64000',
    '--max-port=65000',
    '--user=xstest:xspass',
    '--realm=xs.test',
    '--no-stdout-log',
  ]);
  // coturn needs a moment to bind before the first allocation lands;
  // ICE retries absorb the remainder.
  await Future<void>.delayed(const Duration(seconds: 2));
  addTearDown(() {
    process.kill();
  });
  return (
    process: process,
    uri: 'turn:127.0.0.1:$port?transport=udp',
    user: 'xstest',
    credential: 'xspass',
  );
}

void main() {
  test(
    'relay-only peers connect through coturn and exchange frames (TURN proof)',
    () async {
      if (Platform.environment['XS_TEST_TURN'] != '1') {
        // Run with XS_TEST_TURN=1 (and coturn's `turnserver` on PATH or
        // COTURN_BIN) to exercise the real relay path.
        return;
      }
      final turn = await _turnServer();

      final source = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: Platform.environment['XS_WEBRTC_SIDECAR_BIN'] ??
              '../universal_webrtc_raw/rust/webrtc_sidecar/target/release/'
                  'xs-webrtc-sidecar',
          onError: (line) => stderr.writeln('[turn-sidecar-a] $line'),
        ),
      );
      final viewer = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: Platform.environment['XS_WEBRTC_SIDECAR_BIN'] ??
              '../universal_webrtc_raw/rust/webrtc_sidecar/target/release/'
                  'xs-webrtc-sidecar',
          onError: (line) => stderr.writeln('[turn-sidecar-b] $line'),
        ),
      );
      addTearDown(() async {
        await source.close();
        await viewer.close();
      });
      expect(await source.handshake, 'xs-webrtc-sidecar/1');
      expect(await viewer.handshake, 'xs-webrtc-sidecar/1');

      final iceServers = [
        IceServerSpec(
          urls: [turn.uri],
          username: turn.user,
          credential: turn.credential,
        ),
      ];

      final (sourceSignals, viewerSignals) = LoopbackSignalingChannel.pair();
      // relayOnly is the proof: gathering is restricted to relay
      // candidates, so no host/srflx path can short-circuit the test —
      // any connectivity is relay-mediated, by construction.
      final sourceFactory = SidecarPeerFactory(
        sidecar: source,
        signaling: sourceSignals,
        label: 'turn-source',
        iceServers: iceServers,
        relayOnly: true,
      );
      final viewerFactory = SidecarPeerFactory(
        sidecar: viewer,
        signaling: viewerSignals,
        label: 'turn-viewer',
        iceServers: iceServers,
        relayOnly: true,
      );
      addTearDown(() async {
        await sourceFactory.close();
        await viewerFactory.close();
      });

      final candidates = <String>[];
      void collectCandidates(SidecarClient client) {
        client.events
            .where((event) => event.kind == 'ice')
            .listen(
              (event) =>
                  candidates.add('${event.payload['candidate']}'),
            );
      }

      collectCandidates(source);
      collectCandidates(viewer);

      final peers = await Future.wait([
        viewerFactory.createPeer('turn-pair', PeerRole.offerer),
        sourceFactory.createPeer('turn-pair', PeerRole.answerer),
      ]).timeout(const Duration(seconds: 45));
      await Future.wait<void>(
        peers.map((peer) => peer.opened),
      ).timeout(const Duration(seconds: 60));

      // The relay was genuinely in the path: both sides gathered a
      // `typ relay` candidate and nothing else carried the connection
      // (relay-only policy excluded host/srflx).
      expect(
        candidates.any((candidate) => candidate.contains('typ relay')),
        isTrue,
        reason: 'no relay candidate gathered: $candidates',
      );

      // Frames cross the relay in both directions.
      final payload = Uint8List.fromList(
        List.generate(
          FrameChunkCodec.chunkPayloadLimit + 24,
          (i) => i % 256,
        ),
      );
      final atViewer = viewer.events
          .where((event) => event.kind == 'frame')
          .take(1)
          .toList();
      final sourceSink = WebrtcDataChannelSink(
        sidecar: source,
        peerId: 'turn-pair',
      );
      await sourceSink.push(
        Frame(
          sourceId: 'turn',
          sequence: 1,
          revision: 0,
          bytes: frameBytes(7),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      await sourceSink.push(
        Frame(
          sourceId: 'turn',
          sequence: 2,
          revision: 0,
          bytes: payload,
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      final gotAtViewer = await atViewer.timeout(const Duration(seconds: 30));
      expect(gotAtViewer, hasLength(2));
      expect(
        base64Decode(gotAtViewer.last.payload['bytes']! as String),
        payload,
      );

      final atSource = source.events
          .where((event) => event.kind == 'frame')
          .take(1)
          .toList();
      final viewerSink = WebrtcDataChannelSink(
        sidecar: viewer,
        peerId: 'turn-pair',
      );
      await viewerSink.push(
        Frame(
          sourceId: 'turn',
          sequence: 3,
          revision: 9,
          bytes: frameBytes(8),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      final gotAtSource = await atSource.timeout(const Duration(seconds: 30));
      expect(
        base64Decode(gotAtSource.single.payload['bytes']! as String),
        frameBytes(8),
      );
      expect(gotAtSource.single.payload['revision'], 9);
      await sourceSink.close();
      await viewerSink.close();
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
