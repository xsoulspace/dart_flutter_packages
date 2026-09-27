import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_screencast/universal_screencast.dart';
import 'package:universal_webrtc_raw/universal_webrtc_raw.dart';

/// Sends screencast frames through the sidecar's WebRTC data channel.
///
/// Bind to an **answerer** peer (see the frame-flow contract in the
/// package docs): the receiving side is the offerer. Frames are handed
/// to the sidecar as base64; the sidecar chunks them into the
/// `FrameChunkCodec` envelope over SCTP.
class WebrtcDataChannelSink implements FrameSink {
  /// Creates a sink over [_sidecar] for [_peerId].
  WebrtcDataChannelSink({
    required this._sidecar,
    required this._peerId,
  });

  final SidecarClient _sidecar;
  final String _peerId;
  bool _closed = false;

  @override
  String get id => 'webrtc-dc';

  @override
  List<String> get acceptedContentTypes => const ['*'];

  @override
  Future<void> push(Frame frame) async {
    if (_closed) throw SinkClosedException(id);
    await _sidecar.request('send_frame', {
      'peerId': _peerId,
      'seq': frame.sequence,
      'revision': frame.revision,
      'bytes': base64Encode(frame.bytes),
    });
  }

  @override
  Future<void> close({Object? error}) async {
    if (_closed) return;
    _closed = true;
    try {
      await _sidecar.request('close_peer', {'peerId': _peerId});
    } on Object {
      // The sidecar may already be gone; close is best effort.
    }
  }
}

/// Typed alias keeping [Uint8List] in scope for implementers.
typedef FrameBytes = Uint8List;
