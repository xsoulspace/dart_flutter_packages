import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_screencast/universal_screencast.dart';
import 'package:universal_webrtc/universal_webrtc.dart';
import 'package:universal_webrtc_raw/universal_webrtc_raw.dart';

Future<void> main() async {
  final binary =
      '../universal_webrtc_raw/rust/webrtc_sidecar/target/release/xs-webrtc-sidecar';
  void log(Object line) => stdout.writeln('[dbg] $line');

  final source = SidecarClient(
    await ProcessSidecarTransport.start(
      binary: binary,
      onError: (line) => stdout.writeln('[src-err] $line'),
    ),
  );
  final viewer = SidecarClient(
    await ProcessSidecarTransport.start(
      binary: binary,
      onError: (line) => stdout.writeln('[view-err] $line'),
    ),
  );
  log('handshakes: ${await source.handshake} / ${await viewer.handshake}');

  viewer.events.listen((e) => log('view event: $e'));
  source.events.listen((e) => log('src event: $e'));

  final (sourceSignals, viewerSignals) = LoopbackSignalingChannel.pair();
  final sourceFactory = SidecarPeerFactory(
    sidecar: source,
    signaling: sourceSignals,
    label: 'source',
    iceServers: const [IceServerSpec.stunGoogle],
  );
  final viewerFactory = SidecarPeerFactory(
    sidecar: viewer,
    signaling: viewerSignals,
    label: 'viewer',
    iceServers: const [IceServerSpec.stunGoogle],
  );

  final peers = await Future.wait([
    viewerFactory.createPeer('pair-1', PeerRole.offerer),
    sourceFactory.createPeer('pair-1', PeerRole.answerer),
  ]).timeout(const Duration(seconds: 30));
  log('peers created: ${peers.map((p) => p.peerId)}');
  await Future.wait<void>(peers.map((peer) => peer.opened)).timeout(
    const Duration(seconds: 30),
  );
  log('peers opened');

  final frames = viewer.events
      .where((event) => event.kind == 'frame')
      .take(1)
      .toList();
  final sink = WebrtcDataChannelSink(sidecar: source, peerId: 'pair-1');
  await sink.push(
    Frame(
      sourceId: 'webrtc',
      sequence: 1,
      revision: 0,
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/jpeg',
      capturedAt: DateTime.now().toUtc(),
    ),
  );
  log('frame pushed; waiting 15s for frame event...');
  List<SidecarEvent> received;
  try {
    received = await frames.timeout(const Duration(seconds: 15));
    } on TimeoutException {
    log('TIMEOUT waiting for frame event');
    received = const <SidecarEvent>[];
  }
  await sink.close();
  await sourceFactory.close();
  await viewerFactory.close();
  exit(0);
}
