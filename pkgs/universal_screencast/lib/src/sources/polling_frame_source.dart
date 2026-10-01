import 'dart:async';
import 'dart:typed_data';

import '../frame.dart';
import '../frame_source.dart';

/// Paced screenshot polling for any target that can produce a frame on
/// demand: CDP pages, WebDriver sessions, VM-service drivers, or the
/// OS-native tier.
///
/// Pacing and single-flight live here, at the source: a [grab] that is
/// slower than [interval] simply skips ticks instead of queueing work —
/// the source-pacing rule, encoded.
class PollingFrameSource implements FrameSource {
  /// Creates a source that calls [grab] every [_interval].
  ///
  /// [_revisionProbe] lets the pipeline correlate frames to target
  /// revisions when the underlying driver can report one.
  PollingFrameSource(
    this._grab, {
    this._interval = const Duration(milliseconds: 250),
    this._contentType = 'image/jpeg',
    this._revisionProbe,
  });

  final Future<Uint8List> Function() _grab;
  final Duration _interval;
  final String _contentType;
  final int Function()? _revisionProbe;
  final _frames = StreamController<Frame>.broadcast();
  Timer? _timer;
  bool _capturing = false;
  bool _stopped = false;
  int _sequence = 0;

  @override
  String get id => 'polling';

  @override
  SourceCapabilities get capabilities => const SourceCapabilities();

  @override
  Stream<Frame> start() {
    if (_stopped) throw StateError('PollingFrameSource is stopped');
    if (_timer != null) return _frames.stream;
    _timer = Timer.periodic(_interval, (_) => _capture());
    return _frames.stream;
  }

  Future<void> _capture() async {
    if (_capturing || _stopped) return;
    _capturing = true;
    try {
      final bytes = await _grab();
      if (_stopped) return;
      _frames.add(
        Frame(
          sourceId: id,
          sequence: ++_sequence,
          revision: _revisionProbe?.call() ?? 0,
          bytes: bytes,
          contentType: _contentType,
          capturedAt: DateTime.now().toUtc(),
        ),
      );
    } on Object catch (error) {
      _frames.addError(error);
    } finally {
      _capturing = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    await _frames.close();
  }
}
