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

/// Resolves the sidecar binary: env override first, then the workspace
/// build output. Null means "not built" — the integration test skips.
String? sidecarBinaryPath() {
  final override = Platform.environment['XS_WEBRTC_SIDECAR_BIN'];
  if (override != null && File(override).existsSync()) return override;
  const candidate =
      '../universal_webrtc_raw/rust/webrtc_sidecar/target/release/'
      'xs-webrtc-sidecar';
  if (File(candidate).existsSync()) return candidate;
  return null;
}

void main() {
  group('FrameChunkCodec', () {
    test('small frames are a single first|last chunk', () {
      final chunks = FrameChunkCodec.encode(
        sequence: 7,
        revision: 2,
        payload: frameBytes(9),
      );
      expect(chunks, hasLength(1));
      final reassembler = FrameReassembler();
      final frame = reassembler.accept(chunks.single)!;
      expect(frame.sequence, 7);
      expect(frame.revision, 2);
      expect(frame.bytes, frameBytes(9));
    });

    test('large frames reassemble in order', () {
      final payload = Uint8List.fromList(
        List.generate(
          FrameChunkCodec.chunkPayloadLimit * 2 + 10,
          (i) => i % 256,
        ),
      );
      final chunks = FrameChunkCodec.encode(
        sequence: 1,
        revision: 0,
        payload: payload,
      );
      expect(chunks.length, 3);
      final reassembler = FrameReassembler();
      FrameFrameResult? frame;
      for (final chunk in chunks) {
        frame = reassembler.accept(chunk);
      }
      expect(frame, isNotNull);
      expect(frame!.bytes, payload);
    });

    test('garbage chunks are ignored', () {
      final reassembler = FrameReassembler();
      expect(reassembler.accept(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('LoopbackSignalingChannel', () {
    test('delivers signals both ways', () async {
      final (first, second) = LoopbackSignalingChannel.pair();
      final received = second.messages.take(1).toList();
      await first.send(const SdpOffer('p1', 'v=0'));
      final messages = await received.timeout(const Duration(seconds: 5));
      expect(messages.single, isA<SdpOffer>());
      await first.close();
      await second.close();
    });
  });

  test(
    'two sidecars establish a WebRTC data channel and exchange frames',
    () async {
      final binary = sidecarBinaryPath();
      if (binary == null) {
        // Build with: cd universal_webrtc_raw/rust/webrtc_sidecar &&
        // cargo build --release
        return;
      }

      // Source (answerer, sends frames) and viewer (offerer, receives).
      final source = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: binary,
          onError: (line) => stderr.writeln('[sidecar] $line'),
        ),
      );
      final viewer = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: binary,
          onError: (line) => stderr.writeln('[sidecar] $line'),
        ),
      );
      addTearDown(() async {
        await source.close();
        await viewer.close();
      });
      expect(await source.handshake, 'xs-webrtc-sidecar/1');
      expect(await viewer.handshake, 'xs-webrtc-sidecar/1');

      final (sourceSignals, viewerSignals) = LoopbackSignalingChannel.pair();
      // The frame source dials out through TURN/STUN when pairing
      // crosses a network; host-only still works for the loopback proof.
      final sourceFactory = SidecarPeerFactory(
        sidecar: source,
        signaling: sourceSignals,
        label: 'source',
        iceServers: const [
          IceServerSpec.stunGoogle,
        ],
      );
      final viewerFactory = SidecarPeerFactory(
        sidecar: viewer,
        signaling: viewerSignals,
        label: 'viewer',
      );
      addTearDown(() async {
        await sourceFactory.close();
        await viewerFactory.close();
      });

      // Both sides must start before signaling flows: the offerer's
      // createPeer does not return until the answerer accepted its offer.
      final peers = await Future.wait([
        viewerFactory.createPeer('pair-1', PeerRole.offerer),
        sourceFactory.createPeer('pair-1', PeerRole.answerer),
      ]).timeout(const Duration(seconds: 30));
      await Future.wait<void>(
        peers.map((peer) => peer.opened),
      ).timeout(const Duration(seconds: 30));

      // Frames flow answerer → offerer per the frame-flow contract.
      final frames = viewer.events
          .where((event) => event.kind == 'frame')
          .take(3)
          .toList();
      final sink = WebrtcDataChannelSink(sidecar: source, peerId: 'pair-1');
      await sink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 1,
          revision: 0,
          bytes: frameBytes(1),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      await sink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 2,
          revision: 0,
          bytes: frameBytes(2),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      await sink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 3,
          revision: 5,
          bytes: frameBytes(3),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      final received = await frames.timeout(const Duration(seconds: 20));
      expect(received, hasLength(3));
      // The sidecar reassembles chunks; event payloads are raw frames.
      final decoded = received
          .map((event) => base64Decode(event.payload['bytes']! as String))
          .toList();
      expect(decoded, [frameBytes(1), frameBytes(2), frameBytes(3)]);
      expect(received.last.payload['revision'], 5);
      await sink.close();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'frames flow offerer → answerer too (A→B through the created channel)',
    () async {
      final binary = sidecarBinaryPath();
      if (binary == null) return;

      // Viewer dials (offerer, sends); source answers (receiver).
      final source = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: binary,
          onError: (line) => stderr.writeln('[sidecar-a] $line'),
        ),
      );
      final viewer = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: binary,
          onError: (line) => stderr.writeln('[sidecar-b] $line'),
        ),
      );
      addTearDown(() async {
        await source.close();
        await viewer.close();
      });
      expect(await source.handshake, 'xs-webrtc-sidecar/1');
      expect(await viewer.handshake, 'xs-webrtc-sidecar/1');

      final (sourceSignals, viewerSignals) = LoopbackSignalingChannel.pair();
      final sourceFactory = SidecarPeerFactory(
        sidecar: source,
        signaling: sourceSignals,
        label: 'source-ab',
      );
      final viewerFactory = SidecarPeerFactory(
        sidecar: viewer,
        signaling: viewerSignals,
        label: 'viewer-ab',
        iceServers: const [IceServerSpec.stunGoogle],
      );
      addTearDown(() async {
        await sourceFactory.close();
        await viewerFactory.close();
      });

      final peers = await Future.wait([
        viewerFactory.createPeer('pair-ab', PeerRole.offerer),
        sourceFactory.createPeer('pair-ab', PeerRole.answerer),
      ]).timeout(const Duration(seconds: 30));
      await Future.wait<void>(
        peers.map((peer) => peer.opened),
      ).timeout(const Duration(seconds: 30));

      // A→B: the OFFERER (viewer) sends; the answerer receives.
      final frames = source.events
          .where((event) => event.kind == 'frame')
          .take(2)
          .toList();
      final sink = WebrtcDataChannelSink(sidecar: viewer, peerId: 'pair-ab');
      await sink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 1,
          revision: 0,
          bytes: frameBytes(4),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      await sink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 2,
          revision: 0,
          bytes: frameBytes(5),
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      final received = await frames.timeout(const Duration(seconds: 20));
      expect(received, hasLength(2));
      final decoded = received
          .map((event) => base64Decode(event.payload['bytes']! as String))
          .toList();
      expect(decoded, [frameBytes(4), frameBytes(5)]);
      await sink.close();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'multi-chunk frames reassemble in BOTH directions',
    () async {
      final binary = sidecarBinaryPath();
      if (binary == null) return;

      final source = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: binary,
          onError: (line) => stderr.writeln('[sidecar-mc-a] $line'),
        ),
      );
      final viewer = SidecarClient(
        await ProcessSidecarTransport.start(
          binary: binary,
          onError: (line) => stderr.writeln('[sidecar-mc-b] $line'),
        ),
      );
      addTearDown(() async {
        await source.close();
        await viewer.close();
      });
      expect(await source.handshake, 'xs-webrtc-sidecar/1');
      expect(await viewer.handshake, 'xs-webrtc-sidecar/1');

      final (sourceSignals, viewerSignals) = LoopbackSignalingChannel.pair();
      final sourceFactory = SidecarPeerFactory(
        sidecar: source,
        signaling: sourceSignals,
        label: 'source-mc',
      );
      final viewerFactory = SidecarPeerFactory(
        sidecar: viewer,
        signaling: viewerSignals,
        label: 'viewer-mc',
        iceServers: const [IceServerSpec.stunGoogle],
      );
      addTearDown(() async {
        await sourceFactory.close();
        await viewerFactory.close();
      });

      final peers = await Future.wait([
        viewerFactory.createPeer('pair-mc', PeerRole.offerer),
        sourceFactory.createPeer('pair-mc', PeerRole.answerer),
      ]).timeout(const Duration(seconds: 30));
      await Future.wait<void>(
        peers.map((peer) => peer.opened),
      ).timeout(const Duration(seconds: 30));

      // One >16KB payload: three chunks on the wire.
      final payload = Uint8List.fromList(
        List.generate(
          FrameChunkCodec.chunkPayloadLimit * 2 + 10,
          (i) => i % 256,
        ),
      );

      // answerer → offerer
      final atViewer = viewer.events
          .where((event) => event.kind == 'frame')
          .take(1)
          .toList();
      final sourceSink = WebrtcDataChannelSink(
        sidecar: source,
        peerId: 'pair-mc',
      );
      await sourceSink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 1,
          revision: 0,
          bytes: payload,
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      final gotAtViewer = await atViewer.timeout(const Duration(seconds: 20));
      expect(
        base64Decode(gotAtViewer.single.payload['bytes']! as String),
        payload,
      );

      // offerer → answerer (the direction whose receive handler used to
      // skip reassembly)
      final atSource = source.events
          .where((event) => event.kind == 'frame')
          .take(1)
          .toList();
      final viewerSink = WebrtcDataChannelSink(
        sidecar: viewer,
        peerId: 'pair-mc',
      );
      await viewerSink.push(
        Frame(
          sourceId: 'webrtc',
          sequence: 2,
          revision: 0,
          bytes: payload,
          contentType: 'image/jpeg',
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      final gotAtSource = await atSource.timeout(const Duration(seconds: 20));
      expect(
        base64Decode(gotAtSource.single.payload['bytes']! as String),
        payload,
      );
      await sourceSink.close();
      await viewerSink.close();
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
